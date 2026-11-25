import Foundation

@MainActor
final class MiNaAPI {
    static let origin = URL(string: "https://weieitgfketnpvvwvfpa.supabase.co")!
    static let key = "sb_publishable_OWdrFPOHFcFS3gE795ofWA_gHQST79E"
    private let slot: SessionStore.Slot

    init(slot: SessionStore.Slot = .password) {
        self.slot = slot
    }

    private final class AuthRedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let authTransport: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: AuthRedirectPolicy(), delegateQueue: nil)
    }()

    private var session: [String: Any]?
    private var renewal: Task<String, Error>?
    private var generation = UUID()
    var sessionExpired: (() -> Bool)?

    var userID: String {
        ((session?["user"] as? [String: Any])?["id"] as? String ?? "").lowercased()
    }

    nonisolated static func validEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+([.][A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?([.][A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"#
        guard email.utf8.count <= 254, let separator = email.firstIndex(of: "@"),
              email[..<separator].utf8.count <= 64 else { return false }
        return email.range(of: pattern, options: .regularExpression) == email.startIndex..<email.endIndex
    }

    func signIn(email: String, password: String, expectedOwner: String? = nil) async throws {
        close()
        _ = try await authenticate("token?grant_type=password", body: ["email": email, "password": password], expectedOwner: expectedOwner)
    }

    func signUp(email: String, password: String) async throws {
        close()
        _ = try await authenticate("signup", body: ["email": email, "password": password])
    }

    // Use the original device session until email verification and password setup both finish.
    func linkLegacyAccount(email: String, password: String) async throws -> Bool {
        close()
        session = try SessionStore.read(.legacy)
        guard slot == .legacy, session != nil else { throw MiNaIssue("The previous account is unavailable on this iPhone.") }
        let token = try await accessToken()
        guard var user = try await request("/auth/v1/user", method: "GET", token: token) as? [String: Any],
              (user["id"] as? String)?.lowercased() == userID else { throw MiNaIssue("Could not verify your previous account.") }
        if (user["email"] as? String ?? "").isEmpty {
            user = try await updateUser(["email": email], token: token)
        }
        guard let confirmedEmail = user["email"] as? String, !confirmedEmail.isEmpty,
              user["email_confirmed_at"] is String else { return false }
        guard confirmedEmail.caseInsensitiveCompare(email) == .orderedSame else {
            throw MiNaIssue("Enter the email you verified for this account.")
        }
        do {
            _ = try await updateUser(["password": password], token: token)
        } catch let error as MiNaIssue where error.code == "same_password" {
            // A previous attempt may have set the password before its response arrived.
            // The caller still verifies it with a password grant for the original owner.
        }
        return true
    }

    private func updateUser(_ attributes: [String: String], token: String) async throws -> [String: Any] {
        let response = try await request("/auth/v1/user", method: "PUT",
            payload: JSONSerialization.data(withJSONObject: attributes), token: token)
        guard let user = response as? [String: Any], (user["id"] as? String)?.lowercased() == userID else {
            throw MiNaIssue("Your account update could not be confirmed.")
        }
        return user
    }

    func signOut() {
        let token = session?["access_token"] as? String
        close()
        if let token {
            Task { _ = try? await request("/auth/v1/logout?scope=local", method: "POST", token: token) }
        }
    }

    func close() {
        generation = UUID()
        renewal?.cancel()
        renewal = nil
        session = nil
    }

    private func authenticate(_ path: String, body: [String: Any], expectedOwner: String? = nil) async throws -> String {
        let initial = generation
        let response = try await request("/auth/v1/" + path, method: "POST", payload: JSONSerialization.data(withJSONObject: body))
        try Task.checkCancellation()
        guard generation == initial else { throw CancellationError() }
        return try saveSession(response, expectedOwner: expectedOwner)
    }

    private func saveSession(_ response: Any, expectedOwner: String? = nil) throws -> String {
        guard var fresh = response as? [String: Any],
              let token = fresh["access_token"] as? String, !token.isEmpty,
              fresh["refresh_token"] is String, try SessionStore.owner(fresh) != "Device" else {
            throw MiNaIssue("Your sign-in could not be restored.")
        }
        if let expectedOwner, try SessionStore.owner(fresh).lowercased() != expectedOwner {
            throw MiNaIssue("Could not verify the account for this session.")
        }
        if fresh["expires_at"] == nil {
            fresh["expires_at"] = Date().timeIntervalSince1970 + (fresh["expires_in"] as? Double ?? 0)
        }
        if slot == .legacy { try SessionStore.write(fresh, to: .legacy) }
        session = fresh
        return token
    }

    func accessToken() async throws -> String {
        guard let session, let refresh = session["refresh_token"] as? String else { throw MiNaIssue("Sign in to continue.") }
        if let expires = session["expires_at"] as? Double, expires > Date().timeIntervalSince1970 + 45,
           let token = session["access_token"] as? String { return token }
        if let renewal { return try await renewal.value }
        let owner = userID
        let task = Task {
            try await authenticate("token?grant_type=refresh_token", body: ["refresh_token": refresh], expectedOwner: owner)
        }
        let initial = generation
        renewal = task
        defer { if initial == generation { renewal = nil } }
        return try await task.value
    }

    private func request(_ path: String, method: String, payload: Data? = nil,
                         type: String = "application/json", token: String? = nil, prefer: String? = nil) async throws -> Any {
        guard let url = URL(string: Self.origin.absoluteString + path), url.host == Self.origin.host else {
            throw MiNaIssue("This service address is unavailable.")
        }
        let initial = generation
        var request = URLRequest(url: url)
        if path.hasPrefix("/auth/v1/") {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        }
        request.httpMethod = method
        request.httpBody = payload
        request.setValue(Self.key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if payload != nil { request.setValue(type, forHTTPHeaderField: "Content-Type") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let transport = path.hasPrefix("/auth/v1/") ? Self.authTransport : CloudInterface.transport
        let (data, response) = try await transport.data(for: request)
        guard initial == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw MiNaIssue("The service did not respond.") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = ["message", "msg", "error_description", "error"].compactMap { detail?[$0] as? String }.first
            let code = (detail?["error_code"] ?? detail?["code"]) as? String ?? ""
            let companionUnauthorized = http.statusCode == 401 && ["/functions/v1/companion-chat", "/rest/v1/rpc/open_companion_session"].contains(path)
            if companionUnauthorized || ["PT401", "user_not_found", "session_not_found", "refresh_token_not_found", "refresh_token_already_used"].contains(code),
               !userID.isEmpty {
                if sessionExpired?() == true { throw CancellationError() }
                throw MiNaIssue("Your session has expired. Please sign in again.")
            }
            if code.hasPrefix("PGRST") || code.range(of: "^[0-9A-Z]{5}$", options: .regularExpression) != nil && code != "P0001" {
                throw MiNaIssue("MiNa couldn’t complete the request. Please try again.", code: code)
            }
            throw MiNaIssue(reason ?? "The service could not complete this request (\(http.statusCode)).",
                            code: detail?["error_code"] as? String)
        }
        if method == "HEAD", prefer == "count=exact" {
            guard let total = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last,
                  let count = Int(total) else { throw MiNaIssue("The total could not be read.") }
            return count
        }
        if data.isEmpty { return NSNull() }
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    @discardableResult
    func rest(_ path: String, method: String = "GET", body: Any? = nil, prefer: String? = nil) async throws -> Any {
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await request("/rest/v1/" + path, method: method, payload: payload, token: accessToken(), prefer: prefer)
    }

    func report(_ target: String, kind: String, reason: String, details: String, operation: UUID) async throws -> String {
        let id = operation.uuidString.lowercased()
        let message = String((reason + (details.isEmpty ? "" : " · " + details)).prefix(1000))
        let result = try await rest("reports?select=id", method: "POST", body: ["id": id, "reporter_id": userID, "target_id": target, "target_kind": kind, "reason": message], prefer: "return=representation,resolution=ignore-duplicates")
        if let receipt = (result as? [[String: Any]])?.first?["id"] as? String { return receipt }
        guard let receipt = try await rows("reports?select=id&reporter_id=eq." + userID + "&id=eq." + id).first?["id"] as? String else {
            throw MiNaIssue("Your report could not be confirmed. Please retry.")
        }
        return receipt
    }

    func isChatFriend(_ peer: String) async throws -> Bool {
        guard let result = try await rest("rpc/is_chat_friend", method: "POST", body: ["p_peer": peer]) as? Bool else {
            throw MiNaIssue("Could not verify this friendship.")
        }
        return result
    }

    func rows(_ path: String) async throws -> [[String: Any]] {
        guard let result = try await rest(path) as? [[String: Any]] else { throw MiNaIssue("The records could not be read.") }
        return result
    }

    func mediaURL(_ path: String) async throws -> URL {
        let result = try await request("/storage/v1/object/sign/mina-media/" + path, method: "POST",
            payload: JSONSerialization.data(withJSONObject: ["expiresIn": 900]), token: accessToken())
        guard let row = result as? [String: Any], let suffix = row["signedURL"] as? String, suffix.hasPrefix("/"),
              let url = URL(string: Self.origin.absoluteString + "/storage/v1" + suffix) else {
            throw MiNaIssue("The media link could not be opened.")
        }
        return url
    }

    func removeUnusedCapture(_ path: String, owner: String) async throws {
        guard owner == userID, path.hasPrefix(owner + "/") else { return }
        // Only paths generated for this owner's unfinished audio/video captures are eligible.
        let filename = String(path.dropFirst(owner.count + 1))
        let name = (filename as NSString).deletingPathExtension
        guard UUID(uuidString: name) != nil,
              ["mp4", "mov", "m4a"].contains((filename as NSString).pathExtension) else { return }
        let referenced = try await rows("entries?select=id&media_path=eq." + path + "&limit=1")
        guard referenced.isEmpty, owner == userID else { return }
        _ = try await request("/storage/v1/object/mina-media", method: "DELETE",
            payload: JSONSerialization.data(withJSONObject: ["prefixes": [path]]), token: accessToken())
    }

    func deleteEntry(_ id: String) async throws {
        let parameters = ["p_id": id]
        let result = try await rest("rpc/prepare_entry_deletion", method: "POST", body: parameters)
        guard let state = result as? [String: Any] else {
            throw MiNaIssue("Could not confirm the deletion. Please retry.")
        }
        if state["deleted"] as? Bool == true { return }
        guard let path = state["media_path"] as? String, path.hasPrefix(userID + "/"), !userID.isEmpty else {
            throw MiNaIssue("Could not verify the media owner.")
        }
        _ = try await request("/storage/v1/object/mina-media", method: "DELETE",
            payload: JSONSerialization.data(withJSONObject: ["prefixes": [path]]), token: accessToken())
        let completed = try await rest("rpc/finish_entry_deletion", method: "POST", body: parameters)
        guard completed as? Bool == true else { throw MiNaIssue("Could not confirm the deletion. Please retry.") }
    }

    func upload(_ data: Data, type: String, extension ext: String, id: String) async throws -> String {
        guard !userID.isEmpty, id.range(of: "^[A-Za-z0-9-]{1,70}$", options: .regularExpression) != nil,
              ext.range(of: "^[a-zA-Z0-9]{1,7}$", options: .regularExpression) != nil else {
            throw MiNaIssue("Invalid media name.")
        }
        let path = userID + "/" + id + "." + ext
        do {
            _ = try await request("/storage/v1/object/mina-media/" + path, method: "POST", payload: data, type: type, token: accessToken())
        } catch let error as MiNaIssue {
            guard error.code == "23505" || error.message.localizedCaseInsensitiveContains("already exists") || error.message.localizedCaseInsensitiveContains("duplicate") else { throw error }
            let signed = try await mediaURL(path)
            guard try await CloudInterface.bytes(signed) == data else {
                throw MiNaIssue("A different file already uses this media name.")
            }
        }
        return path
    }

    func companionReply(prompt: String, history: [[String: String]]) async throws -> String {
        let turns = history.suffix(6).compactMap { item -> [String: String]? in
            guard let role = item["role"], ["ai", "assistant", "user"].contains(role),
                  let text = item["text"] else { return nil }
            return ["role": role == "ai" ? "assistant" : role, "text": String(text.prefix(320))]
        }
        let payload: [String: Any] = ["prompt": prompt, "history": turns]
        let response = try await request("/functions/v1/companion-chat", method: "POST",
            payload: JSONSerialization.data(withJSONObject: payload), token: accessToken())
        guard let result = response as? [String: Any], let text = result["text"] as? String,
              !text.isEmpty else { throw MiNaIssue("No reply arrived. Try again.") }
        return text
    }

    func giftRequest(_ path: String, body: [String: Any], owner: String) async throws -> [String: Any] {
        let token = try await accessToken()
        guard !owner.isEmpty, owner == userID else { throw CancellationError() }
        let response = try await request(path, method: "POST",
            payload: JSONSerialization.data(withJSONObject: body), token: token)
        guard let result = response as? [String: Any] else { throw MiNaIssue("Gift authorization is unavailable.") }
        return result
    }

    func deleteAccount() async throws {
        _ = try await request("/functions/v1/delete-account", method: "POST",
            payload: JSONSerialization.data(withJSONObject: ["confirm": true]), token: accessToken())
    }
}

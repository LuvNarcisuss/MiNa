import Foundation

@MainActor
final class MiNaAPI {
    static let origin = URL(string: "https://nojpfyqctfwdshqnzudp.supabase.co")!
    static let key = "sb_publishable_XP-vFncNWgaYBdISstgW6w_2GjLgMDE"
    private var session: [String: Any]?
    private var renewal: Task<String, Error>?
    private var generation = UUID()

    var userID: String {
        ((session?["user"] as? [String: Any])?["id"] as? String ?? "").lowercased()
    }

    func signIn(allowCreation: Bool) async throws {
        session = try SessionStore.read()
        if session == nil {
            guard allowCreation else { throw MiNaIssue("Continue to sign in.") }
            _ = try await authenticate("signup", body: ["data": [String: String]()])
        }
        _ = try await rest("rpc/bootstrap", method: "POST", body: [:] as [String: String])
    }

    func close() {
        generation = UUID()
        renewal?.cancel()
        renewal = nil
        session = nil
    }

    private func authenticate(_ path: String, body: [String: Any]) async throws -> String {
        let initial = generation
        let response = try await request("/auth/v1/" + path, method: "POST", payload: JSONSerialization.data(withJSONObject: body))
        try Task.checkCancellation()
        guard generation == initial, var fresh = response as? [String: Any],
              let token = fresh["access_token"] as? String, !token.isEmpty,
              fresh["refresh_token"] is String, try SessionStore.owner(fresh) != "Device" else {
            throw MiNaIssue("Your sign-in could not be restored.")
        }
        if fresh["expires_at"] == nil {
            fresh["expires_at"] = Date().timeIntervalSince1970 + (fresh["expires_in"] as? Double ?? 0)
        }
        try SessionStore.write(fresh)
        session = fresh
        return token
    }

    func accessToken() async throws -> String {
        guard let session, let refresh = session["refresh_token"] as? String else { throw MiNaIssue("Sign in to continue.") }
        if let expires = session["expires_at"] as? Double, expires > Date().timeIntervalSince1970 + 45,
           let token = session["access_token"] as? String { return token }
        if let renewal { return try await renewal.value }
        let task = Task { try await authenticate("token?grant_type=refresh_token", body: ["refresh_token": refresh]) }
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
        request.httpMethod = method
        request.httpBody = payload
        request.setValue(Self.key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if payload != nil { request.setValue(type, forHTTPHeaderField: "Content-Type") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard initial == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw MiNaIssue("The service did not respond.") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = ["message", "msg", "error_description", "error"].compactMap { detail?[$0] as? String }.first
            throw MiNaIssue(reason ?? "The service could not complete this request (\(http.statusCode)).")
        }
        if data.isEmpty { return NSNull() }
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    @discardableResult
    func rest(_ path: String, method: String = "GET", body: Any? = nil, prefer: String? = nil) async throws -> Any {
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await request("/rest/v1/" + path, method: method, payload: payload, token: accessToken(), prefer: prefer)
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

    func upload(_ data: Data, type: String, extension ext: String, id: String) async throws -> String {
        guard !userID.isEmpty, id.range(of: "^[A-Za-z0-9-]{1,70}$", options: .regularExpression) != nil,
              ext.range(of: "^[a-zA-Z0-9]{1,7}$", options: .regularExpression) != nil else {
            throw MiNaIssue("Invalid media name.")
        }
        let path = userID + "/" + id + "." + ext
        do {
            _ = try await request("/storage/v1/object/mina-media/" + path, method: "POST", payload: data, type: type, token: accessToken())
        } catch let error as MiNaIssue {
            guard error.message.localizedCaseInsensitiveContains("already exists") || error.message.localizedCaseInsensitiveContains("duplicate") else { throw error }
        }
        return path
    }

    func deleteAccount() async throws {
        _ = try await request("/functions/v1/delete-account", method: "POST",
            payload: JSONSerialization.data(withJSONObject: ["confirm": true]), token: accessToken())
    }
}

import Foundation
import Security

enum SessionStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "MiNa") + ".session",
         kSecAttrAccount as String: "supabase"]
    }

    static func read() throws -> [String: Any]? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let session = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiNaIssue("Your saved sign-in could not be opened.")
        }
        return session
    }

    static func owner(_ session: [String: Any]?) throws -> String {
        guard let session else { return "Device" }
        guard let user = session["user"] as? [String: Any], let id = user["id"] as? String,
              let uuid = UUID(uuidString: id) else { throw MiNaIssue("This sign-in has no valid account identifier.") }
        return uuid.uuidString
    }

    static func write(_ session: [String: Any]?) throws {
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard [errSecSuccess, errSecItemNotFound].contains(status) else { throw MiNaIssue("Sign-out could not be saved.") }
            return
        }
        _ = try owner(session)
        let data = try JSONSerialization.data(withJSONObject: session)
        guard data.count <= 64 * 1024 else { throw MiNaIssue("This sign-in is too large to store.") }
        let changes: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(changes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MiNaIssue("Your sign-in could not be saved securely.") }
    }
}

import Foundation

struct MiNaIssue: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AccountLibrary {
    static let files = FileManager.default
    static var owner = "Device"
    static var library: URL {
        files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiNaLibrary", isDirectory: true).appendingPathComponent(owner, isDirectory: true)
    }

    static func loadState() throws -> [String: Any] {
        let url = library.appendingPathComponent("state.json")
        guard files.fileExists(atPath: url.path) else { return [:] }
        let state = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let state = state as? [String: Any] else { throw MiNaIssue("Your saved profile could not be opened.") }
        return state
    }

    static func saveState(_ state: Any?) throws {
        guard let state = state as? [String: Any], JSONSerialization.isValidJSONObject(state) else {
            throw MiNaIssue("Your changes could not be saved.")
        }
        let data = try JSONSerialization.data(withJSONObject: state)
        guard data.count <= 8 * 1024 * 1024 else { throw MiNaIssue("This device library is too large to save.") }
        try files.createDirectory(at: library, withIntermediateDirectories: true)
        try data.write(to: library.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

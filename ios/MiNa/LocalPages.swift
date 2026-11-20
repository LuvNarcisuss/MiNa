import CryptoKit
import Foundation
import ZIPFoundation

struct MiNaIssue: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum LocalPages {
    static let files = FileManager.default
    static let pages = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MiNaPages", isDirectory: true)
    static var owner = "Device"
    static var library: URL { files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MiNaLibrary", isDirectory: true).appendingPathComponent(owner, isDirectory: true) }

    static func prepare() throws -> [String: String] {
        guard let url = Bundle.main.url(forResource: "MiNaPages", withExtension: "zip") else {
            throw MiNaIssue("The bedtime pages are missing. Please reinstall MiNa.")
        }
        let archive = try Archive(url: url, accessMode: .read)
        let staging = pages.deletingLastPathComponent().appendingPathComponent("MiNaExtract-\(UUID().uuidString)")
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        var total: UInt64 = 0
        var checksums: [String: String] = [:]
        let issue = MiNaIssue("The bedtime pages could not be verified.")
        for entry in archive {
            let path = entry.path
            let parts = path.components(separatedBy: "/")
            guard entry.type == .file, !path.contains("\\"), !path.contains("\0"),
                  parts.first != "private-media",
                  parts.allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." }),
                  entry.uncompressedSize <= 32 * 1024 * 1024,
                  checksums.count < 5000, checksums[path] == nil else { throw issue }
            total += entry.uncompressedSize
            guard total <= 256 * 1024 * 1024 else { throw issue }
            let target = staging.appendingPathComponent(path)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard try archive.extract(entry, to: target) == entry.checksum else { throw issue }
            let bytes = try Data(contentsOf: target, options: .mappedIfSafe)
            checksums[path] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let manifest = try JSONDecoder().decode([String: String].self,
            from: Data(contentsOf: staging.appendingPathComponent("manifest.json")))
        checksums.removeValue(forKey: "manifest.json")
        guard checksums == manifest, manifest["index.html"] != nil, manifest["app.js"] != nil else { throw issue }
        if files.fileExists(atPath: pages.path) { try files.removeItem(at: pages) }
        try files.moveItem(at: staging, to: pages)
        return ["entry": pages.appendingPathComponent("index.html").absoluteString, "root": pages.absoluteString]
    }

    static func loadState() throws -> [String: Any] {
        let url = library.appendingPathComponent("state.json")
        guard files.fileExists(atPath: url.path) else { return ["state": NSNull()] }
        let state = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let state = state as? [String: Any] else { throw MiNaIssue("Your saved profile could not be opened.") }
        return ["state": state]
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

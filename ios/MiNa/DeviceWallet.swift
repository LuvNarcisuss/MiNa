import Foundation
import Security

enum WalletEnvironment: String, CaseIterable {
    case production, sandbox, xcode
}

struct DeviceWallet: Codable {
    struct Credit: Codable, Identifiable {
        let transaction: String
        let coins: Int
        let date: Date
        var id: String { transaction }
    }

    struct Spend: Codable, Identifiable {
        let id: String
        let item: Int
        let quantity: Int
        let coins: Int
        let room: String?
        let recipient: String?
        let localItems: Int
        let addedItems: Int
        let date: Date
        var pending: Bool
        var cloudCoins: Int? = nil
        var fromBag: Bool? = nil

        var isStore: Bool { room == nil }
    }

    var credits: [Credit] = []
    var spending: [Spend] = []

    // Pending deliveries reserve their coins or inventory until the server settles them.
    var balance: Int { credits.reduce(0) { $0 + $1.coins } - spending.reduce(0) { $0 + $1.coins } }
    var inventory: [Int: Int] {
        var items: [Int: Int] = [:]
        for entry in spending {
            items[entry.item, default: 0] += (entry.pending ? 0 : entry.addedItems) - entry.localItems
        }
        return items
    }

    private static func key(_ owner: String, _ environment: WalletEnvironment) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.mina.bedtime.device-wallet." + environment.rawValue,
         kSecAttrAccount as String: owner.lowercased()]
    }

    static func read(owner: String, environment: WalletEnvironment) throws -> DeviceWallet {
        var query = key(owner, environment)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var wallet = DeviceWallet()
            #if DEBUG && targetEnvironment(simulator)
            if environment == .xcode {
                let file = AccountLibrary.library.appendingPathComponent("xcode-purchases.json")
                do { wallet.credits = try JSONDecoder().decode([Credit].self, from: Data(contentsOf: file)) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
            }
            #endif
            return wallet
        }
        guard status == errSecSuccess, let data = result as? Data else { throw MiNaIssue("Your wallet could not be opened.") }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func save(owner: String, environment: WalletEnvironment) throws {
        let key = Self.key(owner, environment)
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(self),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(key.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MiNaIssue("Your wallet could not be saved.") }
    }

    static func erase(owner: String) throws {
        for environment in WalletEnvironment.allCases {
            let status = SecItemDelete(key(owner, environment) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw MiNaIssue("Your device wallet could not be removed.") }
        }
    }
}

import CryptoKit
import DeviceCheck
import Foundation

@MainActor
final class GiftSpending {
    private let wallet: WalletStore
    private let api: MiNaAPI
    private var inFlight: Set<String> = []

    init(wallet: WalletStore, api: MiNaAPI) {
        self.wallet = wallet
        self.api = api
    }

    struct Activity: Identifiable {
        let id: String
        let kind: String
        let amount: Int
        let date: Date
    }

    func recentActivity(owner: String) async throws -> [Activity] {
        try check(owner)
        let rows = try await api.rows("wallet_ledger?select=id,kind,amount,created_at&owner_id=eq." + owner + "&order=created_at.desc&limit=50")
        try check(owner)
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let amount = row["amount"] as? Int,
                  let stamp = row["created_at"] as? String, let date = precise.date(from: stamp) ?? seconds.date(from: stamp) else { return nil }
            return Activity(id: id, kind: row["kind"] as? String == "send" ? "Gift sent" : "Backpack item",
                            amount: -amount, date: date)
        }
    }

    func recover() async throws {
        guard wallet.ledger != nil else { return }
        let owner = wallet.owner
        for entry in wallet.ledger?.spending.filter(\.pending) ?? [] {
            guard wallet.owner == owner else { throw CancellationError() }
            guard inFlight.insert(entry.id).inserted else { continue }
            defer { inFlight.remove(entry.id) }
            _ = try await resolve(entry, owner: owner)
        }
    }

    func spend(id: String, item: Int, quantity: Int, price: Int, room: String? = nil,
               recipient: String? = nil, fromBag: Bool = false, resumed: Bool = false) async throws {
        let owner = wallet.owner
        let operation = id.lowercased()
        guard owner == api.userID, !owner.isEmpty, let ledger = wallet.ledger,
              (1...99).contains(quantity), price >= 0, UUID(uuidString: operation) != nil,
              inFlight.insert(operation).inserted else { throw MiNaIssue("Your wallet is busy. Try again.") }
        defer { inFlight.remove(operation) }
        if let saved = ledger.spending.first(where: { $0.id == operation }) {
            guard saved.room == room, saved.recipient == recipient, saved.item == item, saved.quantity == quantity else {
                throw MiNaIssue("Choose this gift again.")
            }
            if saved.pending {
                guard try await resolve(saved, owner: owner) else {
                    throw MiNaIssue("Review your gift and try again.", code: "gift_canceled")
                }
            }
            return
        }
        // A pre-upgrade screen can retain an operation that the server committed before the app closed.
        if resumed {
            let receipt = try await api.giftRequest("/rest/v1/rpc/resolve_device_gift", body: ["p_operation": operation], owner: owner)
            try check(owner)
            guard receipt["id"] as? String == operation else { throw MiNaIssue("The previous gift could not be confirmed.") }
            if receipt["canceled"] as? Bool == true { throw MiNaIssue("Review the gift and confirm again.", code: "gift_canceled") }
            return
        }
        let total = quantity * price
        let environment = wallet.environment
        let production = environment == .production
        let canUseCoins = production || (room == nil && ledger.balance >= total)
        let localCoins = !fromBag && canUseCoins ? min(ledger.balance, total) : 0
        let localItems = fromBag && production ? min(ledger.inventory[item, default: 0], quantity) : 0
        let deviceOnly = room == nil && total > 0 && localCoins == total
        let entry = DeviceWallet.Spend(id: operation, item: item, quantity: quantity, coins: localCoins,
            room: room, recipient: recipient, localItems: localItems, addedItems: deviceOnly ? quantity : 0,
            date: Date(), pending: !deviceOnly)
        if deviceOnly {
            try wallet.updateLedger { $0.spending.append(entry) }
            return
        }

        let deviceFunded = localCoins > 0 || localItems > 0
        var request: [String: Any] = ["gift_index": item, "quantity": quantity, "operation": operation]
        if let room, let recipient {
            request["target_room"] = room
            request["recipient"] = recipient
            request["use_inventory"] = fromBag
        }
        if deviceFunded {
            guard DCAppAttestService.shared.isSupported else { throw MiNaIssue("Device-funded gift delivery requires a supported iPhone.") }
        }
        // Key registration happens before reserving any coins. Only the later assertion authorizes this gift.
        let key: String?
        if deviceFunded { key = try await registeredKey(owner: owner) }
        else { key = nil }
        try check(owner)
        guard environment == wallet.environment else { throw MiNaIssue("Review the gift in your current wallet.") }
        try wallet.updateLedger { current in
            guard current.balance >= localCoins, current.inventory[item, default: 0] >= localItems else {
                throw MiNaIssue("Your balance or backpack changed. Review the gift again.")
            }
            current.spending.append(entry)
        }
        do {
            if let key { try await authorize(entry, owner: owner, total: total, key: key) }
            try check(owner)
            let receipt = try await api.giftRequest(room == nil ? "/rest/v1/rpc/acquire_gift" : "/rest/v1/rpc/send_gift",
                                                    body: request, owner: owner)
            try check(owner)
            guard receipt["id"] as? String == operation else {
                throw MiNaIssue("Gift delivery could not be confirmed.")
            }
            try settle(entry, receipt: receipt)
        } catch {
            if wallet.owner == owner, api.userID == owner {
                if try await resolve(entry, owner: owner) { return }
                throw MiNaIssue(error.localizedDescription, code: "gift_canceled")
            }
            throw error
        }
    }

    private func check(_ owner: String) throws {
        guard api.userID == owner, wallet.owner == owner, AccountLibrary.owner.lowercased() == owner else { throw CancellationError() }
    }

    private func settle(_ entry: DeviceWallet.Spend, receipt: [String: Any]) throws {
        guard (receipt["device_coins"] as? Int ?? 0) == entry.coins, (receipt["device_items"] as? Int ?? 0) == entry.localItems else {
            throw MiNaIssue("Your gift receipt could not be matched.")
        }
        try wallet.updateLedger { ledger in
            guard let i = ledger.spending.firstIndex(where: { $0.id == entry.id }) else { throw MiNaIssue("Gift reservation unavailable.") }
            ledger.spending[i].pending = false
            ledger.spending[i].cloudCoins = receipt["charged"] as? Int
        }
    }

    private func resolve(_ entry: DeviceWallet.Spend, owner: String) async throws -> Bool {
        try check(owner)
        let receipt = try await api.giftRequest("/rest/v1/rpc/resolve_device_gift", body: ["p_operation": entry.id], owner: owner)
        try check(owner)
        guard receipt["id"] as? String == entry.id else {
            throw MiNaIssue("Your gift is awaiting confirmation.")
        }
        if receipt["canceled"] as? Bool == true {
            try wallet.updateLedger { $0.spending.removeAll { $0.id == entry.id && $0.pending } }
            return false
        }
        try settle(entry, receipt: receipt)
        return true
    }

    private func registeredKey(owner: String) async throws -> String {
        let service = DCAppAttestService.shared
        let keySlot = "gift.attest." + owner
        var key = UserDefaults.standard.string(forKey: keySlot)
        if key == nil {
            let fresh = try await service.generateKey()
            try check(owner)
            let registration = try await api.giftRequest("/functions/v1/gift-spend", body: ["action": "challenge", "key": fresh], owner: owner)
            guard let challenge = registration["challenge"] as? String else { throw MiNaIssue("Gift verification is unavailable.") }
            let proof = try await service.attestKey(fresh, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
            try check(owner)
            let reply = try await api.giftRequest("/functions/v1/gift-spend", body: ["action": "register", "key": fresh, "proof": proof.base64EncodedString()], owner: owner)
            guard reply["registered"] as? Bool == true else { throw MiNaIssue("This iPhone could not be verified.") }
            key = fresh
            UserDefaults.standard.set(fresh, forKey: keySlot)
        }
        guard let key else { throw MiNaIssue("This iPhone could not be verified.") }
        return key
    }

    private func authorize(_ entry: DeviceWallet.Spend, owner: String, total: Int, key: String) async throws {
        let keySlot = "gift.attest." + owner
        let service = DCAppAttestService.shared
        var payload: [String: Any] = ["owner": owner, "id": entry.id, "item": entry.item, "quantity": entry.quantity,
                                      "coins": entry.coins, "localItems": entry.localItems, "total": total]
        payload["room"] = entry.room?.lowercased()
        payload["recipient"] = entry.recipient?.lowercased()
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let proof: Data
        do { proof = try await service.generateAssertion(key, clientDataHash: Data(SHA256.hash(data: bytes))) }
        catch {
            if (error as NSError).domain == DCError.errorDomain, (error as NSError).code == DCError.invalidKey.rawValue {
                UserDefaults.standard.removeObject(forKey: keySlot)
            }
            throw error
        }
        try check(owner)
        let reply = try await api.giftRequest("/functions/v1/gift-spend", body: ["action": "authorize", "key": key,
            "proof": proof.base64EncodedString(), "payload": String(decoding: bytes, as: UTF8.self)], owner: owner)
        guard reply["operation"] as? String == entry.id else { throw MiNaIssue("Gift authorization failed.") }
    }
}

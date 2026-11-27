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
        let environment = wallet.environment
        for entry in wallet.ledger?.spending.filter(\.pending) ?? [] {
            guard wallet.owner == owner, wallet.environment == environment else { throw CancellationError() }
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
            guard saved.room == room, saved.recipient == recipient, saved.item == item, saved.quantity == quantity,
                  saved.fromBag == nil || saved.fromBag == fromBag else {
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
        guard RoomGifts.names.indices.contains(item), (room == nil) == (recipient == nil),
              !fromBag || room != nil, price <= Int.max / quantity else { throw MiNaIssue("Choose this gift again.") }
        let total = quantity * price
        let environment = wallet.environment
        let localCoins = fromBag ? 0 : min(ledger.balance, total)
        let localItems = fromBag ? min(ledger.inventory[item, default: 0], quantity) : 0
        let storePurchase = room == nil && localCoins > 0
        let deviceOnly = storePurchase && localCoins == total
        let entry = DeviceWallet.Spend(id: operation, item: item, quantity: quantity, coins: localCoins,
            room: room, recipient: recipient, localItems: localItems, addedItems: storePurchase ? quantity : 0,
            date: Date(), pending: !deviceOnly, fromBag: fromBag)
        try wallet.updateLedger { current in
            guard current.balance >= localCoins, current.inventory[item, default: 0] >= localItems else {
                throw MiNaIssue("Your balance or backpack changed. Review the gift again.")
            }
            current.spending.append(entry)
        }
        if deviceOnly { return }
        do {
            let request: [String: Any] = [
                "target_room": room as Any? ?? NSNull(), "recipient": recipient as Any? ?? NSNull(),
                "gift_index": item, "quantity": quantity, "operation": operation, "use_inventory": fromBag,
                "unit_price": price, "device_coins": localCoins, "device_items": localItems
            ]
            let receipt = try await api.giftRequest("/rest/v1/rpc/deliver_wallet_gift", body: request, owner: owner)
            try check(owner)
            guard receipt["id"] as? String == operation else {
                throw MiNaIssue("Gift delivery could not be confirmed.")
            }
            guard wallet.environment == environment else { throw CancellationError() }
            try settle(entry, receipt: receipt)
        } catch {
            if wallet.owner == owner, api.userID == owner, wallet.environment == environment {
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
        let environment = wallet.environment
        let receipt = try await api.giftRequest("/rest/v1/rpc/resolve_device_gift", body: ["p_operation": entry.id], owner: owner)
        try check(owner)
        guard wallet.environment == environment else { throw CancellationError() }
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
}

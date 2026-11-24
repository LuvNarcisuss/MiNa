import StoreKit
import SwiftUI
import OSLog
#if DEBUG && targetEnvironment(simulator)
import TPInAppReceipt
#endif

struct CoinPackage: Identifiable {
    let id: String
    let coins: Int

    static let all = [
        CoinPackage(id: "iukawygoozctrvri", coins: 400),
        CoinPackage(id: "iuksdwimsbrhwuza", coins: 800),
        CoinPackage(id: "kbuujljqmlnqmmpp", coins: 2450),
        CoinPackage(id: "yyzthxzkykuwreyt", coins: 5150),
        CoinPackage(id: "mxvqqvbrxagzhpzd", coins: 10800),
        CoinPackage(id: "cbdqrfufpxoocyou", coins: 29400),
        CoinPackage(id: "ezcsvqkqboqagspr", coins: 63700)
    ]
}

// The queue observer outlives navigation and receives unfinished purchases at launch.
@MainActor
final class WalletStore: NSObject, ObservableObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    private static let catalogLog = Logger(subsystem: "com.mina.bedtime", category: "WalletCatalog")
    #if DEBUG && targetEnvironment(simulator)
    struct TestCredit: Codable {
        let transaction: String
        let coins: Int
        let date: Date
    }

    @Published private(set) var testCredits: [TestCredit] = []
    private var testLedgerURL: URL { AccountLibrary.library.appendingPathComponent("xcode-purchases.json") }

    private func readTestCredits() throws -> [TestCredit] {
        do { return try JSONDecoder().decode([TestCredit].self, from: Data(contentsOf: testLedgerURL)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    }

    private func deliverTestPurchase(_ pack: CoinPackage, transaction: SKPaymentTransaction,
                                     id: String, accountSession: UUID) async throws -> Bool {
        _ = try await receipt(refresh: false)
        let proof = try await AppReceipt.local
        guard proof.environment == .xcode else { return false }
        guard proof.bundleIdentifier == Bundle.main.bundleIdentifier, case .valid = await proof.validate(),
              let item = proof.purchases.first(where: { $0.transactionIdentifier == id }),
              item.productIdentifier == pack.id, item.quantity == 1, transaction.payment.quantity == 1,
              item.cancellationDate == nil, item.subscriptionExpirationDate == nil,
              item.productType == .consumable || item.productType == .unknown,
              accountSession == session, owner == AccountLibrary.owner.lowercased() else {
            throw MiNaIssue("This purchase could not be verified.")
        }
        var credits = try readTestCredits()
        let newCredit = !credits.contains(where: { $0.transaction == id })
        if newCredit {
            credits.append(TestCredit(transaction: id, coins: pack.coins, date: Date()))
            try FileManager.default.createDirectory(at: AccountLibrary.library, withIntermediateDirectories: true)
            try JSONEncoder().encode(credits).write(to: testLedgerURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        testCredits = credits
        finish(transaction)
        recordDelivery(in: .local, balance: credits.reduce(0) { $0 + $1.coins }, pack: pack, newCredit: newCredit, id: id)
        return true
    }
    #endif

    private let api: MiNaAPI
    private let queue = SKPaymentQueue.default()
    private var owner = ""
    private var session = UUID()
    private var request: SKProductsRequest?
    private var timeout: Task<Void, Never>?
    private var receiptRequest: SKReceiptRefreshRequest?
    private var receiptTimeout: Task<Void, Never>?
    private var receiptWaiters: [CheckedContinuation<Void, Error>] = []
    private var preparing = false
    private var submitting = false
    private var delivering = Set<String>()
    private var finishing: [ObjectIdentifier: String] = [:]
    @Published private(set) var products: [String: SKProduct] = [:]
    @Published private(set) var catalogMessage = ""
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    @Published private(set) var revision = 0
    enum Ledger { case production, sandbox, local }
    struct PurchaseNotice: Identifiable {
        let id: String
        let coins: Int
    }

    @Published private(set) var notices: [PurchaseNotice] = []
    private var lastLedger: Ledger?

    func activeLedger() async -> Ledger {
        if let lastLedger { return lastLedger }
        #if DEBUG && targetEnvironment(simulator)
        if let receipt = try? await AppReceipt.local, receipt.environment == .xcode { return .local }
        #endif
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? .sandbox : .production
    }

    func dismissNotice() {
        if !notices.isEmpty { notices.removeFirst() }
    }

    private func recordDelivery(in ledger: Ledger, balance: Int, pack: CoinPackage, newCredit: Bool, id: String) {
        lastLedger = ledger
        confirmedBalance = balance
        message = ""
        revision += 1
        if newCredit { notices.append(PurchaseNotice(id: id, coins: pack.coins)) }
    }

    @Published private(set) var confirmedBalance: Int?

    init(api: MiNaAPI) {
        self.api = api
        super.init()
        queue.add(self)
    }

    func setOwner(_ account: String) {
        session = UUID()
        owner = account
        completeReceiptRefresh(.failure(CancellationError()))
        lastLedger = nil
        notices.removeAll()
        request?.cancel()
        request = nil
        timeout?.cancel()
        preparing = false
        submitting = false
        products = [:]
        catalogMessage = ""
        message = ""
        confirmedBalance = nil
        #if DEBUG && targetEnvironment(simulator)
        testCredits = []
        if !account.isEmpty {
            do { testCredits = try readTestCredits() }
            catch { message = "Your purchase history could not be read." }
        }
        #endif
        recover()
    }

    func loadCatalog() {
        guard !owner.isEmpty, request == nil else { return }
        timeout?.cancel()
        request?.cancel()
        products = [:]
        catalogMessage = "Loading App Store prices…"
        let next = SKProductsRequest(productIdentifiers: Set(CoinPackage.all.map(\.id)))
        request = next
        next.delegate = self
        next.start()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.request === next else { return }
            next.cancel()
            self.request = nil
            self.catalogMessage = "The App Store took too long to respond."
        }
    }

    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor in
            guard request === self.request else { return }
            self.timeout?.cancel()
            self.request = nil
            self.products = Dictionary(response.products.map { ($0.productIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            let invalid = response.invalidProductIdentifiers.sorted().joined(separator: ",")
            Self.catalogLog.info("Requested \(CoinPackage.all.count) products, received \(response.products.count), invalid IDs: \(invalid, privacy: .public)")
            if self.products.isEmpty { self.catalogMessage = "No packages are available in this storefront." }
            else if self.products.count < CoinPackage.all.count { self.catalogMessage = "Some packages are unavailable in this storefront." }
            else { self.catalogMessage = "" }
        }
    }

    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor in
            if request === self.receiptRequest {
                self.completeReceiptRefresh(.failure(MiNaIssue("The App Store receipt could not be refreshed.")))
                return
            }
            guard request === self.request else { return }
            self.request = nil
            self.timeout?.cancel()
            self.catalogMessage = "App Store prices could not be loaded."
        }
    }

    nonisolated func requestDidFinish(_ request: SKRequest) {
        Task { @MainActor in
            if request === self.receiptRequest { self.completeReceiptRefresh(.success(())) }
        }
    }

    private func completeReceiptRefresh(_ result: Result<Void, Error>) {
        let active = receiptRequest
        receiptRequest = nil
        receiptTimeout?.cancel()
        receiptTimeout = nil
        if case .failure = result { active?.cancel() }
        let waiters = receiptWaiters
        receiptWaiters.removeAll()
        for waiter in waiters { waiter.resume(with: result) }
    }

    private func receipt(refresh: Bool) async throws -> String {
        func read() -> String? {
            guard let url = Bundle.main.appStoreReceiptURL, let data = try? Data(contentsOf: url),
                  !data.isEmpty else { return nil }
            return data.base64EncodedString()
        }
        if !refresh, let existing = read() { return existing }
        try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
            receiptWaiters.append(waiter)
            guard receiptRequest == nil else { return }
            let next = SKReceiptRefreshRequest(receiptProperties: nil)
            receiptRequest = next
            next.delegate = self
            receiptTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.receiptRequest === next else { return }
                self.completeReceiptRefresh(.failure(MiNaIssue("The App Store receipt refresh timed out.")))
            }
            next.start()
        }
        guard let refreshed = read() else { throw MiNaIssue("The App Store receipt is still unavailable.") }
        return refreshed
    }

    private func claim(_ id: String, product: String, sessionID: UUID, refresh: Bool) async throws -> [String: Any] {
        let proof = try await receipt(refresh: refresh)
        guard session == sessionID, owner == api.userID else { throw CancellationError() }
        return try await api.purchase(["action": "deliver", "proof": "receipt-v1", "product": product,
                                       "transaction": id, "receipt": proof])
    }

    func price(_ pack: CoinPackage) -> String? {
        guard let product = products[pack.id] else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price)
    }

    func buy(_ pack: CoinPackage) async {
        let current = session
        guard !busy, !owner.isEmpty, api.userID == owner, let product = products[pack.id],
              SKPaymentQueue.canMakePayments() else { return }
        preparing = true
        updateBusy()
        defer { if current == session { preparing = false; updateBusy() } }
        message = "Opening checkout…"
        do {
            let ready = try await api.purchase(["action": "prepare", "proof": "receipt-v1", "product": pack.id])
            guard current == session else { return }
            try Task.checkCancellation()
            guard ready["proof"] as? String == "receipt-v1", ready["owner"] as? String == owner, ready["product"] as? String == pack.id,
                  ready["coins"] as? Int == pack.coins, products[pack.id] === product,
                  SKPaymentQueue.canMakePayments(), !hasQueuedPurchase else {
                throw MiNaIssue("This package is unavailable. Refresh your wallet.")
            }
            let payment = SKMutablePayment(product: product)
            payment.applicationUsername = owner
            payment.quantity = 1
            submitting = true
            message = "Waiting for the App Store…"
            queue.add(payment)
        } catch {
            if current == session { message = Task.isCancelled ? "" : error.localizedDescription }
        }
    }

    private var hasQueuedPurchase: Bool {
        queue.transactions.contains { $0.payment.applicationUsername?.lowercased() == owner }
    }

    private func updateBusy() {
        busy = !owner.isEmpty && (preparing || submitting || hasQueuedPurchase || finishing.values.contains(owner))
    }

    func recover() {
        for transaction in queue.transactions { handle(transaction) }
        updateBusy()
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            for transaction in transactions { self.handle(transaction) }
            self.updateBusy()
        }
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            for transaction in transactions { self.finishing.removeValue(forKey: ObjectIdentifier(transaction)) }
            self.updateBusy()
        }
    }

    private func handle(_ transaction: SKPaymentTransaction) {
        guard !owner.isEmpty, transaction.payment.applicationUsername?.lowercased() == owner,
              queue.transactions.contains(where: { $0 === transaction }),
              finishing[ObjectIdentifier(transaction)] == nil else { return }
        submitting = false
        switch transaction.transactionState {
        case .purchasing:
            message = "Waiting for the App Store…"
        case .deferred:
            message = "Waiting for purchase approval."
        case .failed:
            let cancelled = (transaction.error as? SKError)?.code == .paymentCancelled
            message = cancelled ? "Purchase canceled." : "The purchase failed. Please try again."
            finish(transaction)
        case .restored:
            finish(transaction)
        case .purchased:
            guard let id = transaction.transactionIdentifier,
                  let pack = CoinPackage.all.first(where: { $0.id == transaction.payment.productIdentifier }),
                  delivering.insert(id).inserted else { return }
            let current = session
            message = "Verifying your purchase…"
            Task {
                defer { delivering.remove(id); if current != session { recover() } }
                do {
                    #if DEBUG && targetEnvironment(simulator)
                    if try await deliverTestPurchase(pack, transaction: transaction, id: id, accountSession: current) { return }
                    guard current == session else { return }
                    #endif
                    var result = try await claim(id, product: pack.id, sessionID: current, refresh: false)
                    guard current == session else { return }
                    if result["refreshReceipt"] as? Bool == true {
                        result = try await claim(id, product: pack.id, sessionID: current, refresh: true)
                    }
                    guard current == session else { return }
                    guard result["transaction"] as? String == id, result["owner"] as? String == owner,
                          result["product"] as? String == pack.id, result["coins"] as? Int == pack.coins,
                          let environment = result["environment"] as? String, ["Sandbox", "Production"].contains(environment),
                          let newCredit = result["newCredit"] as? Bool else {
                        throw MiNaIssue("Your wallet has not confirmed delivery.")
                    }
                    let wallet = environment == "Sandbox" ? "sandbox_wallets" : "wallets"
                    let row = try await api.rows(wallet + "?select=balance&owner_id=eq." + owner).first
                    guard current == session else { return }
                    guard let balance = row?["balance"] as? Int, balance >= 0 else {
                        throw MiNaIssue("Refresh your wallet to confirm the balance.")
                    }
                    finish(transaction)
                    recordDelivery(in: environment == "Sandbox" ? .sandbox : .production,
                                   balance: balance, pack: pack, newCredit: newCredit, id: id)
                } catch {
                    if current == session { message = error.localizedDescription + " Refresh your wallet to retry delivery." }
                }
            }
        @unknown default:
            message = "The App Store is processing your purchase."
        }
    }

    private func finish(_ transaction: SKPaymentTransaction) {
        finishing[ObjectIdentifier(transaction)] = owner
        queue.finishTransaction(transaction)
    }
}

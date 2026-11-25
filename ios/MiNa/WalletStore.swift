import CryptoKit
import StoreKit
import SwiftUI
import OSLog
import TPInAppReceipt

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
    // Frozen receipt IDs from the previous server wallet prevent double delivery across the cutover.
    private static let legacyCredits = Result<Set<String>, Error> {
        guard let url = Bundle.main.url(forResource: "LegacyPurchaseCredits", withExtension: "json") else {
            throw MiNaIssue("The previous wallet records could not be read.")
        }
        return try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url))
    }

    @Published private(set) var ledger: DeviceWallet?
    @Published private(set) var environment: WalletEnvironment = .production
    private(set) var owner = ""
    private var selectedEnvironment = false

    func updateLedger(_ change: (inout DeviceWallet) throws -> Void) throws {
        guard !owner.isEmpty, selectedEnvironment, owner == AccountLibrary.owner.lowercased() else {
            throw MiNaIssue("Open your wallet for this account.")
        }
        var next = try DeviceWallet.read(owner: owner, environment: environment)
        try change(&next)
        try next.save(owner: owner, environment: environment)
        ledger = next
    }

    func reloadLedger() {
        guard selectedEnvironment, !owner.isEmpty, owner == AccountLibrary.owner.lowercased() else { return }
        do { ledger = try DeviceWallet.read(owner: owner, environment: environment) }
        catch { ledger = nil; problem = "Your wallet could not be read." }
    }

    private func walletEnvironment(_ proof: AppReceipt) throws -> WalletEnvironment {
        switch proof.environment {
        case .production: return .production
        case .sandbox, .productionSandbox: return .sandbox
        #if DEBUG && targetEnvironment(simulator)
        case .xcode: return .xcode
        #endif
        default: throw MiNaIssue("This App Store receipt environment is unavailable.")
        }
    }

    private let queue = SKPaymentQueue.default()
    private var session = UUID()
    private var request: SKProductsRequest?
    private var timeout: Task<Void, Never>?
    private var receiptRequest: SKReceiptRefreshRequest?
    private var receiptTimeout: Task<Void, Never>?
    private var receiptWaiters: [CheckedContinuation<Void, Error>] = []
    private var submitting = false
    private var delivering = Set<String>()
    private var finishing: [ObjectIdentifier: String] = [:]
    @Published private(set) var products: [String: SKProduct] = [:]
    @Published private(set) var problem = ""
    @Published private(set) var catalogProblem = ""
    @Published private(set) var catalogMessage = ""
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    struct PurchaseNotice: Identifiable {
        let id: String
        let coins: Int
    }

    @Published private(set) var notices: [PurchaseNotice] = []
    func dismissNotice() {
        if !notices.isEmpty { notices.removeFirst() }
    }

    override init() {
        super.init()
        queue.add(self)
    }

    func setOwner(_ account: String) {
        session = UUID()
        owner = account.lowercased()
        completeReceiptRefresh(.failure(CancellationError()))
        selectedEnvironment = false
        ledger = nil
        notices.removeAll()
        request?.cancel()
        request = nil
        timeout?.cancel()
        submitting = false
        products = [:]
        problem = ""
        catalogProblem = ""
        catalogMessage = ""
        message = ""
        updateBusy()
        guard !owner.isEmpty else { return }
        let current = session
        Task {
            let proof = try? await AppReceipt.local
            guard current == session, !selectedEnvironment else { return }
            do {
                if let proof { environment = try walletEnvironment(proof) }
                else { environment = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? .sandbox : .production }
                selectedEnvironment = true
                reloadLedger()
            } catch { problem = error.localizedDescription }
            recover()
        }
    }

    func loadCatalog() {
        guard !owner.isEmpty, request == nil else { return }
        timeout?.cancel()
        request?.cancel()
        products = [:]
        catalogProblem = ""
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
            self.catalogMessage = ""
            self.catalogProblem = "The App Store took too long to respond."
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
            self.catalogMessage = ""
            if self.products.isEmpty { self.catalogProblem = "No packages are available in this storefront." }
            else if self.products.count < CoinPackage.all.count { self.catalogProblem = "Some packages are unavailable in this storefront." }
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
            self.catalogMessage = ""
            self.catalogProblem = "App Store prices could not be loaded."
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

    private func refreshReceipt() async throws {
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
    }

    private func deliver(_ transaction: SKPaymentTransaction, id: String, pack: CoinPackage, sessionID: UUID) async throws {
        var proof = try? await AppReceipt.local
        guard sessionID == session else { throw CancellationError() }
        if proof?.purchases.contains(where: { $0.transactionIdentifier == id }) != true {
            try await refreshReceipt()
            proof = try await AppReceipt.local
        }
        guard let proof, proof.bundleIdentifier == Bundle.main.bundleIdentifier else { throw MiNaIssue("Invalid app receipt.") }
        let verifiedEnvironment = try walletEnvironment(proof)
        guard case .valid = await proof.validate(),
              let item = proof.purchases.first(where: { $0.transactionIdentifier == id }),
              item.productIdentifier == pack.id, item.quantity == 1, transaction.payment.quantity == 1,
              item.originalTransactionIdentifier.isEmpty || item.originalTransactionIdentifier == id,
              item.cancellationDate == nil, item.subscriptionExpirationDate == nil,
              item.productType == .consumable || item.productType == .unknown else {
            throw MiNaIssue("This purchase could not be verified.")
        }
        guard sessionID == session, owner == transaction.payment.applicationUsername?.lowercased(),
              owner == AccountLibrary.owner.lowercased() else { throw CancellationError() }
        if verifiedEnvironment != .xcode {
            let prefix = verifiedEnvironment == .sandbox ? "Sandbox:" : "Production:"
            let digest = SHA256.hash(data: Data((prefix + id).utf8)).map { String(format: "%02x", $0) }.joined()
            if try Self.legacyCredits.get().contains(digest) {
                finish(transaction)
                message = ""
                return
            }
        }
        if environment != verifiedEnvironment { ledger = nil }
        environment = verifiedEnvironment
        selectedEnvironment = true
        var isNew = false
        try updateLedger { wallet in
            guard !wallet.credits.contains(where: { $0.transaction == id }) else { return }
            wallet.credits.append(.init(transaction: id, coins: pack.coins, date: item.purchaseDate))
            isNew = true
        }
        finish(transaction)
        message = ""
        if isNew { notices.append(PurchaseNotice(id: id, coins: pack.coins)) }
    }

    func price(_ pack: CoinPackage) -> String? {
        guard let product = products[pack.id] else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price)
    }

    func buy(_ pack: CoinPackage) {
        guard !busy, ledger != nil, !owner.isEmpty, owner == AccountLibrary.owner.lowercased(),
              let product = products[pack.id], SKPaymentQueue.canMakePayments(), !hasQueuedPurchase else { return }
        let payment = SKMutablePayment(product: product)
        payment.applicationUsername = owner
        payment.quantity = 1
        problem = ""
        submitting = true
        updateBusy()
        message = "Waiting for the App Store…"
        queue.add(payment)
    }

    private var hasQueuedPurchase: Bool {
        queue.transactions.contains { $0.payment.applicationUsername?.lowercased() == owner }
    }

    private func updateBusy() {
        busy = !owner.isEmpty && (submitting || hasQueuedPurchase || finishing.values.contains(owner))
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
            message = cancelled ? "Purchase canceled." : ""
            if !cancelled { problem = "The purchase failed. Please try again." }
            finish(transaction)
        case .restored:
            finish(transaction)
        case .purchased:
            guard let id = transaction.transactionIdentifier, !id.isEmpty,
                  let pack = CoinPackage.all.first(where: { $0.id == transaction.payment.productIdentifier }),
                  delivering.insert(id).inserted else { return }
            let current = session
            message = "Verifying your purchase…"
            Task {
                defer { delivering.remove(id); if current != session { recover() } }
                do {
                    try await deliver(transaction, id: id, pack: pack, sessionID: current)
                } catch {
                    if current == session {
                        message = ""
                        problem = error.localizedDescription + " Refresh your wallet to retry delivery."
                    }
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

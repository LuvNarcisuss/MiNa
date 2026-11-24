import StoreKit
import SwiftUI

struct WalletScreen: View {
    @EnvironmentObject private var app: MiNaAppModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: WalletStore
    @State private var balance: Int?
    @State private var balanceError = false
    @State private var read = UUID()
    @State private var historyRefresh = 0
    @State private var showHistory = false
    @State private var checkout: Task<Void, Never>?
    @ScaledMetric private var bodySize: CGFloat = 16
    private let aqua = Color(red: 0.02, green: 0.9, blue: 0.68)
    private let blue = Color(red: 0.42, green: 0.73, blue: 1)

    var body: some View {
        VStack(spacing: 0) {
            Text("My wallet").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                .overlay(alignment: .leading) {
                    Button { app.back() } label: {
                        NativeArt("wallet", 2).scaledToFit().frame(width: 24, height: 24)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Back")
                }.padding(.horizontal, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 9) {
                            NativeArt("wallet", 4).scaledToFit().frame(width: 84, height: 17)
                                .accessibilityLabel("My wallet")
                            Group {
                                if let balance { Text(balance.formatted()).font(.largeTitle.bold().monospacedDigit()) }
                                else if balanceError { Text("Unavailable").font(.headline) }
                                else { ProgressView() }
                            }.accessibilityIdentifier("wallet.balance")
                            Text("Star coin balance").font(.caption)

                        }
                        Spacer()
                        NativeArt("wallet", 3).scaledToFit().frame(width: 124, height: 132).accessibilityHidden(true)
                    }
                    if !SKPaymentQueue.canMakePayments() { Text("Purchases are disabled on this iPhone.").font(.footnote) }
                    if !store.catalogMessage.isEmpty { Text(store.catalogMessage).font(.footnote) }
                    if !store.message.isEmpty { Text(store.message).font(.callout).accessibilityIdentifier("wallet.status") }
                    ForEach(CoinPackage.all) { pack in
                        let price = store.price(pack)
                        Button { checkout = Task { await store.buy(pack) } } label: {
                            HStack(spacing: 9) {
                                NativeArt("wallet", 6).scaledToFit().frame(width: 34, height: 36).accessibilityHidden(true)
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(pack.coins.formatted()).font(.headline)
                                        Text("coins").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(pack.coins.formatted()).font(.headline)
                                }
                                Spacer(minLength: 2)
                                Text(price ?? "Unavailable").font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .frame(minWidth: 76)
                                    .background {
                                        if price != nil { Capsule().fill(LinearGradient(colors: [aqua, blue], startPoint: .leading, endPoint: .trailing)) }
                                        else { Capsule().fill(Color.gray.opacity(0.12)) }
                                    }
                            }
                            .padding(.leading, 15).padding(.trailing, 12).padding(.vertical, 9)
                            .frame(maxWidth: .infinity, minHeight: max(64, bodySize * 3.4))
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(blue.opacity(0.7), lineWidth: 0.8) }
                            .contentShape(Rectangle())
                        }
                        .disabled(price == nil || store.busy || !SKPaymentQueue.canMakePayments())
                        .accessibilityLabel("\(pack.coins) star coins, \(price ?? "unavailable")")
                        .accessibilityIdentifier("wallet.package.\(pack.coins)")
                    }
                    HStack {
                        Text("Purchase history").font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("View all") { showHistory = true }.font(.subheadline)
                    }.padding(.top, 8)
                    WalletActivity(store: store, purchasesOnly: true, refreshVersion: historyRefresh)
                }.padding(.horizontal, 20).padding(.vertical, 18)
            }.refreshable {
                historyRefresh += 1
                await refresh()
            }
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .background { NativeArt("wallet", 1).ignoresSafeArea().accessibilityHidden(true) }
        .toolbar(.hidden, for: .navigationBar)
        .task { await refresh() }
        .onChange(of: store.revision) { _ in
            read = UUID()
            balance = store.confirmedBalance
            Task { await loadBalance() }
        }
        .onChange(of: scenePhase) { phase in if phase == .active { store.recover() } }
        .onDisappear { checkout?.cancel() }
        .alert(item: Binding(get: { store.notices.first }, set: { if $0 == nil { store.dismissNotice() } })) { notice in
            Alert(title: Text("Purchase successful"),
                  message: Text("\(notice.coins.formatted()) star coins added."),
                  dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showHistory) { WalletActivity(store: store) }
    }

    private func refresh() async {
        store.loadCatalog()
        store.recover()
        await loadBalance()
    }

    private func loadBalance() async {
        let ticket = UUID()
        read = ticket
        let owner = app.api.userID
        do {
            let ledger = await store.activeLedger()
            guard ticket == read, owner == app.api.userID, !Task.isCancelled else { return }
            #if DEBUG && targetEnvironment(simulator)
            if ledger == .local {
                balance = store.testCredits.reduce(0) { $0 + $1.coins }
                balanceError = false
                return
            }
            #endif
            let table = ledger == .sandbox ? "sandbox_wallets" : "wallets"
            let row = try await app.api.rows(table + "?select=balance&owner_id=eq." + owner).first
            guard ticket == read, owner == app.api.userID, !Task.isCancelled else { return }
            balance = row?["balance"] as? Int ?? (ledger == .sandbox && row == nil ? 0 : nil)
            balanceError = balance == nil
        } catch {
            if ticket == read && !Task.isCancelled { balanceError = true; balance = nil }
        }
    }
}

private struct WalletActivity: View {
    @EnvironmentObject private var app: MiNaAppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WalletStore
    var purchasesOnly = false
    var refreshVersion = 0
    @State private var items: [Entry] = []
    @State private var message = "Loading activity…"

    private struct Entry: Identifiable {
        let id: String
        let kind: String
        let amount: Int
        let date: Date
    }

    var body: some View {
        Group {
            if purchasesOnly {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        entryRow(item)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                NavigationStack {
                    List {
                        if !message.isEmpty { Text(message) }
                        ForEach(items) { item in entryRow(item) }
                    }
                    .navigationTitle("Recent activity").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { dismiss() } }
                    .refreshable { await load() }
                }
            }
        }
        .task(id: [store.revision, refreshVersion]) { await load() }
    }

    private func entryRow(_ item: Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind)
                Text(item.date.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.amount.formatted(.number.sign(strategy: .always(includingZero: false))))
                .font(.headline.monospacedDigit())
        }.accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            let owner = app.api.userID
            let filter = "&owner_id=eq." + owner + "&order=created_at.desc&limit=50"
            let ledger = await store.activeLedger()
            #if DEBUG && targetEnvironment(simulator)
            if ledger == .local {
                guard owner == app.api.userID, !Task.isCancelled else { return }
                items = store.testCredits.sorted { $0.date > $1.date }.prefix(50).map {
                    Entry(id: $0.transaction, kind: "Star coin purchase", amount: $0.coins, date: $0.date)
                }
                message = items.isEmpty ? (purchasesOnly ? "No purchases yet." : "No wallet activity yet.") : ""
                return
            }
            #endif
            let environment = ledger == .sandbox ? "Sandbox" : "Production"
            let purchases = try await app.api.rows("coin_purchases?select=transaction_id,coins,created_at&environment=eq." + environment + filter)
            let spending = !purchasesOnly && ledger == .production ? try await app.api.rows("wallet_ledger?select=id,kind,amount,created_at" + filter) : []
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let seconds = ISO8601DateFormatter()
            let entries: [Entry] = (purchases + spending).compactMap { row in
                guard let stamp = row["created_at"] as? String, let date = parser.date(from: stamp) ?? seconds.date(from: stamp) else { return nil }
                if let id = row["transaction_id"] as? String, let coins = row["coins"] as? Int {
                    return Entry(id: "purchase-" + id, kind: "Star coin purchase", amount: coins, date: date)
                }
                guard let id = row["id"] as? String, let amount = row["amount"] as? Int else { return nil }
                return Entry(id: id, kind: row["kind"] as? String == "send" ? "Gift sent" : "Backpack item", amount: -amount, date: date)
            }
            guard owner == app.api.userID, !Task.isCancelled else { return }
            items = Array(entries.sorted { $0.date > $1.date }.prefix(50))
            message = items.isEmpty ? (purchasesOnly ? "No purchases yet." : "No wallet activity yet.") : ""
        } catch { if !Task.isCancelled { message = "Activity could not be loaded. Pull to refresh." } }
    }
}

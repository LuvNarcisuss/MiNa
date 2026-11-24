import StoreKit
import SwiftUI

struct WalletScreen: View {
    @EnvironmentObject private var app: MiNaAppModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: WalletStore
    @State private var balance: Int?
    @State private var sandboxBalance: Int?
    @State private var balanceError = false
    @State private var read = UUID()
    @State private var selected: CoinPackage?
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
                            if let sandboxBalance, sandboxBalance > 0 {
                                Text("Sandbox balance: \(sandboxBalance.formatted())").font(.footnote)
                            }
                        }
                        Spacer()
                        NativeArt("wallet", 3).scaledToFit().frame(width: 124, height: 132).accessibilityHidden(true)
                    }
                    Text("Choose a package to add star coins to your wallet.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    if !SKPaymentQueue.canMakePayments() { Text("Purchases are disabled on this iPhone.").font(.footnote) }
                    if !store.catalogMessage.isEmpty { Text(store.catalogMessage).font(.footnote) }
                    if !store.message.isEmpty { Text(store.message).font(.callout).accessibilityIdentifier("wallet.status") }
                    ForEach(CoinPackage.all) { pack in
                        let price = store.price(pack)
                        Button { selected = pack } label: {
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
                        Button("Refresh") { Task { await refresh() } }
                        Spacer()
                        Button("Wallet activity") { showHistory = true }
                    }.font(.subheadline.weight(.semibold)).padding(.vertical, 8)
                    Button("My backpack") { app.go("store.bag") }.font(.subheadline.weight(.semibold))
                }.padding(.horizontal, 20).padding(.vertical, 18)
            }.refreshable { await refresh() }
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .background { NativeArt("wallet", 1).ignoresSafeArea().accessibilityHidden(true) }
        .toolbar(.hidden, for: .navigationBar)
        .task { await refresh() }
        .onChange(of: store.revision) { _ in
            read = UUID()
            if store.sandboxDelivery { sandboxBalance = store.confirmedBalance }
            else { balance = store.confirmedBalance }
            Task { await loadBalance() }
        }
        .onChange(of: scenePhase) { phase in if phase == .active { store.recover() } }
        .onDisappear { checkout?.cancel() }
        .alert(item: $selected) { pack in
            Alert(title: Text("Add \(pack.coins.formatted()) star coins?"),
                  message: Text(store.price(pack).map { "Confirm your purchase for " + $0 + "." } ?? "This package is unavailable."),
                  primaryButton: .default(Text("Continue")) { checkout = Task { await store.buy(pack) } },
                  secondaryButton: .cancel())
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
            let row = try await app.api.rows("wallets?select=balance&owner_id=eq." + owner).first
            guard ticket == read, owner == app.api.userID, !Task.isCancelled else { return }
            balance = row?["balance"] as? Int
            balanceError = balance == nil
            let sandbox = try? await app.api.rows("sandbox_wallets?select=balance&owner_id=eq." + owner)
            if ticket == read, owner == app.api.userID, !Task.isCancelled, let sandbox {
                sandboxBalance = sandbox.first?["balance"] as? Int
            }
        } catch {
            if ticket == read && !Task.isCancelled { balanceError = true; balance = nil }
        }
    }
}

private struct WalletActivity: View {
    @EnvironmentObject private var app: MiNaAppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WalletStore
    @State private var items: [Entry] = []
    @State private var message = "Loading activity…"

    private struct Entry: Identifiable {
        let id: String
        let kind: String
        let amount: Int
        let date: Date
    }

    var body: some View {
        NavigationStack {
            List {
                if !message.isEmpty { Text(message) }
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.kind)
                            Text(item.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.amount.formatted(.number.sign(strategy: .always(includingZero: false))))
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("Recent activity").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .refreshable { await load() }
            .task(id: store.revision) { await load() }
        }
    }

    private func load() async {
        do {
            let owner = app.api.userID
            let filter = "&owner_id=eq." + owner + "&order=created_at.desc&limit=50"
            async let credits = app.api.rows("coin_purchases?select=environment,transaction_id,coins,created_at" + filter)
            async let debits = app.api.rows("wallet_ledger?select=id,kind,amount,created_at" + filter)
            let (purchases, spending) = try await (credits, debits)
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let seconds = ISO8601DateFormatter()
            let entries: [Entry] = (purchases + spending).compactMap { row in
                guard let stamp = row["created_at"] as? String, let date = parser.date(from: stamp) ?? seconds.date(from: stamp) else { return nil }
                if let id = row["transaction_id"] as? String, let coins = row["coins"] as? Int {
                    let sandbox = row["environment"] as? String == "Sandbox"
                    return Entry(id: (sandbox ? "sandbox-" : "store-") + id, kind: sandbox ? "Sandbox purchase" : "Star coin purchase", amount: coins, date: date)
                }
                guard let id = row["id"] as? String, let amount = row["amount"] as? Int else { return nil }
                return Entry(id: id, kind: row["kind"] as? String == "send" ? "Gift sent" : "Backpack item", amount: -amount, date: date)
            }
            guard owner == app.api.userID, !Task.isCancelled else { return }
            items = Array(entries.sorted { $0.date > $1.date }.prefix(50))
            message = items.isEmpty ? "No wallet activity yet." : ""
        } catch { if !Task.isCancelled { message = "Activity could not be loaded. Pull to refresh." } }
    }
}

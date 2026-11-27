import StoreKit
import SwiftUI

struct WalletScreen: View {
    @EnvironmentObject private var app: MiNaAppModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: WalletStore
    @State private var showHistory = false
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
                                if let balance = store.ledger?.balance { Text(balance.formatted()).font(.largeTitle.bold().monospacedDigit()) }
                                else if !store.problem.isEmpty { Text("—").font(.headline) }
                                else { ProgressView() }
                            }.accessibilityIdentifier("wallet.balance")
                            Text("Star coins on this iPhone").font(.caption)

                        }
                        Spacer()
                        NativeArt("wallet", 3).scaledToFit().frame(width: 124, height: 132).accessibilityHidden(true)
                    }
                    if !store.catalogMessage.isEmpty { Text(store.catalogMessage).font(.footnote) }
                    if !store.message.isEmpty { Text(store.message).font(.callout).accessibilityIdentifier("wallet.status") }
                    ForEach(CoinPackage.all) { pack in
                        let price = store.price(pack)
                        Button { store.buy(pack) } label: {
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
                        .disabled(store.ledger == nil || price == nil || store.busy || !SKPaymentQueue.canMakePayments())
                        .accessibilityLabel("\(pack.coins) star coins, \(price ?? "unavailable")")
                        .accessibilityIdentifier("wallet.package.\(pack.coins)")
                    }
                    HStack {
                        Text("Purchase history").font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("View all") { showHistory = true }.font(.subheadline)
                    }.padding(.top, 8)
                    WalletActivity(store: store, purchasesOnly: true)
                }.padding(.horizontal, 20).padding(.vertical, 18)
            }.refreshable { refresh() }
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .pageBackground("wallet")
        .toolbar(.hidden, for: .navigationBar)
        .minaAlert(store.problem)
        .minaAlert(store.catalogProblem)
        .minaAlert(SKPaymentQueue.canMakePayments() ? "" : "Purchases are disabled on this iPhone.")
        .task { refresh() }
        .onChange(of: scenePhase) { phase in if phase == .active { store.recover() } }
        .sheet(item: Binding(get: { store.notices.first }, set: { _ in })) { notice in
            PopupPanel(title: "Purchase successful", message: "\(notice.coins.formatted()) star coins added.") {
                PopupAction("OK", "checkmark") {
                    if store.notices.first?.id == notice.id { store.dismissNotice() }
                }
            }.modifier(FittedPopup()).interactiveDismissDisabled()
        }
        .sheet(isPresented: $showHistory) { WalletActivity(store: store) }
    }

    private func refresh() {
        store.reloadLedger()
        store.loadCatalog()
        store.recover()
    }
}

private struct WalletActivity: View {
    @EnvironmentObject private var app: MiNaAppModel
    @State private var earlierSpending: [GiftSpending.Activity] = []
    @State private var activityError = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WalletStore
    var purchasesOnly = false
    private var items: [Entry] {
        guard let wallet = store.ledger else { return [] }
        var rows = wallet.credits.map { Entry(id: "purchase-" + $0.id, kind: "Star coin purchase", amount: $0.coins, date: $0.date) }
        if !purchasesOnly {
            rows += wallet.spending.map {
                Entry(id: $0.id, kind: $0.pending ? "Gift pending" : ($0.isStore ? "Backpack item" : "Gift sent"),
                      amount: -($0.coins + ($0.cloudCoins ?? 0)), date: $0.date)
            }
        }
        if !purchasesOnly, store.environment == .production {
            let localIDs = Set(wallet.spending.map(\.id))
            rows += earlierSpending.filter { !localIDs.contains($0.id) }
        }
        return Array(rows.sorted { $0.date > $1.date }.prefix(50))
    }

    private var message: String {
        guard store.ledger != nil else { return "" }
        return items.isEmpty ? (purchasesOnly ? "No purchases yet." : "No wallet activity yet.") : ""
    }

    private typealias Entry = GiftSpending.Activity

    private func loadEarlierSpending() async {
        let owner = store.owner
        guard !purchasesOnly, store.environment == .production, !owner.isEmpty else { return }
        do {
            let result = try await app.gifts.recentActivity(owner: owner)
            guard !Task.isCancelled, owner == store.owner else { return }
            earlierSpending = result
            activityError = ""
        } catch {
            if !Task.isCancelled, owner == store.owner { activityError = "Earlier gift activity could not be loaded. Pull to retry." }
        }
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
                VStack(spacing: 0) {
                    PopupHeading(title: "Recent activity", closeLabel: "Done") { dismiss() }
                        .padding(.horizontal, 20).padding(.top, 18)
                    List {
                        if !message.isEmpty && activityError.isEmpty { Text(message) }
                        ForEach(items) { item in entryRow(item) }
                    }.scrollContentBackground(.hidden)
                    .refreshable { store.reloadLedger(); await loadEarlierSpending() }
                    .task(id: store.owner + store.environment.rawValue) {
                        earlierSpending = []
                        activityError = ""
                        await loadEarlierSpending()
                    }
                }.popupSurface()
            }
        }.minaAlert(activityError).minaAlert(store.problem)
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

}

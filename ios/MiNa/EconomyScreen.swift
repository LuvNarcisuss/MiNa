import StoreKit
import SwiftUI

struct EconomyScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var balance: Int?
    @State private var catalog: [Gift] = []
    @State private var inventory: [Int: Int] = [:]
    @State private var level: [String: Any] = [:]
    @State private var selected: Gift?
    @State private var busy = false
    @State private var notice = ""
    @State private var loaded = false
    private var bag: Bool { route.name == "store.bag" }

    private struct Gift: Identifiable {
        let id: Int
        let price: Int
        var name: String { EconomyScreen.names[id] }
    }
    private static let names = ["Sleep Mask","Cloud Kitten","Triple Six","Stardust Jar","Wishing Star","Moon Headphones","Rain Cloud","Dream Pillow","Dreamcatcher","Bunny Slippers","Sleeping Moon","Soft Slumber","Night Orbit","Star Friend","Sleepy Bear","Moonlight Bed","Heartbeat","Heart Headphones","Star Wand","Moon Lantern"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if route.name == "wallet" {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("My balance")
                            if let balance { Text(balance.formatted()).font(.largeTitle.bold()) }
                            Text("Star coins").font(.caption)
                        }
                        Spacer()
                        NativeArt("wallet", 3).scaledToFit().frame(width: 76)
                    }.padding().background(Color.mint.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                    Text("Coin packages").font(.headline)
                    Text(SKPaymentQueue.canMakePayments() ? "Coin packages are not available yet." : "Purchases are disabled on this iPhone.")
                    Button("Check again") { Task { await load() } }
                    Button("My backpack") { app.go("store.bag") }
                } else if route.name == "level" {
                    if let current = level["current_level"] as? Int, let contribution = level["contribution"] as? Int {
                        Text("Gift contribution").font(.headline)
                        Text("\(contribution.formatted()) coins").font(.title.bold())
                        Text("VIP \(current)")
                        if let next = level["next_threshold"] as? Int { Text("\(next.formatted()) coins for the next level") }
                        else { Text("Highest level reached") }
                        let badges = [12,11,10,9,8,7,6,5,4,13,3,2,1]
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                            ForEach(badges.indices, id: \.self) { n in
                                NativeArt("medals", badges[n] + (n <= current ? 0 : 13)).scaledToFit().accessibilityLabel("VIP \(n)")
                            }
                        }
                    }
                } else {
                    Picker("Collection", selection: Binding(get: { bag }, set: { value in app.go(value ? "store.bag" : "store") })) {
                        Text("Store").tag(false); Text("Backpack").tag(true)
                    }.pickerStyle(.segmented)
                    let visible = catalog.filter { !bag || inventory[$0.id, default: 0] > 0 }
                    if loaded && visible.isEmpty { Text(bag ? "Your backpack is empty." : "No gifts are available.") }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        ForEach(visible) { gift in
                            Button { selected = gift } label: {
                                VStack {
                                    NativeArt("store", 3 + gift.id).scaledToFit().frame(height: 65)
                                    Text(gift.name).font(.caption)
                                    Text(bag ? "× \(inventory[gift.id, default: 0])" : gift.price == 0 ? "Free" : "\(gift.price) coins")
                                        .font(.caption2)
                                }.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                if !loaded && notice.isEmpty { ProgressView() }
                if !notice.isEmpty { Text(notice); Button("Refresh") { Task { await load() } } }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(route.name == "wallet" ? "My wallet" : route.name == "level" ? "My level" : "Store")
        .background(Color.mint.opacity(0.08))
        .task(id: route) { await load() }
        .sheet(item: $selected) { gift in
            VStack(spacing: 14) {
                NativeArt("store", 3 + gift.id).scaledToFit().frame(height: 100)
                Text(gift.name).font(.title2.bold())
                if bag { Text("Owned: \(inventory[gift.id, default: 0])") }
                else {
                    Text(gift.price > 0 ? "Add one for \(gift.price) star coins." : "Claim one free gift for today.")
                    if let balance { Text("Balance: \(balance) star coins") }
                    if let balance, balance < gift.price {
                        Button("Open wallet") { selected = nil; app.go("wallet") }
                    } else {
                        Button("Confirm") { Task { await acquire(gift) } }.disabled(balance == nil || busy)
                            .buttonStyle(.borderedProminent)
                    }
                }
                if !notice.isEmpty { Text(notice).font(.footnote) }
                Button("Close") { selected = nil }.disabled(busy)
            }.padding().presentationDetents([.medium]).interactiveDismissDisabled(busy)
        }
    }

    private func load() async {
        do {
            let me = app.api.userID
            balance = try await app.api.rows("wallets?select=balance&owner_id=eq." + me).first?["balance"] as? Int
            if route.name == "level" {
                let response = try await app.api.rest("rpc/my_level", method: "POST", body: [String: String]())
                level = (response as? [[String: Any]])?.first ?? [:]
            } else if route.name.hasPrefix("store") {
                catalog = try await app.api.rows("gift_catalog?select=gift_index,unit_price&order=gift_index").compactMap { row in
                    guard let id = row["gift_index"] as? Int, Self.names.indices.contains(id), let price = row["unit_price"] as? Int else { return nil }
                    return Gift(id: id, price: price)
                }
                let items = try await app.api.rows("gift_inventory?select=gift_index,quantity&owner_id=eq." + me)
                inventory = items.reduce(into: [:]) { values, row in
                    if let id = row["gift_index"] as? Int, let quantity = row["quantity"] as? Int { values[id] = quantity }
                }
            }
            loaded = true; notice = ""
        } catch { if !Task.isCancelled { notice = error.localizedDescription } }
    }

    private func acquire(_ gift: Gift) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let key = "store.operation." + String(gift.id)
            let operation = app.state(key) as? String ?? UUID().uuidString
            try app.save(key, operation)
            try await app.api.rest("rpc/acquire_gift", method: "POST", body: ["gift_index":gift.id, "quantity":1, "operation":operation] as [String: Any])
            try app.save(key, nil)
            selected = nil
            await load()
        } catch { notice = error.localizedDescription }
    }
}

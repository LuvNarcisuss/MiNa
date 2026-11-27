import SwiftUI

struct EconomyScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var cloudBalance: Int?
    @State private var cloudInventory: [Int: Int] = [:]
    @EnvironmentObject private var wallet: WalletStore
    private var balance: Int? {
        guard let cloudBalance, let local = wallet.ledger?.balance else { return nil }
        return cloudBalance + local
    }
    private var inventory: [Int: Int] { cloudInventory.merging(wallet.ledger?.inventory ?? [:], uniquingKeysWith: +) }
    @State private var catalog: [Gift] = []
    @State private var level: [String: Any] = [:]
    @State private var returnGiftID: Int?
    @State private var navigateToWallet = false
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
                if route.name == "level" {
                    if let current = level["current_level"] as? Int, let contribution = level["contribution"] as? Int {
                        VStack(alignment: .leading,spacing: 7) {
                            Text("Gift contribution").font(.caption)
                            HStack { NativeArt("level",17).scaledToFit().frame(width:26); Text(contribution.formatted()).font(.title.bold()) }
                            if let next = level["next_threshold"] as? Int {
                                ProgressView(value: min(Double(contribution),Double(next)), total: Double(max(1,next))).tint(.white)
                                Text("VIP \(current) · \(next.formatted()) coins for the next level").font(.footnote)
                            } else { Text("VIP \(current) · Highest level reached") }
                        }.padding(16).frame(maxWidth: .infinity,alignment: .leading).background { NativeArt("level",16) }
                        LevelJourney(current: current)
                    }
                } else {
                    Picker("Collection", selection: Binding(get: { bag }, set: { value in app.go(value ? "store.bag" : "store") })) {
                        Text("Store").tag(false); Text("Backpack").tag(true)
                    }.pickerStyle(.segmented)
                    let visible = catalog.filter { !bag || inventory[$0.id, default: 0] > 0 }
                    if loaded && visible.isEmpty { Text(bag ? "Your backpack is empty." : "No gifts are available.") }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                        ForEach(visible) { gift in
                            Button { selected = gift } label: {
                                VStack {
                                    NativeArt("store", 3 + gift.id).scaledToFit().frame(height: 55)
                                    Text(gift.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                                    Text(bag ? "× \(inventory[gift.id, default: 0])" : gift.price == 0 ? "Free" : "\(gift.price) coins")
                                        .font(.caption2)
                                }.padding(4).frame(maxWidth: .infinity,minHeight: 108).background(.white,in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !loaded && notice.isEmpty { ProgressView() }
                if !notice.isEmpty { Button("Refresh") { Task { await load() } } }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(route.name == "level" ? "My level" : "Store")
        .navigationBarTitleDisplayMode(.inline)

        .pageBackground(route.name == "level" ? "level" : "store")
        .minaAlert(notice)
        .task(id: route) {
            await load()
            if let id = returnGiftID, app.route == route, !Task.isCancelled {
                selected = catalog.first { $0.id == id }; returnGiftID = nil
            }
        }
        .sheet(item: $selected, onDismiss: {
            if navigateToWallet { navigateToWallet = false; app.go("wallet") }
        }) { gift in
            let title = bag ? "Backpack" : (balance ?? gift.price) < gift.price ? "Insufficient balance" : "Confirm gift"
            PopupPanel(title: title, closeLabel: "Close", close: { if !busy { selected = nil } }) {
                VStack(spacing: 12) {
                    NativeArt("store", 3 + gift.id).scaledToFit().frame(height: 76)
                    Text(gift.name).font(.headline)
                    if bag { Text("Owned: \(inventory[gift.id, default: 0])") }
                    else {
                        Text(gift.price > 0 ? "Add one for \(gift.price) star coins." : "Claim one free gift for today.")
                        if let balance { Text("Balance: \(balance) star coins") }
                        if let balance, balance < gift.price {
                            PopupAction("Open wallet", "wallet.pass") { returnGiftID = gift.id; navigateToWallet = true; selected = nil }
                        } else {
                            PopupAction("Confirm", "checkmark") { Task { await acquire(gift) } }
                                .disabled(balance == nil || busy).opacity(balance == nil || busy ? 0.48 : 1)
                        }
                    }
                }.frame(maxWidth: .infinity)
            }.disabled(busy).modifier(FittedPopup()).interactiveDismissDisabled(busy)
        }
    }

    private func load() async {
        do {
            let me = app.api.userID
            if route.name == "level" {
                let response = try await app.api.rest("rpc/my_level", method: "POST", body: [String: String]())
                level = (response as? [[String: Any]])?.first ?? [:]
            } else if route.name.hasPrefix("store") {
                try await app.gifts.recover()
                cloudBalance = try await app.api.rows("wallets?select=balance&owner_id=eq." + me).first?["balance"] as? Int
                catalog = try await app.api.rows("gift_catalog?select=gift_index,unit_price&order=gift_index").compactMap { row in
                    guard let id = row["gift_index"] as? Int, Self.names.indices.contains(id), let price = row["unit_price"] as? Int else { return nil }
                    return Gift(id: id, price: price)
                }
                let items = try await app.api.rows("gift_inventory?select=gift_index,quantity&owner_id=eq." + me)
                cloudInventory = items.reduce(into: [:]) { values, row in
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
        let owner = app.api.userID
        let key = "store.operation." + String(gift.id)
        do {
            let savedOperation = app.state(key) as? String
            let operation = savedOperation ?? UUID().uuidString
            try app.save(key, operation)
            try await app.gifts.spend(id: operation, item: gift.id, quantity: 1, price: gift.price, resumed: savedOperation != nil)
            guard owner == app.api.userID else { return }
            try app.save(key, nil)
            selected = nil
            await load()
        } catch {
            guard owner == app.api.userID else { return }
            if (error as? MiNaIssue)?.code == "gift_canceled" { try? app.save(key, nil) }
            notice = error.localizedDescription
        }
    }
}

private struct LevelJourney: View {
    let current: Int
    private let badges = [12,11,10,9,8,7,6,5,4,13,3,2,1]
    private let rowHeight: CGFloat = 108
    private let top: CGFloat = 32

    var body: some View {
        GeometryReader { box in
            let width = box.size.width
            let badgeWidth = min(91,width * 0.24)
            let inset = badgeWidth / 2
            let centers = [inset,width / 2,width - inset]
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: centers[0], y: top))
                    for row in 0..<4 {
                        let right = row.isMultiple(of: 2)
                        let start = right ? centers[2] : centers[0]
                        let outside = right ? width - 12 : 12
                        let y = top + CGFloat(row) * rowHeight
                        path.addLine(to: CGPoint(x: start,y: y))
                        path.addQuadCurve(to: CGPoint(x: outside,y: y + rowHeight * 0.4),
                                          control: CGPoint(x: outside,y: y))
                        path.addLine(to: CGPoint(x: outside,y: y + rowHeight * 0.6))
                        path.addQuadCurve(to: CGPoint(x: start,y: y + rowHeight),
                                          control: CGPoint(x: outside,y: y + rowHeight))
                    }
                }.stroke(.white,style: StrokeStyle(lineWidth: 10,lineCap: .round,lineJoin: .round))
                    .accessibilityHidden(true)
                ForEach(badges.indices,id: \.self) { level in
                    let row = level / 3
                    let column = row.isMultiple(of: 2) ? level % 3 : 2 - level % 3
                    NativeArt("medals",badges[level] + (level <= current ? 0 : 13))
                        .scaledToFit().frame(width: badgeWidth,height: 44)
                        .position(x: centers[column],y: top + CGFloat(row) * rowHeight)
                        .accessibilityLabel("VIP \(level), " + (level <= current ? "earned" : "locked"))
                }
            }
        }.frame(height: top + rowHeight * 4 + 30)
    }
}

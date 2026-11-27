import SwiftUI

struct RoomInvitations: View {
    @EnvironmentObject var app: MiNaAppModel
    let id: String
    @State private var friends: [RoomRow] = []
    @State private var loaded = false
    @State private var error = ""
    @State private var busy = false
    @State private var sent = Set<String>()
    @State private var operations: [String:String] = [:]
    @State private var retry = 0
    var body: some View {
        RoomPanelList {
            Text("Invitations appear in your friend’s conversation. Room visibility still applies.")
            ForEach(Array(friends.enumerated()),id: \.offset) { _,person in
                let uid = person.roomText("id")
                HStack { Text(person.roomText("name")); Spacer(); Button(sent.contains(uid) ? "Sent" : "Invite") {
                    busy = true
                    Task { defer { busy = false }; do {
                        let op = operations[uid] ?? roomUUID(); operations[uid] = op
                        if try await app.api.rows("messages?select=id&id=eq." + op).isEmpty {
                            _ = try await app.api.rest("messages",method: "POST",body: ["id":op,"sender_id":app.api.userID,"recipient_id":uid,"body":"mina:room:" + id])
                        }
                        sent.insert(uid); error = ""
                    } catch { self.error = error.localizedDescription } }
                }.disabled(busy || sent.contains(uid)) }
            }
            if friends.isEmpty && error.isEmpty { RoomEmptyPanel(title: loaded ? "No friends to invite" : "Finding friends…",detail: "Friends are people who follow each other.") }
            if !error.isEmpty { Button("Retry") { error = ""; retry += 1 } }
        }.minaAlert(error).task(id: retry) {
            do {
                let me = app.api.userID
                async let outgoing = app.api.rows("follows?select=followed_id&follower_id=eq." + me)
                async let incoming = app.api.rows("follows?select=follower_id&followed_id=eq." + me)
                let (a,b) = try await (outgoing,incoming)
                let ids = Set(a.map { $0.roomText("followed_id") }).intersection(b.map { $0.roomText("follower_id") })
                friends = ids.isEmpty ? [] : try await app.api.rows("profiles?select=id,name&id=in.(" + ids.joined(separator: ",") + ")")
                loaded = true; error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct RoomGiftCatalog: View {
    let choices: [Int]
    let selected: Int
    let price: (Int) -> String?
    let select: (Int) -> Void
    @State private var page = 0
    var body: some View {
        let pages = (choices.count + 7) / 8
        VStack(spacing: 3) {
            TabView(selection: $page) {
                ForEach(0..<pages,id: \.self) { number in
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()),count: 4)) {
                        ForEach(Array(choices.dropFirst(number * 8).prefix(8)),id: \.self) { i in
                            Button { select(i) } label: {
                                VStack(spacing: 2) {
                                    NativeArt("store",i+3).scaledToFit().frame(height: 42).padding(3)
                                        .frame(maxWidth: .infinity).background(.white.opacity(0.8),in: RoundedRectangle(cornerRadius: 9))
                                        .overlay { if selected == i { RoundedRectangle(cornerRadius: 9).stroke(.teal,lineWidth: 2) } }
                                    Text(RoomGifts.names[i]).font(.caption2).lineLimit(1)
                                    if let label = price(i) { Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            }.buttonStyle(.plain).accessibilityAddTraits(selected == i ? .isSelected : [])
                        }
                    }.frame(maxHeight: .infinity,alignment: .top).tag(number)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 168)
            if pages > 1 { HStack(spacing: 5) { ForEach(0..<pages,id: \.self) { i in
                Circle().fill(page == i ? Color.teal : .gray.opacity(0.36)).frame(width: 6,height: 6)
            } }.frame(maxWidth: .infinity).accessibilityHidden(true) }
        }.onChange(of: choices) { _ in page = 0 }
    }
}

struct RoomGifts: View {
    static let names = ["Sleep Mask","Cloud Kitten","Triple Six","Stardust Jar","Wishing Star","Moon Headphones","Rain Cloud","Dream Pillow","Dreamcatcher","Bunny Slippers","Sleeping Moon","Soft Slumber","Night Orbit","Star Friend","Sleepy Bear","Moonlight Bed","Heartbeat","Heart Headphones","Star Wand","Moon Lantern"]
    @EnvironmentObject var app: MiNaAppModel

    let id: String
    @ObservedObject var session: NativeRoomSession
    let initialRecipient: String?
    let close: () -> Void
    let inviteFriend: () -> Void
    let openWallet: () throws -> Void
    @State private var index = 0
    @State private var recipient = ""
    @State private var quantity = 1
    @State private var backpack = false
    @State private var operation = ""
    @State private var prices: [Int:Int] = [:]
    @State private var cloudInventory: [Int: Int] = [:]
    @State private var cloudBalance: Int?
    @EnvironmentObject private var wallet: WalletStore
    private var inventory: [Int: Int] {
        cloudInventory.merging(wallet.ledger?.inventory ?? [:], uniquingKeysWith: +)
    }
    private var balance: Int? {
        guard let cloudBalance, let local = wallet.ledger?.balance else { return nil }
        return cloudBalance + local
    }
    @State private var confirm = false
    @State private var busy = false
    @State private var sent = false
    @State private var error = ""
    @State private var retry = 0
    var key: String { "room.gift." + id }
    var total: Int? { prices[index].map { backpack ? 0 : quantity * $0 } }
    var limit: Int { backpack ? min(99,inventory[index] ?? 0) : prices[index] == 0 ? 1 : 99 }
    var others: [String] { session.members.map { $0.roomText("user_id") }.filter { $0 != app.api.userID.lowercased() } }
    var valid: Bool { session.active && session.room?.roomFlag("allow_gifts") == true && others.contains(recipient) && total != nil && quantity <= limit && (total == 0 || balance != nil) }
    func retain(_ op: String) throws {
        try app.save(key,["index":index,"recipient":recipient,"quantity":quantity,"backpack":backpack,"operation":op] as RoomRow)
    }
    private var recipientMenu: some View {
        PopupMenu("Recipient") {
            ForEach(others, id: \.self) { uid in
                PopupAction(session.name(uid), "person", selected: uid == recipient) { change($recipient, uid) }
            }
        } label: {
            Label(others.contains(recipient) ? session.name(recipient) : "Select a recipient", systemImage: "person.2")
                .frame(minHeight: 44)
        }
    }

    func change<T>(_ binding: Binding<T>,_ value: T) { binding.wrappedValue = value; operation = ""; confirm = false; error = "" }
    private func updateRecipient() {
        guard !busy, !sent, !others.contains(recipient) else { return }
        confirm = false
        // A saved operation can only be retried for its original recipient.
        guard operation.isEmpty else { return }
        recipient = others.count == 1 ? others[0] : ""
    }
    var body: some View {
        RoomPanelList {
            if sent {
                Text("Gift sent").font(.headline)
                Text("\(quantity) × " + Self.names[index] + " sent to " + session.name(recipient) + ".")
                Button("Done") { close() }.buttonStyle(RoomCapsuleStyle())
            } else {
                if !confirm {
                    Picker("Gift source",selection: Binding(get: { backpack },set: { value in
                        change($backpack,value); quantity = 1
                        if value, let owned = inventory.keys.sorted().first(where: { inventory[$0,default: 0] > 0 }) { index = owned }
                    })) { Text("Catalog").tag(false); Text("Backpack").tag(true) }.pickerStyle(.segmented)
                    let choices = Self.names.indices.filter { !backpack || inventory[$0,default: 0] > 0 }
                    if choices.isEmpty { Text("Your backpack is empty.") }
                    RoomGiftCatalog(choices: choices,selected: index,price: { i in
                        backpack ? "\(inventory[i,default: 0]) owned" : prices[i].map { $0 == 0 ? "Free" : "\($0) coins" } ?? "Unavailable"
                    },select: { i in change($index,i); quantity = 1 })
                    if others.isEmpty {
                        Label("No available recipients", systemImage: "person.2").foregroundStyle(.secondary)
                    } else {
                        recipientMenu
                    }
                    Stepper("Quantity: \(quantity)",value: Binding(get: { quantity },set: { change($quantity,$0) }),in: 1...max(1,limit))
                } else {
                    VStack(spacing: 10) { NativeArt("store",index+3).scaledToFit().frame(height: 55); Text("Confirm gift").font(.title3.bold()); Text("\(quantity) × " + Self.names[index]); Text("Recipient: " + session.name(recipient)) }.frame(maxWidth: .infinity).padding().background { NativeArt("spend",5) }
                }
                LabeledContent("Total",value: total.map { "\($0) coins" } ?? "Unavailable")
                LabeledContent("Balance",value: balance.map { "\($0) coins" } ?? "Unavailable")
                if let total,let balance,total > balance {
                    Text("Insufficient balance").font(.headline)
                }
                if confirm { Button("Change selection") { confirm = false }.disabled(busy) }
            }
            if !error.isEmpty { Button("Refresh catalog") { error = ""; retry += 1 } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !sent {
                Group {
                    if busy {
                        Button("Sending…") {}.disabled(true)
                    } else if !session.active {
                        Button("Connecting…") {}.disabled(true)
                    } else if session.room?.roomFlag("allow_gifts") != true {
                        Button("Room gifts are off") {}.disabled(true)
                    } else if others.isEmpty {
                        Button("Invite a friend") {
                            do { try retain(operation); inviteFriend() } catch { self.error = error.localizedDescription }
                        }
                    } else if !others.contains(recipient) {
                        recipientMenu
                    } else if let total, let balance, total > balance {
                        Button("Open wallet") { do { try retain(operation); try openWallet() } catch { self.error = error.localizedDescription } }
                    } else {
                        Button(confirm ? "Confirm and send" : "Review gift") {
                            if confirm { send() } else { confirm = true }
                        }.disabled(!valid || busy)
                    }
                }.buttonStyle(RoomCapsuleStyle()).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(red: 0.91, green: 0.99, blue: 0.99))
            }
        }
        .onChange(of: others) { _ in updateRecipient() }
        .onChange(of: busy) { if !$0 { updateRecipient() } }
        .onChange(of: session.room?.roomFlag("allow_gifts")) { if $0 != true && !busy { confirm = false } }
        .minaAlert(error).interactiveDismissDisabled(busy).task(id: retry) {
            if retry == 0,let state = app.state(key) as? RoomRow {
                index = min(max(0,state["index"] as? Int ?? 0),Self.names.count-1)
                quantity = min(max(1,state["quantity"] as? Int ?? 1),99); recipient = state.roomText("recipient")
                backpack = state.roomFlag("backpack"); operation = state.roomText("operation")
            }
            if retry == 0, let initialRecipient, operation.isEmpty { recipient = initialRecipient }
            updateRecipient()
            do {
                let me = app.api.userID
                try await app.gifts.recover()
                async let wallets = app.api.rows("wallets?select=balance&owner_id=eq." + me)
                async let catalog = app.api.rows("gift_catalog?select=gift_index,unit_price")
                async let owned = app.api.rows("gift_inventory?select=gift_index,quantity&owner_id=eq." + me)
                let (w,c,b) = try await (wallets,catalog,owned)
                cloudBalance = w.first?["balance"] as? Int
                prices = indexed(c,"unit_price"); cloudInventory = indexed(b,"quantity"); error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
    func indexed(_ values: [RoomRow],_ field: String) -> [Int:Int] {
        values.reduce(into: [:]) { result,row in if let i = row["gift_index"] as? Int { result[i] = row[field] as? Int } }
    }
    func send() {
        guard valid && !busy else { return }; busy = true
        let owner = app.api.userID
        Task { defer { busy = false }; do {
            let resumed = !operation.isEmpty
            if operation.isEmpty { operation = roomUUID() }
            try retain(operation)
            guard let price = prices[index] else { throw MiNaIssue("Refresh the gift catalog.") }
            try await app.gifts.spend(id: operation, item: index, quantity: quantity, price: price,
                                      room: id, recipient: recipient, fromBag: backpack, resumed: resumed)
            guard owner == app.api.userID else { return }
            try retain("")
            sent = true
            confirm = false
        } catch {
            guard owner == app.api.userID else { return }
            if (error as? MiNaIssue)?.code == "gift_canceled" { operation = ""; try? retain("") }
            self.error = error.localizedDescription
        } }
    }
}

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
        List {
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
            if friends.isEmpty && error.isEmpty { Text(loaded ? "No friends to invite." : "Finding friends…") }
            if !error.isEmpty { Text(error); Button("Retry") { retry += 1 } }
        }.task(id: retry) {
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

struct RoomGifts: View {
    static let names = ["Sleep Mask","Cloud Kitten","Triple Six","Stardust Jar","Wishing Star","Moon Headphones","Rain Cloud","Dream Pillow","Dreamcatcher","Bunny Slippers","Sleeping Moon","Soft Slumber","Night Orbit","Star Friend","Sleepy Bear","Moonlight Bed","Heartbeat","Heart Headphones","Star Wand","Moon Lantern"]
    @EnvironmentObject var app: MiNaAppModel
    @Environment(\.dismiss) var dismiss
    let id: String
    @ObservedObject var session: NativeRoomSession
    let openWallet: () throws -> Void
    @State private var index = 0
    @State private var recipient = ""
    @State private var quantity = 1
    @State private var backpack = false
    @State private var operation = ""
    @State private var prices: [Int:Int] = [:]
    @State private var inventory: [Int:Int] = [:]
    @State private var balance: Int?
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
    func change<T>(_ binding: Binding<T>,_ value: T) { binding.wrappedValue = value; operation = ""; confirm = false; error = "" }
    var body: some View {
        Form {
            if sent {
                Text("Gift sent").font(.headline)
                Text("\(quantity) × " + Self.names[index] + " sent to " + session.name(recipient) + ".")
                Button("Done") { dismiss() }
            } else {
                if !confirm {
                    Picker("Gift source",selection: Binding(get: { backpack },set: { value in
                        change($backpack,value); quantity = 1
                        if value, let owned = inventory.keys.sorted().first(where: { inventory[$0,default: 0] > 0 }) { index = owned }
                    })) { Text("Catalog").tag(false); Text("Backpack").tag(true) }.pickerStyle(.segmented)
                    let choices = Self.names.indices.filter { !backpack || inventory[$0,default: 0] > 0 }
                    if choices.isEmpty { Text("Your backpack is empty.") }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                        ForEach(choices,id: \.self) { i in
                            Button { change($index,i); quantity = 1 } label: {
                                VStack { NativeArt("store",i+3).scaledToFit().frame(height: 50); Text(Self.names[i]).font(.caption)
                                    Text(backpack ? "\(inventory[i,default: 0]) owned" : prices[i].map { $0 == 0 ? "Free" : "\($0) coins" } ?? "Unavailable").font(.caption2)
                                }.padding(4).frame(maxWidth: .infinity).background(index == i ? Color.teal.opacity(0.2) : .clear,in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).accessibilityAddTraits(index == i ? .isSelected : [])
                        }
                    }
                    Picker("Recipient",selection: Binding(get: { recipient },set: { change($recipient,$0) })) {
                        Text(others.isEmpty ? "No other participants" : "Select a recipient").tag("")
                        ForEach(others,id: \.self) { Text(session.name($0)).tag($0) }
                    }
                    Stepper("Quantity: \(quantity)",value: Binding(get: { quantity },set: { change($quantity,$0) }),in: 1...max(1,limit))
                } else { Text("\(quantity) × " + Self.names[index]); Text("Recipient: " + session.name(recipient)) }
                LabeledContent("Total",value: total.map { "\($0) coins" } ?? "Unavailable")
                LabeledContent("Balance",value: balance.map { "\($0) coins" } ?? "Unavailable")
                if let total,let balance,total > balance {
                    Button("Open wallet") { do { try retain(operation); try openWallet() } catch { self.error = error.localizedDescription } }
                } else {
                    Button(confirm ? "Confirm and send" : "Review gift") { if confirm { send() } else { confirm = true } }.disabled(!valid || busy)
                }
                if confirm { Button("Change selection") { confirm = false }.disabled(busy) }
            }
            if !error.isEmpty { Text(error); Button("Refresh catalog") { retry += 1 } }
        }.interactiveDismissDisabled(busy).task(id: retry) {
            if retry == 0,let state = app.state(key) as? RoomRow {
                index = min(max(0,state["index"] as? Int ?? 0),Self.names.count-1)
                quantity = min(max(1,state["quantity"] as? Int ?? 1),99); recipient = state.roomText("recipient")
                backpack = state.roomFlag("backpack"); operation = state.roomText("operation")
            }
            do {
                let me = app.api.userID
                async let wallets = app.api.rows("wallets?select=balance&owner_id=eq." + me)
                async let catalog = app.api.rows("gift_catalog?select=gift_index,unit_price")
                async let owned = app.api.rows("gift_inventory?select=gift_index,quantity&owner_id=eq." + me)
                let (w,c,b) = try await (wallets,catalog,owned)
                balance = w.first?["balance"] as? Int
                prices = indexed(c,"unit_price"); inventory = indexed(b,"quantity"); error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
    func indexed(_ values: [RoomRow],_ field: String) -> [Int:Int] {
        values.reduce(into: [:]) { result,row in if let i = row["gift_index"] as? Int { result[i] = row[field] as? Int } }
    }
    func send() {
        guard valid && !busy else { return }; busy = true
        Task { defer { busy = false }; do {
            if operation.isEmpty { operation = roomUUID() }
            try retain(operation)
            let request: RoomRow = ["target_room":id,"recipient":recipient,"gift_index":index,"quantity":quantity,"operation":operation,"use_inventory":backpack]
            let receipt = try await app.api.rest("rpc/send_gift",method: "POST",body: request) as? RoomRow
            guard receipt?.roomText("id").lowercased() == operation.lowercased() else { throw MiNaIssue("The gift receipt could not be confirmed. Retry this selection.") }
            balance = receipt?["balance"] as? Int; sent = true; confirm = false; try retain("")
        } catch { self.error = error.localizedDescription } }
    }
}

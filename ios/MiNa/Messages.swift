import SwiftUI

struct InboxRow: Identifiable {
    let values: [String: Any]
    var id: String { string("id").isEmpty ? string("peer_id") : string("id") }
    func string(_ key: String) -> String { values[key] as? String ?? "" }
    func count(_ key: String) -> Int { values[key] as? Int ?? 0 }
    func flag(_ key: String) -> Bool { values[key] as? Bool ?? false }
    var date: Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: string("created_at")) ?? ISO8601DateFormatter().date(from: string("created_at"))
    }
    var timestamp: String { date?.formatted(date: .abbreviated, time: .shortened) ?? "" }
    var roomID: String? {
        let body = string("body")
        guard body.hasPrefix("mina:room:") else { return nil }
        let id = String(body.dropFirst(10))
        return UUID(uuidString: id) == nil ? nil : id
    }
}

@MainActor
func inboxPeople(_ ids: [String], api: MiNaAPI) async throws -> [String: InboxRow] {
    let ids = Array(Set(ids.filter { UUID(uuidString: $0) != nil }))
    var people: [String: InboxRow] = [:]
    for start in stride(from: 0, to: ids.count, by: 80) {
        let group = ids[start..<min(start + 80, ids.count)].joined(separator: ",")
        for value in try await api.rows("profiles?select=id,name,avatar_path,allow_calls,allow_messages&id=in.(\(group))") {
            let person = InboxRow(values: value)
            people[person.id] = person
        }
    }
    return people
}

extension Notification.Name {
    static let inboxUpdated = Notification.Name("MiNa.inbox.updated")
}

struct InboxAvatar: View {
    @EnvironmentObject var app: MiNaAppModel
    let person: InboxRow?
    var size: CGFloat = 48
    @State private var url: URL?
    var body: some View {
        ZStack {
            Circle().fill(Color.mint.opacity(0.22))
            Text(String((person?.string("name") ?? "☾").prefix(1))).font(.title3)
            if let url { CloudPortraitImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear } }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: person?.string("avatar_path")) {
            url = nil
            guard let path = person?.string("avatar_path"), !path.isEmpty else { return }
            let result = try? await app.api.mediaURL(path)
            if !Task.isCancelled { url = result }
        }
    }
}

struct MessagesScreen: View {
    let route: NativeRoute
    var body: some View {
        Group {
            if route.name == "messages.call" { VoiceCallScreen(id: route.id ?? "") }
            else { MessageListScreen(route: route) }
        }.id(route.name + (route.id ?? ""))
    }
}

private struct MessageListScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var rows: [InboxRow] = []
    @State private var people: [String: InboxRow] = [:]
    @State private var following: [String] = []
    @State private var notices = 0
    @State private var query = ""
    @State private var draft = ""
    @State private var draftID = UUID().uuidString.lowercased()
    @State private var dialID = UUID().uuidString.lowercased()
    @State private var error = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var loading = false
    @State private var refreshPending = false
    @State private var revealedPeer: String?
    @State private var clear: InboxRow?
    @State private var confirmCall = false
    @Environment(\.scenePhase) private var phase
    @State private var isFriend = false
    @State private var preview: CallPreviewMode?
    @State private var showEmoji = false
    @State private var opened = ""
    @State private var take = 50
    @State private var lastRead = ""
    let categories = ["platform", "follow", "ranking"]
    let titles = ["platform": "Platform notifications", "follow": "New followers", "ranking": "Ranking updates"]
    var me: String { app.api.userID }
    var peer: String { route.id ?? "" }
    private var pinnedPeers: [String] { app.state("chat.pinnedPeers") as? [String] ?? [] }
    private var unreadPeers: [String] { app.state("chat.unreadPeers") as? [String] ?? [] }
    var draftKey: String { "chat.draft.\(peer)" }
    var inbox: Bool { route.name == "messages" }
    var thread: Bool { route.name == "messages.thread" }
    var calls: Bool { route.name == "messages.calls" }
    var category: Bool { route.name == "messages.notices.category" }
    var title: String {
        if inbox { return "Messages" }
        if thread { return people[peer]?.string("name") ?? "Conversation" }
        if calls { return "Recent calls" }
        return titles[peer] ?? "System notifications"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if !inbox { Text(title).font(.headline).lineLimit(1).padding(.horizontal, 55) }
                HStack(spacing: 10) {
                    if inbox {
                        Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                        Spacer()
                        Button { app.go("messages.calls") } label: {
                            Image(systemName: "phone").frame(width: 44, height: 44)
                        }.foregroundStyle(.white).accessibilityLabel("Recent calls")
                    } else {
                        Button { app.back() } label: {
                            NativeArt("notice", 2).frame(width: 24, height: 24).frame(width: 44, height: 44)
                        }.accessibilityLabel("Back")
                        Spacer()
                    }
                    if inbox || (!thread && !calls) {
                        Button { operate { if inbox { try await markAll() } else { try await markNotices() } } } label: {
                            NativeArt(inbox ? "inbox" : "notice", inbox ? 2 : 3).scaledToFit()
                                .frame(width: inbox ? 34 : 24).frame(width: 44, height: 44)
                        }.accessibilityLabel("Mark all as read")
                    } else if thread {
                        Button { app.go("person",peer) } label: {
                            NativeArt("chat",3).frame(width: 24,height: 24).frame(width: 44, height: 44)
                        }.accessibilityLabel("Profile and safety")
                    }
                }
            }.padding(.horizontal, inbox ? 18 : 6).frame(minHeight: 44)
            if !error.isEmpty {
                Button("Retry") { error = ""; Task { await refresh() } }
                    .padding(10).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
            }
            if inbox {
                HStack {
                    NativeArt("inbox", 11).frame(width: 18, height: 18)
                    TextField("", text: $query, prompt: Text("Search conversations").foregroundColor(.white.opacity(0.8)))
                        .foregroundStyle(.white).accessibilityLabel("Search conversations")
                }.padding(.horizontal, 13).frame(height: 40).background(.white.opacity(0.23), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.6), lineWidth: 1) }.padding(.horizontal, 18).padding(.bottom, 8)
            }
            if !loaded && error.isEmpty { ProgressView().padding() }
            if inbox {
                ScrollView {
                    LazyVStack(spacing: 8) { inboxContent }
                        .padding(.horizontal, 18).padding(.vertical, 4)
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        Group {
                            if thread { threadContent }
                            else if calls { callContent }
                            else { noticeContent }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .onChange(of: rows.first?.id) { newest in
                        if thread, let newest, lastRead.isEmpty || rows.first?.string("sender_id") == me {
                            proxy.scrollTo(newest, anchor: .bottom)
                        }
                    }
                }
            }
            if thread { composer }
        }
        .buttonStyle(.plain)
        .toolbar(.hidden, for: .navigationBar)
        .pageBackground(inbox ? "inbox" : thread ? "chat" : category ? "noticeDetail" : "notice")
        .minaAlert(error)
        .task {
            if thread, let saved = app.state(draftKey) as? [String:String] {
                draft = saved["body"] ?? ""
                draftID = saved["id"] ?? draftID
            }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .onChange(of: phase) { next in
            if thread && next == .active { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .inboxUpdated)) { _ in Task { await refresh() } }
        .popupDialog("Delete this conversation?", isPresented: Binding(get: { clear != nil }, set: { if !$0 { clear = nil } }),
                     message: "This removes the conversation from your inbox.") {
            if let selected = clear {
                PopupAction("Delete", "trash", role: .destructive) {
                    operate { try await mark(selected.id, selected.string("latest_id"), clear: true) }
                }
            }
        }
        .fullScreenCover(item: $preview) { mode in
            if let person = people[peer] {
                CallPreviewScreen(mode: mode, person: person, verifyFriendship: checkFriendship)
            }
        }
        .onChange(of: isFriend) { if !$0 { preview = nil; confirmCall = false; showEmoji = false } }
        .popupDialog("Start a voice call?", isPresented: $confirmCall) {
            PopupAction("Call \(title)", "phone") { operate {
                let result = try await rpc("start_voice_call", ["p_id": dialID, "p_peer": peer])
                guard let id = result as? String, UUID(uuidString: id) != nil else { throw VoiceFailure("The call could not be confirmed.") }
                dialID = UUID().uuidString.lowercased()
                app.go("messages.call",id)
            } }
        }
    }

    @ViewBuilder var inboxContent: some View {
        if !following.isEmpty {
            ScrollView(.horizontal,showsIndicators: false) {
                HStack { ForEach(following,id: \.self) { id in
                    Button { app.go("messages.thread",id) } label: {
                        VStack { InboxAvatar(person: people[id]); Text(people[id]?.string("name") ?? "Listener").font(.caption).lineLimit(1) }.frame(width: 72)
                    }
                } }
            }.listRowBackground(Color.clear)
        }
        Button { app.go("messages.notices") } label: {
            HStack { NativeArt("inbox",5).scaledToFit().frame(width: 46,height: 46); VStack(alignment: .leading, spacing: 4) { Text("System notifications").font(.headline); Text("Updates from MiNa").font(.caption).foregroundStyle(.secondary) }; Spacer(); badge(notices) }.messageCard()
        }
        let filtered = rows.filter { query.isEmpty || (($0.string("body") + (people[$0.id]?.string("name") ?? "")).localizedCaseInsensitiveContains(query)) }
        let pins = pinnedPeers
        let byPeer = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        ForEach(pins.compactMap { byPeer[$0] } + filtered.filter { !pins.contains($0.id) }) { row in
            let pinned = pins.contains(row.id)
            let unread = isUnread(row)
            ConversationSwipeRow(id: row.id, revealed: $revealedPeer, pinned: pinned, unread: unread, open: {
                app.go("messages.thread", row.id)
            }, pin: {
                do {
                    let remaining = pinnedPeers.filter { $0 != row.id }
                    try app.save("chat.pinnedPeers", pinned ? remaining : [row.id] + remaining)
                } catch { self.error = error.localizedDescription }
            }, markRead: {
                if unread { operate { try await mark(row.id, row.string("latest_id")) } }
                else {
                    do { try app.save("chat.unreadPeers", unreadPeers + [row.id]) }
                    catch { self.error = error.localizedDescription }
                }
            }, delete: { clear = row }) {
                HStack { InboxAvatar(person: people[row.id]); VStack(alignment: .leading) {
                    Text(people[row.id]?.string("name") ?? "Listener").bold()
                    Text(row.roomID == nil ? row.string("body") : "Voice room invitation").font(ReactionPicker.textFont(for: row.string("body"))).lineLimit(1).foregroundStyle(.secondary)
                }; Spacer()
                    VStack(alignment: .trailing) {
                        Text(row.timestamp).font(.caption2)
                        HStack(spacing: 5) {
                            if pinned {
                                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.teal)
                                    .accessibilityLabel("Pinned")
                            }
                            if row.count("unread") > 0 { badge(row.count("unread")) }
                            else if unread {
                                Circle().fill(.teal).frame(width: 9, height: 9)
                                    .accessibilityLabel("Unread")
                            }
                        }
                    }
                }.messageCard()
            }
        }
        if loaded && error.isEmpty && filtered.isEmpty {
            if query.isEmpty {
                InboxWelcomeCard { app.go("profile.search") }
            } else {
                emptyMessage("No matching conversations.")
            }
        }
    }

    @ViewBuilder func badge(_ count: Int) -> some View {
        if count > 0 { Text("\(count)").font(.caption.bold()).padding(.horizontal,6).background(.mint,in: Capsule()) }
    }

    @ViewBuilder var noticeContent: some View {
        if !category {
            ForEach(categories, id: \.self) { kind in
                Button { app.go("messages.notices.category",kind) } label: {
                    HStack { NativeArt("notice",kind == "platform" ? 4 : kind == "follow" ? 6 : 7).frame(width: 44,height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(titles[kind] ?? kind).font(.headline)
                            Text(rows.first(where: { $0.string("kind") == kind })?.string("body") ?? ["platform": "News and service updates", "follow": "People who followed you", "ranking": "Your room and gift rankings"][kind] ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }; Spacer(); badge(rows.filter { $0.string("kind") == kind && $0.string("read_at").isEmpty }.count) }.messageCard()
                }
            }
        } else {
            ForEach(rows) { row in
                Button { operate {
                    try await markNotices(id: row.id)
                    if peer == "follow" && !row.string("actor_id").isEmpty { app.go("person",row.string("actor_id")) }
                    else if peer == "ranking" { app.go("rooms.ranks") }
                    else { opened = opened == row.id ? "" : row.id }
                } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(row.string("title")).bold(); if row.string("read_at").isEmpty { Text("New").font(.caption).foregroundStyle(.teal) } }
                        Text(row.string("body")).lineLimit(opened == row.id ? nil : 2)
                        Text(row.timestamp).font(.caption).foregroundStyle(.secondary)
                    }.messageCard()
                }
            }
            if loaded && rows.isEmpty { emptyMessage("No notifications yet.") }
        }
    }

    @ViewBuilder var callContent: some View {
        ForEach(rows) { row in
            let outgoing = row.string("caller_id") == me
            let id = row.string(outgoing ? "callee_id" : "caller_id")
            let expired = row.string("state") == "ringing" && (row.date?.timeIntervalSinceNow ?? 0) < -45
            let active = ["ringing","accepted"].contains(row.string("state")) && !expired
            Button { app.go(active ? "messages.call" : "messages.thread", active ? row.id : id) } label: {
                HStack { InboxAvatar(person: people[id]); VStack(alignment: .leading) {
                    Text(people[id]?.string("name") ?? "Listener").bold()
                    Text((outgoing ? "Outgoing · " : "Incoming · ") + (expired ? "Invitation expired" : row.string("state").capitalized))
                    Text(row.timestamp).font(.caption)
                } }
            }
        }
        if loaded && rows.isEmpty { emptyMessage("No calls yet.") }
    }

    @ViewBuilder var threadContent: some View {
        if let person = people[peer] {
            VStack(spacing: 6) {
                Button { app.go("person", peer) } label: { InboxAvatar(person: person, size: 102) }.accessibilityLabel("View profile")
                HStack(spacing: 12) {
                    ForEach(CallPreviewMode.allCases) { mode in
                        Button { operate {
                            if await checkFriendship() { preview = mode }
                        } } label: {
                            Label(mode.rawValue, systemImage: mode.icon)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(.white.opacity(0.9), in: Capsule())
                        }
                    }
                }
                .grayscale(isFriend ? 0 : 1).opacity(isFriend ? 1 : 0.45).disabled(!isFriend || busy)
                if person.flag("allow_calls") {
                    Button("Start live voice call") { confirmCall = true }
                        .font(.subheadline).frame(minHeight: 44).disabled(!isFriend || busy)
                }
                if !isFriend {
                    Text("Follow each other to message or call.").font(.subheadline).foregroundStyle(.secondary)
                } else if !person.flag("allow_messages") || !person.flag("allow_calls") {
                    let unavailable = person.flag("allow_messages") ? "live voice calls" : person.flag("allow_calls") ? "private messages" : "private messages and live voice calls"
                    Text("This listener has turned off \(unavailable).")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }.frame(maxWidth: .infinity)
        }
        if rows.count >= take { Button("Load earlier messages") { take += 50; Task { await refresh() } } }
        ForEach(rows.reversed()) { row in
            let own = row.string("sender_id") == me
            HStack {
                if own { Spacer(minLength: 36) }
                VStack(alignment: own ? .trailing : .leading) {
                    if let room = row.roomID { Button("Open voice room invitation") { app.go("rooms.live",room) } }
                    else { Text(row.string("body")).font(ReactionPicker.textFont(for: row.string("body"))).textSelection(.enabled) }
                    Text(row.timestamp).font(.caption2).foregroundStyle(.secondary)
                }.padding(10).background(own ? Color(red: 0.42, green: 0.87, blue: 0.8) : Color.white.opacity(0.92),in: RoundedRectangle(cornerRadius: 15))
                if !own { Spacer(minLength: 36) }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            .onAppear { if row.id == rows.first?.id && row.id != lastRead { Task { do { try await mark(peer,row.id); lastRead = row.id } catch { self.error = error.localizedDescription } } } }
        }
        if loaded && rows.isEmpty && canMessage { emptyMessage("Start a conversation.") }
    }

    private var canMessage: Bool { isFriend && people[peer]?.flag("allow_messages") == true }

    var composer: some View {
        VStack {
            if showEmoji { ReactionPicker { edit(draft + $0) } }
            HStack {
                Button { showEmoji.toggle() } label: { NativeArt("chat",5).frame(width: 32,height: 32) }.accessibilityLabel("Choose an emoji")
                TextField("Message…",text: Binding(get: { draft }, set: edit)).font(ReactionPicker.textFont(for: draft))
                Button { operate { try await send() } } label: { NativeArt("chat",6).scaledToFit().frame(width: 64,height: 45) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send message")
            }.padding(.horizontal, 8).background(.white, in: Capsule())
        }.padding(.horizontal, 16).padding(.bottom, 4).grayscale(canMessage ? 0 : 1).disabled(busy || !canMessage)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 25)
            .frame(maxWidth: .infinity)
    }

    private func edit(_ value: String) {
        let body = String(value.prefix(2000))
        let id = UUID().uuidString.lowercased()
        do {
            try app.save(draftKey, ["id":id, "body":body])
            draft = body
            draftID = id
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func rpc(_ name: String, _ body: [String:Any] = [:]) async throws -> Any {
        try await app.api.rest("rpc/" + name, method: "POST", body: body)
    }

    private func isUnread(_ row: InboxRow) -> Bool {
        row.count("unread") > 0 || unreadPeers.contains(row.id)
    }

    @MainActor private func mark(_ peer: String, _ id: String, clear: Bool = false) async throws {
        let owner = me
        _ = try await rpc("mark_conversation",["p_peer":peer,"p_latest":id,"p_clear":clear])
        guard owner == me, app.signedIn else { return }
        var changes: [String: Any?] = [:]
        if unreadPeers.contains(peer) { changes["chat.unreadPeers"] = unreadPeers.filter { $0 != peer } }
        if clear && pinnedPeers.contains(peer) { changes["chat.pinnedPeers"] = pinnedPeers.filter { $0 != peer } }
        if !changes.isEmpty { try app.saveChanges(changes) }
    }

    private func markNotices(id: String? = nil) async throws {
        let filter = id.map { "&id=eq." + $0 } ?? (category ? "&kind=eq." + peer : "")
        _ = try await app.api.rest("account_notices?owner_id=eq.\(me)&read_at=is.null" + filter, method:"PATCH",body:["read_at": ISO8601DateFormatter().string(from: Date())])
    }

    private func markAll() async throws {
        for row in rows where isUnread(row) { try await mark(row.id,row.string("latest_id")) }
        try await markNotices()
    }

    private func checkFriendship() async -> Bool {
        let current = (try? await app.api.isChatFriend(peer)) ?? false
        guard !Task.isCancelled else { return false }
        isFriend = current
        return current
    }

    private func send() async throws {
        let result = try await rpc("send_message",["p_peer":peer,"p_id":draftID,"p_body":draft.trimmingCharacters(in:.whitespacesAndNewlines)])
        guard result as? String == draftID else { throw VoiceFailure("Message delivery could not be confirmed.") }
        edit(""); showEmoji = false
    }

    @MainActor private func operate(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation(); await refresh() } catch { self.error = error.localizedDescription }
        }
    }

    @MainActor private func refresh() async {
        guard !loading else { refreshPending = true; return }
        loading = true
        defer { loading = false }
        repeat {
            refreshPending = false
            do {
                var values: [[String:Any]]
                if inbox {
                    values = try await rpc("inbox_summary") as? [[String:Any]] ?? []
                    let follows = try await app.api.rows("follows?select=followed_id&follower_id=eq.\(me)&order=created_at.desc&limit=25")
                    following = follows.compactMap { $0["followed_id"] as? String }
                    notices = try await app.api.rows("account_notices?select=id&owner_id=eq.\(me)&read_at=is.null&limit=1000").count
                    people = try await inboxPeople(following + values.compactMap { $0["peer_id"] as? String },api: app.api)
                } else if thread {
                    guard UUID(uuidString: peer) != nil && peer != me else { throw VoiceFailure("Conversation unavailable.") }
                    _ = await checkFriendship()
                    people = try await inboxPeople([peer], api: app.api)
                    guard people[peer] != nil else { throw VoiceFailure("This profile is unavailable.") }
                    values = []
                    while values.count < take {
                        var body: [String:Any] = ["p_peer":peer,"p_take":50]
                        if let last = values.last { body["p_before"] = last["created_at"]; body["p_id"] = last["id"] }
                        let page = try await rpc("chat_history",body) as? [[String:Any]] ?? []
                        values += page
                        if page.count < 50 { break }
                    }
                } else if calls {
                    values = try await app.api.rows("voice_calls?select=id,caller_id,callee_id,state,created_at&or=(caller_id.eq.\(me),callee_id.eq.\(me))&order=created_at.desc&limit=100")
                    people = try await inboxPeople(values.compactMap { $0[$0["caller_id"] as? String == me ? "callee_id" : "caller_id"] as? String }, api: app.api)
                } else {
                    let filter = category && categories.contains(peer) ? "&kind=eq." + peer : ""
                    values = try await app.api.rows("account_notices?owner_id=eq.\(me)" + filter + "&order=created_at.desc,id.desc&limit=200")
                }
                try Task.checkCancellation()
                rows = values.map(InboxRow.init(values:)); loaded = true; error = ""
                if inbox { app.didRefreshRoot("messages") }
            } catch { if !Task.isCancelled { isFriend = false; self.error = error.localizedDescription } }
        } while refreshPending && !Task.isCancelled
    }
}


private struct ConversationSwipeRow<Card: View>: View {
    let id: String
    @Binding var revealed: String?
    let pinned, unread: Bool
    let open, pin, markRead, delete: () -> Void
    @ViewBuilder var card: () -> Card
    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trayWidth: CGFloat = 224
    private var isOpen: Bool { revealed == id }
    private var pinTitle: String { pinned ? "Unpin" : "Pin" }
    private var readTitle: String { unread ? "Mark read" : "Mark unread" }

    private func selectCard() {
        if revealed != nil { revealed = nil } else { open() }
    }

    var body: some View {
        let offset = max(-trayWidth, min(0, (isOpen ? -trayWidth : 0) + drag))
        ZStack(alignment: .trailing) {
            card()
                .contentShape(Rectangle())
                .onTapGesture(perform: selectCard)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { selectCard() }
                .accessibilityIdentifier("conversation-" + id)
                .accessibilityAction(named: Text(pinTitle)) { perform(pin) }
                .accessibilityAction(named: Text(readTitle)) { perform(markRead) }
                .accessibilityAction(named: Text("Delete")) { perform(delete) }
                .accessibilityHidden(isOpen)
                .offset(x: offset)
            if offset < 0 {
                Group {
                    if #available(iOS 26, *) {
                        GlassEffectContainer(spacing: 2) { actions }
                    } else { actions }
                }
                .frame(width: trayWidth - 8)
                .offset(x: trayWidth + offset)
                .accessibilityHidden(!isOpen)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .updating($drag) { value, state, _ in
                    if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
                }
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height), abs(dx) > 18 else { return }
                    if dx < -32 || value.predictedEndTranslation.width < -68 { revealed = id }
                    else if dx > 32 || value.predictedEndTranslation.width > 68 { revealed = nil }
                }
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
        .onDisappear { if isOpen { revealed = nil } }
    }

    private func perform(_ action: () -> Void) {
        revealed = nil
        action()
    }

    private var actions: some View {
        HStack(spacing: 6) {
            action(pinTitle, icon: pinned ? "pin.slash" : "pin", tint: .teal, ink: Color(red: 0.03, green: 0.31, blue: 0.32), handler: pin)
            action(readTitle, icon: unread ? "envelope.open" : "envelope.badge", tint: .blue, ink: Color(red: 0.10, green: 0.25, blue: 0.46), handler: markRead)
                .frame(minWidth: 84)
            action("Delete", icon: "trash", tint: .pink, ink: Color(red: 0.51, green: 0.15, blue: 0.24), handler: delete)
        }.padding(.vertical, 2)
    }

    private func action(_ title: String, icon: String, tint: Color, ink: Color, handler: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let label = VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium))
            Text(title).font(.caption2.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 54)
        .contentShape(shape)
        let illuminatedLabel = label.background {
            shape.fill(LinearGradient(stops: [
                .init(color: .white.opacity(0.68), location: 0),
                .init(color: tint.opacity(0.06), location: 0.40),
                .init(color: tint.opacity(0.20), location: 0.75),
                .init(color: .white.opacity(0.32), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return Button { perform(handler) } label: {
            if #available(iOS 26, *) {
                illuminatedLabel.glassEffect(.regular.tint(tint.opacity(0.07)).interactive(), in: shape)
            } else {
                illuminatedLabel.background(.ultraThinMaterial, in: shape)
            }
        }
        .buttonStyle(.plain)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.22), tint.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityLabel(title)
    }
}

private struct InboxWelcomeCard: View {
    let findPeople: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to your inbox")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 172, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button(action: findPeople) {
                Text("Find people")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.03, green: 0.17, blue: 0.24))
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .background(Color(red: 0.67, green: 0.97, blue: 0.89), in: Capsule())
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .background {
            ZStack(alignment: .trailing) {
                Color(red: 0.035, green: 0.17, blue: 0.33)
                if !typeSize.isAccessibilitySize {
                    GeometryReader { area in
                        let width = area.size.width * 0.55
                        nativeArtwork("signIn", "welcome")
                            .scaledToFill()
                            .frame(width: width, height: area.size.height, alignment: .top)
                            .offset(y: -width * 0.2)
                            .frame(width: width, height: area.size.height, alignment: .top)
                            .mask(LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.42)
                            ], startPoint: .leading, endPoint: .trailing))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }.accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private extension View {
    func messageCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 13))
    }
}

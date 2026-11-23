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
            if let url { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear } }
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
        .environment(\.colorScheme, .light)
        .preferredColorScheme(route.name == "messages" ? .dark : .light)
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
    @State private var clear: InboxRow?
    @State private var confirmCall = false
    @State private var showEmoji = false
    @State private var opened = ""
    @State private var take = 50
    @State private var lastRead = ""
    let categories = ["platform", "follow", "ranking"]
    let titles = ["platform": "Platform notifications", "follow": "New followers", "ranking": "Ranking updates"]
    var me: String { app.api.userID }
    var peer: String { route.id ?? "" }
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
                HStack { Text(error).font(.footnote); Spacer(); Button("Retry") { Task { await refresh() } } }
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
            ScrollViewReader { proxy in
            List {
                Group {
                    if inbox { inboxContent }
                    else if thread { threadContent }
                    else if calls { callContent }
                    else { noticeContent }
                }.listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)).listRowBackground(Color.clear)
            }.listStyle(.plain).scrollContentBackground(.hidden)
            .onChange(of: rows.first?.id) { newest in
                if thread, let newest, lastRead.isEmpty || rows.first?.string("sender_id") == me {
                    proxy.scrollTo(newest, anchor: .bottom)
                }
            }
            }
            if thread { composer }
        }
        .buttonStyle(.plain)
        .toolbar(.hidden, for: .navigationBar)
        .background { NativeArt(inbox ? "inbox" : thread ? "chat" : category ? "noticeDetail" : "notice",1).ignoresSafeArea().accessibilityHidden(true) }
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
        .onReceive(NotificationCenter.default.publisher(for: .inboxUpdated)) { _ in Task { await refresh() } }
        .overlay {
            if let selected = clear {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { clear = nil }
                    VStack(spacing: 16) {
                        Text("Clear this conversation?").font(.headline)
                        Text("Clear your copy through the selected message.").font(.subheadline)
                        Button("Clear my copy", role: .destructive) {
                            clear = nil
                            operate { try await mark(selected.id, selected.string("latest_id"), clear: true) }
                        }.frame(maxWidth: .infinity).padding(12).background(.white, in: Capsule())
                        Button("Cancel") { clear = nil }
                    }.padding(24).frame(maxWidth: .infinity).background(Color(red: 0.88, green: 0.98, blue: 0.96), in: RoundedRectangle(cornerRadius: 22))
                }
            }
        }
        .confirmationDialog("Start a voice call?", isPresented: $confirmCall) {
            Button("Call \(title)") { operate {
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
        ForEach(filtered) { row in
            Button { app.go("messages.thread",row.id) } label: {
                HStack { InboxAvatar(person: people[row.id]); VStack(alignment: .leading) {
                    Text(people[row.id]?.string("name") ?? "Listener").bold()
                    Text(row.roomID == nil ? row.string("body") : "Voice room invitation").lineLimit(1).foregroundStyle(.secondary)
                }; Spacer(); VStack(alignment: .trailing) { Text(row.timestamp).font(.caption2); badge(row.count("unread")) } }.messageCard()
            }.swipeActions { Button("Clear", role: .destructive) { clear = row } }
        }
        if loaded && filtered.isEmpty { emptyMessage(query.isEmpty ? "No conversations yet." : "No matching conversations.") }
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
                Button { confirmCall = true } label: { NativeArt("chat", 4).scaledToFit().frame(width: 74, height: 38) }
                    .disabled(!person.flag("allow_calls") || busy).accessibilityLabel("Voice call")
            }.frame(maxWidth: .infinity)
        }
        if rows.count >= take { Button("Load earlier messages") { take += 50; Task { await refresh() } } }
        ForEach(rows.reversed()) { row in
            let own = row.string("sender_id") == me
            HStack {
                if own { Spacer(minLength: 36) }
                VStack(alignment: own ? .trailing : .leading) {
                    if let room = row.roomID { Button("Open voice room invitation") { app.go("rooms.live",room) } }
                    else { Text(row.string("body")).textSelection(.enabled) }
                    Text(row.timestamp).font(.caption2).foregroundStyle(.secondary)
                }.padding(10).background(own ? Color(red: 0.42, green: 0.87, blue: 0.8) : Color.white.opacity(0.92),in: RoundedRectangle(cornerRadius: 15))
                if !own { Spacer(minLength: 36) }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            .onAppear { if row.id == rows.first?.id && row.id != lastRead { Task { do { try await mark(peer,row.id); lastRead = row.id } catch { self.error = error.localizedDescription } } } }
        }
        if loaded && rows.isEmpty { emptyMessage("Start a conversation.") }
    }

    var composer: some View {
        VStack {
            if showEmoji { HStack { ForEach(["🌙","✨","💚","😴","🌟","🫶"], id: \.self) { emoji in Button(emoji) { edit(draft + emoji) } } } }
            HStack {
                Button { showEmoji.toggle() } label: { NativeArt("chat",5).frame(width: 32,height: 32) }.accessibilityLabel("Choose an emoji")
                TextField("Message…",text: Binding(get: { draft }, set: edit))
                Button { operate { try await send() } } label: { NativeArt("chat",6).scaledToFit().frame(width: 64,height: 45) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send message")
            }.padding(.horizontal, 8).background(.white, in: Capsule())
        }.padding(.horizontal, 16).padding(.bottom, 4).disabled(busy || people[peer]?.flag("allow_messages") != true)
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

    private func mark(_ peer: String, _ id: String, clear: Bool = false) async throws {
        _ = try await rpc("mark_conversation",["p_peer":peer,"p_latest":id,"p_clear":clear])
    }

    private func markNotices(id: String? = nil) async throws {
        let filter = id.map { "&id=eq." + $0 } ?? (category ? "&kind=eq." + peer : "")
        _ = try await app.api.rest("account_notices?owner_id=eq.\(me)&read_at=is.null" + filter, method:"PATCH",body:["read_at": ISO8601DateFormatter().string(from: Date())])
    }

    private func markAll() async throws {
        for row in rows where row.count("unread") > 0 { try await mark(row.id,row.string("latest_id")) }
        try await markNotices()
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
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        } while refreshPending && !Task.isCancelled
    }
}


private extension View {
    func messageCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 13))
    }
}

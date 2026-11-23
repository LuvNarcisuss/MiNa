import SwiftUI
import AVKit

typealias CommunityRow = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func communityString(_ key: String) -> String { self[key] as? String ?? "" }
    func communitySeconds(_ key: String) -> Double { (self[key] as? NSNumber)?.doubleValue ?? 0 }
}

private func queryValue(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
}

private func timestamp(_ raw: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    return date?.formatted(date: .abbreviated, time: .shortened) ?? raw
}

func communityClock(_ seconds: Double) -> String {
    let value = Int(ceil(max(0, seconds)))
    return String(format: "%d:%02d", value / 60, value % 60)
}

struct CommunityScreen: View {
    let route: NativeRoute
    var body: some View {
        Group {
            if route.name.hasSuffix(".compose") || route.name == "dreams.record" {
                CommunityComposer(route: route)
            } else {
                CommunityListing(route: route)
            }
        }
        .id(route.name + (route.id ?? ""))
        .background { NativeArt(route.name == "feed" ? "home" : "dreams", 1).scaledToFill().ignoresSafeArea().accessibilityHidden(true) }
        .tint(Color(red: 0.02, green: 0.43, blue: 0.43))
    }
}

private let readings = [
    ("journal-moon-window","A window left open","For a moment, the whole street was quiet enough to hear the curtains move.","Across the courtyard, one window stayed lit. A spoon touched the side of a cup, then the light went out. The curtains lifted again. For once, there was nothing else I needed to do.","moon-seat"),
    ("journal-falling-star","One last star","I watched a small light cross the sky and forgot to make a wish.","Maybe it was a plane. Maybe someone in a window seat was watching the lights below, trying to guess which one was home. I pulled the blanket to my chin and let the thought drift on.","star-pillow")
]

private struct CommunityListing: View {
    @EnvironmentObject var app: MiNaAppModel
    @Environment(\.scenePhase) private var scenePhase
    let route: NativeRoute
    @State private var following = false
    @State private var likes = false
    @State private var query = ""
    @State private var limit = 30
    @State private var rows: [CommunityRow] = []
    @State private var comments: [CommunityRow] = []
    @State private var profiles: [String:CommunityRow] = [:]
    @State private var follows: Set<String> = []
    @State private var more = false
    @State private var loaded = false
    @State private var failure = ""
    @State private var message = ""
    @State private var revision = 0
    @State private var text = ""
    @State private var emoji = false
    @State private var commentID = UUID()
    @State private var sending = false
    @FocusState private var editingComment: Bool
    private var name: String { route.name }
    private var dream: Bool { name.hasPrefix("dreams") }
    private var mine: Bool { name.hasSuffix(".mine") }
    private var author: Bool { name.hasSuffix(".author") }
    private var detail: Bool { ["dreams.detail","feed.post"].contains(name) }
    private var activity: Bool { ["feed.likes","feed.activity"].contains(name) }
    private var title: String {
        if activity { return "Activity" }
        if detail { return dream ? "Dream" : "Post" }
        if mine { return dream ? "My Dreams" : "My Posts" }
        if author { return dream ? "Dreams" : "Posts" }
        return name == "feed.read" ? "Bedtime reading" : "Dream Space"
    }
    private var readIndices: [Int] {
        readings.indices.filter { i in
            if name == "feed.read" { return readings[i].0 == route.id }
            return name == "feed" && !following && (query.isEmpty || [readings[i].1,readings[i].2,"MiNa Journal"].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                controls
                if !failure.isEmpty {
                    Text(failure)
                    Button("Try again") { revision += 1 }
                } else if !loaded && name != "feed.read" { ProgressView("Loading…") }
                ForEach(rows.indices, id: \.self) { i in
                    let row = rows[i]
                    if activity { activityRow(row) }
                    else {
                        CommunityEntry(row: row, profile: profiles[row.communityString("owner_id")] ?? [:], followed: follows.contains(row.communityString("owner_id")), detail: detail, update: { revision += 1 }, issue: { message = $0 }, focus: { editingComment = true })
                            .id(row.communityString("id"))
                    }
                }
                ForEach(readIndices, id: \.self) { i in reading(i) }
                if (loaded || name == "feed.read") && rows.isEmpty && readIndices.isEmpty {
                    VStack(spacing: 8) {
                        NativeArt("search", 10).scaledToFit().frame(height: 86)
                        Text(detail || name == "feed.read" ? "Content unavailable" : activity ? (likes ? "No likes yet" : "No comments yet") : !query.isEmpty ? "No matches" : dream ? "No dreams yet" : "No posts yet").font(.headline)
                        if detail { Text("This entry was removed or is no longer available to you.") }
                        if following { Text("Entries from people you follow will appear here.") }
                    }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                if more { Button("Load more") { limit += 30 } }
                if detail && !dream && !rows.isEmpty { discussion }
            }.padding()
        }
        .navigationTitle(name == "feed" ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { revision += 1 }
        .overlay(alignment: .bottomTrailing) {
            if name == "feed" { Button { app.go("ai") } label: { Image(systemName: "moon.stars.fill").padding(13).background(.thinMaterial, in: Circle()) }.accessibilityLabel("Open AI Companion").padding() }
        }
        .onAppear { if name == "feed.likes" { likes = true } }
        .onChange(of: "\(following)|\(likes)|\(query)") { _ in rows = []; more = false; loaded = false; failure = "" }
        .onChange(of: scenePhase) { phase in if phase == .active { revision += 1 } }
        .task(id: "\(following)|\(likes)|\(query)|\(limit)|\(revision)") {
            guard name != "feed.read" else { return }
            do {
                if !query.isEmpty { try await Task.sleep(nanoseconds: 250_000_000) }
                while !Task.isCancelled {
                    do { try await load() } catch { if !Task.isCancelled { failure = error.localizedDescription } }
                    try await Task.sleep(nanoseconds: 45_000_000_000)
                }
            } catch {}
        }
        .alert("MiNa", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("OK") {} } message: { Text(message) }
    }
    @ViewBuilder private var controls: some View {
        if name == "feed" {
            HStack {
                Picker("Feed", selection: $following) { Text("Recommended").tag(false); Text("Following").tag(true) }.pickerStyle(.segmented)
                Button { app.go("feed.activity") } label: { NativeArt("feed",3).scaledToFit().frame(width: 24, height: 24).frame(width: 44,height: 44) }.accessibilityLabel("Post activity")
            }
            TextField("Search post captions", text: $query).textFieldStyle(.roundedBorder).onChange(of: query) { _ in limit = 30 }
            HStack { Text(following ? "Following" : "Night feed").font(.title.bold()); Spacer(); Button("＋ Post") { app.go("feed.compose") }.buttonStyle(.bordered) }
        } else {
            if mine {
                Button(dream ? "Record a dream" : "New post") { app.go(dream ? "dreams.compose" : "feed.compose") }
            }
            if activity {
                Picker("Activity", selection: $likes) { Text("Comments").tag(false); Text("Likes").tag(true) }.pickerStyle(.segmented)
            } else if dream && !mine && !author && !detail {
                Button { app.go("dreams.compose") } label: { NativeArt("dreams",15).scaledToFit() }.accessibilityLabel("Record a dream")
                HStack { Text("Dream Square").font(.title.bold()); Spacer(); Button(following ? "Following ✓" : "Following") { following.toggle() } }
            }
        }
    }

    @MainActor private func load() async throws {
        let api = app.api
        let me = api.userID
        var entries: [CommunityRow] = []
        var notes: [CommunityRow] = []
        var followed = Set<String>()
        if activity {
            let table = likes ? "entry_reactions" : "entry_comments"
            let fields = "entry_id,owner_id,created_at," + (likes ? "" : "body,") + "entries!inner(owner_id,caption,kind)"
            entries = try await api.rows(table + "?select=" + fields + "&entries.owner_id=eq." + me + "&owner_id=neq." + me + (likes ? "&kind=eq.like" : "") + "&order=created_at.desc")
        } else {
            let links = try await api.rows("follows?select=followed_id&follower_id=eq." + me)
            followed = Set(links.compactMap { $0["followed_id"] as? String })
            var path = "entry_feed?select=*&kind=eq." + (dream ? "dream" : "post")
            if mine || author { path += "&owner_id=eq." + (mine ? me : queryValue(route.id ?? "")) }
            else if detail { path += "&id=eq." + queryValue(route.id ?? "") }
            else if following { path += "&owner_id=in.(" + followed.joined(separator: ",") + ")" }
            if !query.isEmpty {
                let literal = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
                path += "&caption=ilike." + queryValue("%" + literal + "%")
            }
            if !following || !followed.isEmpty { entries = try await api.rows(path + "&order=created_at.desc,id.desc&limit=\(limit + 1)") }
            if detail && !dream, let id = entries.first?["id"] as? String {
                notes = try await api.rows("entry_comments?select=id,owner_id,body,created_at&entry_id=eq." + id + "&order=created_at.desc")
            }
        }
        let ids = Set((entries + notes).compactMap { $0["owner_id"] as? String })
        var people: [String:CommunityRow] = [:]
        if !ids.isEmpty {
            for profile in try await api.rows("profiles?select=id,name,avatar_path&id=in.(" + ids.joined(separator: ",") + ")") { people[profile.communityString("id")] = profile }
        }
        try Task.checkCancellation()
        rows = activity ? entries : Array(entries.prefix(limit))
        more = !activity && entries.count > limit
        comments = notes; profiles = people; follows = followed; failure = ""; loaded = true
    }

    private func activityRow(_ row: CommunityRow) -> some View {
        let source = row["entries"] as? CommunityRow ?? [:]
        return Button { app.go(source.communityString("kind") == "dream" ? "dreams.detail" : "feed.post", row.communityString("entry_id")) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(profiles[row.communityString("owner_id")]?.communityString("name") ?? "Night listener").bold()
                Text(timestamp(row.communityString("created_at"))).font(.caption)
                Text(likes ? "Liked your " + source.communityString("kind") : row.communityString("body"))
                Text(source.communityString("caption").isEmpty ? "View original ›" : source.communityString("caption") + " ›").font(.callout)
            }.communityCard()
        }.buttonStyle(.plain)
    }

    private func reading(_ i: Int) -> some View {
        let story = readings[i]
        return VStack(alignment: .leading, spacing: 10) {
            HStack { NativeArt("icon", 1).scaledToFill().frame(width: 42, height: 42).clipShape(Circle()); VStack(alignment: .leading) { Text("MiNa Journal").bold(); Text("Bedtime reading").font(.caption) } }
            Text(story.2)
            Button { if name != "feed.read" { app.go("feed.read", story.0) } } label: {
                ZStack(alignment: .bottomLeading) {
                    nativeArtwork("rooms-extra",story.4).scaledToFill()
                    Text(story.1).font(.headline).padding(9).background(.ultraThinMaterial, in: Capsule()).padding()
                }.frame(maxWidth: .infinity).frame(height: 148).clipped().cornerRadius(16)
            }.buttonStyle(.plain)
            if name == "feed.read" { Text(story.3) }
        }.communityCard()
    }

    @ViewBuilder private var discussion: some View {
        Text("Discussion").font(.title2.bold())
        if comments.isEmpty { Text("No comments yet.") }
        ForEach(comments.indices, id: \.self) { i in
            let note = comments[i]
            VStack(alignment: .leading) {
                CommunityOwner(row: note, profile: profiles[note.communityString("owner_id")] ?? [:])
                Text(note.communityString("body"))
            }.communityCard()
        }
        HStack {
            Button { emoji.toggle() } label: { NativeArt("post",10).scaledToFit().frame(width: 24,height: 24).frame(width: 44,height: 44) }.accessibilityLabel("Choose an emoji")
            TextField("Write a comment…", text: $text).focused($editingComment).onChange(of: text) { value in
                if value.count > 1000 { text = String(value.prefix(1000)) }
                commentID = UUID()
            }
            Button {
                guard !sending else { return }; sending = true
                Task {
                    defer { sending = false }
                    do {
                        _ = try await app.api.rest("entry_comments", method: "POST", body: ["id":commentID.uuidString,"entry_id":route.id ?? "","owner_id":app.api.userID,"body":text.trimmingCharacters(in: .whitespacesAndNewlines)], prefer: "resolution=ignore-duplicates")
                        text = ""; emoji = false; editingComment = false; revision += 1
                    } catch { message = error.localizedDescription }
                }
            } label: { NativeArt("post",11).scaledToFit().frame(width: 24,height: 24).frame(width: 44,height: 44) }.accessibilityLabel("Send comment").disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.disabled(sending).communityCard()
        if emoji { HStack { ForEach(["🌙","✨","💚","😴","🌟","🫶"], id: \.self) { item in Button(item) { text += item } } } }
    }
}

extension View {
    func communityCard() -> some View { padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20)) }
}

private struct CommunityOwner: View {
    @EnvironmentObject var app: MiNaAppModel
    let row: CommunityRow
    let profile: CommunityRow
    @State private var avatar: URL?
    var body: some View {
        let owner = row.communityString("owner_id")
        let name = profile.communityString("name").isEmpty ? "Night listener" : profile.communityString("name")
        Button { app.go(owner == app.api.userID ? "profile" : "person", owner == app.api.userID ? nil : owner) } label: {
            HStack {
                ZStack {
                    Circle().fill(Color.mint.opacity(0.2))
                    Text(String(name.prefix(1))).bold()
                    if let avatar { AsyncImage(url: avatar) { image in image.resizable().scaledToFill() } placeholder: { Color.clear } }
                }.frame(width: 40, height: 40).clipShape(Circle())
                VStack(alignment: .leading) { Text(name).bold(); Text(timestamp(row.communityString("created_at"))).font(.caption).foregroundStyle(.secondary) }
            }
        }.buttonStyle(.plain).task(id: profile.communityString("avatar_path")) {
            avatar = nil
            if let path = profile["avatar_path"] as? String, !path.isEmpty { avatar = try? await app.api.mediaURL(path) }
        }
    }
}

private struct CommunityEntry: View {
    @EnvironmentObject var app: MiNaAppModel
    let row: CommunityRow
    let profile: CommunityRow
    let followed: Bool
    let detail: Bool
    let update: () -> Void
    let issue: (String) -> Void
    let focus: () -> Void
    @State private var busy = false
    @State private var confirm = ""
    @State private var reporting = false
    @State private var reason = "Harassment"
    @State private var context = ""
    @State private var reportID = UUID()
    private var me: String { app.api.userID }
    private var id: String { row.communityString("id") }
    private var owner: String { row.communityString("owner_id") }
    private var kind: String { row.communityString("kind") }
    private var dream: Bool { kind == "dream" }
    private func open() { if !detail { app.go(dream ? "dreams.detail" : "feed.post", id) } }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await action(); update() } catch { issue(error.localizedDescription) }
        }
    }
    private func toggle(_ reaction: String, _ active: Bool) {
        run {
            if active { _ = try await app.api.rest("entry_reactions?entry_id=eq." + id + "&owner_id=eq." + me + "&kind=eq." + reaction, method: "DELETE") }
            else { _ = try await app.api.rest("entry_reactions", method: "POST", body: ["entry_id":id,"owner_id":me,"kind":reaction], prefer: "resolution=ignore-duplicates") }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CommunityOwner(row: row, profile: profile)
                Spacer()
                if owner != me {
                    Button(followed ? "Following" : "Follow") { run {
                        if followed { _ = try await app.api.rest("follows?follower_id=eq." + me + "&followed_id=eq." + owner, method: "DELETE") }
                        else { _ = try await app.api.rest("follows", method: "POST", body: ["follower_id":me,"followed_id":owner], prefer: "resolution=ignore-duplicates") }
                    } }.buttonStyle(.bordered)
                }
            }
            Button { open() } label: { Text(row.communityString("caption").isEmpty ? (dream ? "A voice from the night" : "A moment from my night") : row.communityString("caption")) }.buttonStyle(.plain)
            CommunityMedia(path: row.communityString("media_path"), duration: row.communitySeconds("duration"), voice: dream, remote: true)
            HStack {
                let liked = row["liked"] as? Bool ?? false
                let saved = row["saved"] as? Bool ?? false
                Button { toggle("like", liked) } label: { actionIcon("feed", liked ? 9 : 6, String(Int(row.communitySeconds("like_count")))) }.accessibilityLabel(liked ? "Remove like" : "Like")
                if dream { Button { toggle("save", saved) } label: { actionIcon("dreams",saved ? 9 : 8, saved ? "Saved" : "Save") } }
                else { Button { if detail { focus() } else { open() } } label: { actionIcon("feed",7,String(Int(row.communitySeconds("comment_count")))) }.accessibilityLabel("Open discussion") }
                Spacer()
                Menu {
                    if owner == me { Button("Delete " + kind, role: .destructive) { confirm = "Delete" } }
                    else {
                        Button("Report " + kind) { reporting = true }
                        Button("View author profile") { app.go("person",owner) }
                        Button("Block author", role: .destructive) { confirm = "Block" }
                    }
                } label: { NativeArt("feed",8).scaledToFit().frame(width: 22,height: 22).frame(width: 44,height: 44) }.accessibilityLabel("More options")
            }.disabled(busy)
        }.communityCard()
        .confirmationDialog(confirm == "Block" ? "Block this author?" : "Delete this " + kind + "?", isPresented: Binding(get: { !confirm.isEmpty }, set: { if !$0 { confirm = "" } }), titleVisibility: .visible) {
            if confirm == "Block" {
                Button("Block author", role: .destructive) { run { _ = try await app.api.rest("blocks", method: "POST", body: ["owner_id":me,"blocked_id":owner], prefer: "resolution=ignore-duplicates") } }
            } else {
                Button("Delete " + kind, role: .destructive) { run {
                    let result = try await app.api.rest("entries?id=eq." + id + "&owner_id=eq." + me + "&select=id", method: "DELETE", prefer: "return=representation")
                    guard let deleted = result as? [CommunityRow], !deleted.isEmpty else { throw MiNaIssue("This entry has already been removed.") }
                } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $reporting) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Report this " + kind).font(.title2.bold())
                Picker("Reason", selection: $reason) { ForEach(["Harassment","Sexual content","Harmful content","Privacy concern","Spam","Other"],id: \.self) { Text($0) } }
                TextField("Additional details (optional)", text: $context, axis: .vertical)
                Button("Submit report") {
                    run {
                        let key = reportID.uuidString
                        let body = ["id":key,"reporter_id":me,"target_id":id,"target_kind":kind,"reason":String((reason + (context.isEmpty ? "" : " · " + context)).prefix(1000))]
                        let result = try await app.api.rest("reports?select=id",method: "POST",body: body,prefer: "return=representation,resolution=ignore-duplicates")
                        var receipt = (result as? [CommunityRow])?.first?["id"] as? String
                        if receipt == nil { receipt = try await app.api.rows("reports?select=id&reporter_id=eq." + me + "&id=eq." + key).first?["id"] as? String }
                        guard let receipt else { throw MiNaIssue("Your report could not be confirmed. Please retry.") }
                        reporting = false; reportID = UUID(); context = ""; issue("Report received · " + receipt.prefix(8))
                    }
                }.buttonStyle(.borderedProminent)
                Button("Cancel") { reporting = false }
            }.padding().disabled(busy).presentationDetents([.medium])
        }
    }
    private func actionIcon(_ group: String, _ index: Int, _ text: String) -> some View {
        HStack { NativeArt(group,index).scaledToFit().frame(width: 20,height: 20); Text(text) }.frame(minWidth: 44,minHeight: 44)
    }
}

import SwiftUI
import AVKit

typealias CommunityRow = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func communityString(_ key: String) -> String { self[key] as? String ?? "" }
    func communitySeconds(_ key: String) -> Double { (self[key] as? NSNumber)?.doubleValue ?? 0 }
    fileprivate var communityListID: String {
        if let id = self["id"] as? String { return id }
        return communityString("entry_id") + "/" + communityString("owner_id")
    }
}

private func queryValue(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
}

func communityTimestamp(_ raw: String) -> String {
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
        .pageBackground(route.name == "feed" ? "home" : route.name == "feed.post" ? "post" : "dreams")
        .tint(Color(red: 0.02, green: 0.43, blue: 0.43))
    }
}

private var readings: [JournalStory] { CloudInterface.library?.stories ?? [] }

private enum CommunityItem: Identifiable {
    case entry(CommunityRow)
    case reading(JournalStory)

    var id: String {
        switch self {
        case .entry(let row): return "entry/" + row.communityListID
        case .reading(let story): return "reading/" + story.id
        }
    }
}

private struct CommunityReportTarget: Identifiable {
    let id: String
    let kind: String
    let owner: String
}

private struct DiscussionNote: Identifiable {
    let id: String
    let row: CommunityRow
    let parentID: String
    let parentName: String?
}

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
    @State private var revision = 0
    @State private var loadRequest = DiscoveryLoad()
    @State private var feedOrder = DiscoveryOrder()
    @State private var text = ""
    @State private var emoji = false
    @State private var commentID = UUID()
    @State private var replyID: String?
    @State private var replyName = ""
    @State private var sending = false
    @State private var postOptions = false
    @State private var reportTarget: CommunityReportTarget?
    @State private var leavingReportedDetail = false
    @State private var loadedSafetyRevision = -1
    private var visibleRows: [CommunityRow] { loadedSafetyRevision == app.safetyRevision ? rows : [] }
    @FocusState private var editingComment: Bool
    private var name: String { route.name }
    private var dream: Bool { name.hasPrefix("dreams") }
    private var mine: Bool { name.hasSuffix(".mine") }
    private var author: Bool { name.hasSuffix(".author") }
    private var detail: Bool { ["dreams.detail","feed.post"].contains(name) }
    private var activity: Bool { ["feed.likes","feed.activity"].contains(name) }
    private var loadKey: String {
        "\(following)|\(likes)|\(query)|\(limit)|\(revision)|\(app.safetyRevision)"
    }
    private var title: String {
        if activity { return "Activity" }
        if detail { return dream ? "Dream" : "Details" }
        if mine { return dream ? "My Dreams" : "My Posts" }
        if author { return dream ? "Dreams" : "Posts" }
        return name == "feed.read" ? "Bedtime reading" : "Dream Space"
    }
    private var listedItems: [CommunityItem] {
        let stories = readings.filter { story in
            if name == "feed.read" { return story.id == route.id }
            return name == "feed" && !following && (query.isEmpty || [story.title,story.summary,"MiNa Journal"].contains { $0.localizedCaseInsensitiveContains(query) })
        }
        let items = visibleRows.map(CommunityItem.entry) + stories.map(CommunityItem.reading)
        return name == "feed" ? feedOrder.arranged(items) : items
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if name == "feed.post", let row = visibleRows.first { entry(row) }
                LazyVStack(alignment: .leading, spacing: 14) {
                    controls
                    if !failure.isEmpty {
                        Button("Try again") { revision += 1 }
                    } else if (!loaded || loadedSafetyRevision != app.safetyRevision) && name != "feed.read" { ProgressView("Loading…") }
                    if name != "feed.post" {
                        ForEach(listedItems) { item in
                            switch item {
                            case .entry(let row):
                                if activity { activityRow(row) } else { entry(row) }
                            case .reading(let story):
                                reading(story)
                            }
                        }
                    }
                    if ((loaded && loadedSafetyRevision == app.safetyRevision) || name == "feed.read") && listedItems.isEmpty {
                        VStack(spacing: 8) {
                            NativeArt(activity && likes ? "likes" : "activity", activity && likes ? 5 : 4).scaledToFit().frame(width: 112,height: 108).accessibilityHidden(true)
                            Text(detail || name == "feed.read" ? "Content unavailable" : activity ? (likes ? "No likes yet" : "No comments yet") : !query.isEmpty ? "No matches" : dream ? "No dreams yet" : "No posts yet").font(.headline)
                            if detail { Text("This entry was removed or is no longer available to you.") }
                            if following { Text("Entries from people you follow will appear here.") }
                        }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, activity ? 145 : 50).multilineTextAlignment(.center)
                    }
                    if more { Button("Load more") { limit += 30 } }
                    if detail && !dream && !visibleRows.isEmpty { discussion }
                }
            }.padding(.horizontal, 20).padding(.vertical, 4)
        }
        .navigationTitle(name == "feed" ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(name == "feed" || name == "feed.post" ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if mine || (dream && !author && !detail) {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { app.go(dream ? "dreams.compose" : "feed.compose") } label: {
                        Text(dream && mine ? "Record" : "Post").communityPill()
                    }.accessibilityLabel(dream ? "Record a dream" : "New post")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if name == "feed.post" {
                HStack {
                    Button { app.back() } label: { NativeArt("post", 3).scaledToFit().frame(width: 24).frame(width: 44, height: 44) }
                        .accessibilityLabel("Back")
                    Spacer()
                    Text(title).font(.headline)
                    Spacer()
                    Button { postOptions = true } label: { NativeArt("post", 2).scaledToFit().frame(width: 24).frame(width: 44, height: 44) }
                        .accessibilityLabel("More options").disabled(visibleRows.isEmpty)
                }.padding(.horizontal, 10).foregroundStyle(.primary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if name == "feed.post" && !visibleRows.isEmpty {
                VStack(spacing: 5) { commentInput }.padding(.horizontal, 20).padding(.bottom, 4)
            }
        }
        .refreshable { await reload(pull: true) }
        .overlay(alignment: .bottomTrailing) {
            if name == "feed" {
                Button { app.go("ai") } label: {
                    nativeArtwork("feed", "companion").scaledToFit().frame(width: 56, height: 56)
                }.buttonStyle(.plain).accessibilityLabel("Open AI Companion")
                    .padding(.trailing, 20).padding(.bottom, 20)
            }
        }
        .minaAlert(failure)
        .onAppear { if name == "feed.likes" { likes = true } }
        .onChange(of: "\(following)|\(likes)|\(query)") { _ in rows = []; more = false; loaded = false; failure = ""; feedOrder = DiscoveryOrder() }
        .onChange(of: scenePhase) { phase in if phase == .active { revision += 1 } }
        .task(id: loadKey) {
            guard name != "feed.read" else { return }
            do {
                if !query.isEmpty { try await Task.sleep(nanoseconds: 250_000_000) }
                while !Task.isCancelled {
                    await reload()
                    try await Task.sleep(nanoseconds: 45_000_000_000)
                }
            } catch {}
        }
        .sheet(item: $reportTarget, onDismiss: {
            if leavingReportedDetail && app.route == route { app.back() }
            leavingReportedDetail = false
        }) { target in
            ReportForm(targetID: target.id, kind: target.kind) { reportAccepted(target) }
        }
    }
    private func entry(_ row: CommunityRow) -> some View {
        let owner = row.communityString("owner_id")
        return CommunityEntry(row: row, profile: profiles[owner] ?? [:], followed: follows.contains(owner),
                              detail: detail, mine: mine, detailOptions: $postOptions,
                              update: { revision += 1 }, issue: { AppAlerts.shared.show($0) },
                              report: openReport, removed: { removeEntry(row.communityString("id")) })
            .id(row.communityString("id"))
    }

    @ViewBuilder private var controls: some View {
        if name == "feed" {
            HStack(spacing:5) {
                ForEach([false,true], id: \.self) { selected in
                    Button { following = selected } label: {
                        VStack(spacing: 3) {
                            Text(selected ? "Following" : "Recommended").font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                            Capsule().fill(selected == following ? Color.mint : .clear).frame(height: 3)
                        }
                    }.frame(minHeight: 44).foregroundStyle(.white.opacity(selected == following ? 1 : 0.72))
                    .accessibilityAddTraits(following == selected ? .isSelected : [])
                }
                Spacer()
                Button { app.go("feed.compose") } label: { NativeArt("feed",15).scaledToFit().frame(width: 31,height: 31).frame(minWidth: 44,minHeight: 44) }.accessibilityLabel("New post")
                Button { app.go("feed.activity") } label: { NativeArt("feed",3).scaledToFit().frame(width: 34,height: 34).frame(minWidth: 44,minHeight: 44) }.accessibilityLabel("Post activity")
            }
            HStack {
                NativeArt("feed",2).scaledToFit().frame(width: 21,height: 21)
                TextField("", text: $query, prompt: Text("Search post captions").foregroundColor(.white.opacity(0.85))).foregroundStyle(.white)
                    .accessibilityLabel("Search post captions").onChange(of: query) { _ in limit = 30 }
            }.padding(.horizontal,14).frame(minHeight: 44).background(.white.opacity(0.24),in: Capsule())
        } else {
            if activity {
                HStack(spacing: 0) {
                    ForEach([false,true],id: \.self) { tab in
                        Button { likes = tab } label: {
                            Text(tab ? "Likes" : "Comments").font(.subheadline.weight(.medium)).foregroundStyle(tab == likes ? Color.teal : Color.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical,8).background(tab == likes ? Color.white : .clear,in: Capsule())
                        }.frame(minHeight:44).accessibilityAddTraits(likes == tab ? .isSelected : [])
                    }
                }.padding(.horizontal,3).background(.white.opacity(0.55),in: Capsule())
            } else if dream && !mine && !author && !detail {
                Button { app.go("dreams.compose") } label: { NativeArt("dreams",15).scaledToFit() }.accessibilityLabel("Record a dream")
                HStack { NativeArt("dreams",16).scaledToFit().frame(width:104,height:20).accessibilityLabel("Dream Square"); Spacer(); Button { following.toggle() } label: { Text(following ? "Following ✓" : "Following").communityPill() }.frame(minHeight:44) }
            }
        }
    }

    @MainActor private func reload(pull: Bool = false) async {
        let key = loadKey
        guard name != "feed.read", let request = loadRequest.begin(scope: key, pull: pull) else { return }
        defer { loadRequest.finish(request) }
        do {
            try await load(key, request: request, shuffle: pull && name == "feed")
        } catch {
            if loadRequest.current == request && key == loadKey && !Task.isCancelled { failure = error.localizedDescription }
        }
    }

    @MainActor private func load(_ key: String, request: UUID, shuffle: Bool) async throws {
        let api = app.api
        let me = api.userID
        var entries: [CommunityRow] = []
        var notes: [CommunityRow] = []
        var followed = Set<String>()
        if activity {
            let table = likes ? "entry_reactions" : "entry_comments"
            let fields = "entry_id,owner_id,created_at," + (likes ? "" : "id,body,") + "entries!inner(owner_id,caption,kind)"
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
                let path = "entry_comments?select=id,owner_id,parent_id,body,created_at&entry_id=eq." + id + "&order=created_at.desc,id.desc&limit=100"
                var cursor = ""
                while true {
                    try Task.checkCancellation()
                    let page = try await api.rows(path + cursor)
                    notes.append(contentsOf: page)
                    guard page.count == 100, let last = page.last else { break }
                    let date = queryValue(last.communityString("created_at"))
                    let note = last.communityString("id")
                    cursor = "&or=(created_at.lt." + date + ",and(created_at.eq." + date + ",id.lt." + note + "))"
                }
            }
        }
        let ids = Array(Set((entries + notes).compactMap { $0["owner_id"] as? String }))
        var people: [String:CommunityRow] = [:]
        for offset in stride(from: 0, to: ids.count, by: 60) {
            try Task.checkCancellation()
            let batch = ids[offset..<min(offset + 60, ids.count)].joined(separator: ",")
            for profile in try await api.rows("profiles?select=id,name,avatar_path,country&id=in.(" + batch + ")") {
                people[profile.communityString("id")] = profile
            }
        }
        try Task.checkCancellation()
        guard loadRequest.current == request, key == loadKey, me == api.userID else { return }
        let previousFirst = shuffle ? listedItems.first?.id : nil
        loadedSafetyRevision = app.safetyRevision
        rows = activity ? entries : Array(entries.prefix(limit))
        if shuffle { feedOrder.shuffle(listedItems, replacing: previousFirst) }
        more = !activity && entries.count > limit
        comments = notes; profiles = people; follows = followed; failure = ""; loaded = true
        if name == "feed" { app.didRefreshRoot("feed") }
    }

    private func activityRow(_ row: CommunityRow) -> some View {
        let source = row["entries"] as? CommunityRow ?? [:]
        return VStack(alignment: .leading, spacing: 10) {
            CommunityOwner(row: row,profile: profiles[row.communityString("owner_id")] ?? [:])
            Text(likes ? "Liked your " + source.communityString("kind") : row.communityString("body"))
                .font(ReactionPicker.textFont(for: row.communityString("body"), style: .subheadline))
            Button { app.go(source.communityString("kind") == "dream" ? "dreams.detail" : "feed.post", row.communityString("entry_id")) } label: {
                HStack {
                    Text(source.communityString("caption").isEmpty ? "View original" : source.communityString("caption"))
                        .lineLimit(3).multilineTextAlignment(.leading)
                    Spacer()
                    NativeArt("activity",3).scaledToFit().frame(width:38,height:17)
                }.font(.footnote).padding(10).frame(minHeight:74).background(Color.gray.opacity(0.1),in: RoundedRectangle(cornerRadius:10))
            }.buttonStyle(.plain).accessibilityLabel("View original")
        }.communityCard()
    }

    private func reading(_ story: JournalStory) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack { NativeArt("icon", 1).scaledToFill().frame(width: 42, height: 42).clipShape(Circle()); VStack(alignment: .leading) { Text("MiNa Journal").bold(); Text("Bedtime reading").font(.caption) } }
            Text(story.summary)
            Button { if name != "feed.read" { app.go("feed.read", story.id) } } label: {
                Color.clear.frame(maxWidth: .infinity).frame(height: 220)
                    .overlay { nativeArtwork("rooms-extra",story.cover).scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(alignment:.bottomLeading) {
                        Text(story.title).font(.headline).padding(9).background(.ultraThinMaterial,in:Capsule()).padding()
                    }
                    .contentShape(RoundedRectangle(cornerRadius:16))
            }.buttonStyle(.plain)
                .accessibilityIdentifier("journal-reading-" + story.id)
            if name == "feed.read" { Text(story.body) }
        }.padding(.vertical,8).overlay(alignment: .bottom) { Divider() }
    }

    private func openReport(_ target: CommunityReportTarget) {
        guard !target.id.isEmpty, !target.owner.isEmpty, target.owner != app.api.userID else { return }
        editingComment = false
        reportTarget = target
    }

    private func reportAccepted(_ target: CommunityReportTarget) {
        if target.kind == "comment" {
            comments.removeAll { $0.communityString("id") == target.id }
            if replyID == target.id { cancelReply() }
        } else if target.kind == "post" || target.kind == "dream" {
            CommunityPlayer.pauseActive()
            rows.removeAll { $0.communityString("id") == target.id }
            leavingReportedDetail = detail && route.id == target.id
        }
        app.safetyChanged()
    }

    private func removeEntry(_ id: String) {
        CommunityPlayer.pauseActive()
        rows.removeAll { $0.communityString("id") == id }
        app.safetyChanged()
        if detail && app.route == route { app.back() }
    }

    private func memberName(_ owner: String) -> String {
        let name = profiles[owner]?.communityString("name") ?? ""
        return name.isEmpty ? "Night listener" : name
    }

    private var thread: [DiscussionNote] {
        var authors: [String: String] = [:]
        for row in comments { authors[row.communityString("id")] = row.communityString("owner_id") }
        var roots: [CommunityRow] = []
        var children: [String: [CommunityRow]] = [:]
        for row in comments {
            let parent = row.communityString("parent_id")
            if authors[parent] == nil { roots.append(row) }
            else { children[parent, default: []].append(row) }
        }
        // The query returns newest first. Keep recent roots first and replies in conversation order.
        var pending = Array(roots.reversed())
        var result: [DiscussionNote] = []
        while let row = pending.popLast() {
            let id = row.communityString("id")
            let parent = row.communityString("parent_id")
            result.append(DiscussionNote(id: id, row: row, parentID: parent, parentName: authors[parent].map(memberName)))
            if let replies = children[id] { pending.append(contentsOf: replies) }
        }
        return result
    }

    @ViewBuilder private var discussion: some View {
        NativeArt("post", 6).scaledToFit().frame(width: 82, height: 15).padding(.top, 16).accessibilityLabel("Discussion")
        if comments.isEmpty { Text("No comments yet.") }
        ForEach(thread) { note in
            let owner = note.row.communityString("owner_id")
            CommunityComment(note: note, profile: profiles[owner] ?? [:], name: memberName(owner), sending: sending,
                             reply: {
                                 if replyID != note.id { commentID = UUID() }
                                 replyID = note.id
                                 replyName = memberName(owner)
                                 editingComment = true
                             }, report: openReport, issue: { AppAlerts.shared.show($0) })
        }
    }

    private func cancelReply() {
        replyID = nil
        replyName = ""
        commentID = UUID()
    }

    private func sendComment() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, !body.isEmpty, let entry = route.id else { return }
        let id = commentID.uuidString.lowercased()
        let owner = app.api.userID
        let parent = replyID
        var record = ["id": id, "entry_id": entry, "owner_id": owner, "body": body]
        record["parent_id"] = parent
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let result = try await app.api.rest("entry_comments?select=id", method: "POST", body: record,
                                                    prefer: "return=representation,resolution=ignore-duplicates")
                if (result as? [CommunityRow])?.first?.communityString("id") != id {
                    let saved = try await app.api.rows("entry_comments?select=body,parent_id&id=eq." + id + "&entry_id=eq." + entry + "&owner_id=eq." + owner)
                    guard let comment = saved.first, comment.communityString("body") == body,
                          (comment["parent_id"] as? String) == parent else {
                        throw MiNaIssue("Your comment could not be confirmed. Please try again.")
                    }
                }
                text = ""
                cancelReply()
                emoji = false
                editingComment = false
                revision += 1
            } catch { AppAlerts.shared.show(error.localizedDescription) }
        }
    }

    @ViewBuilder private var commentInput: some View {
        if replyID != nil {
            HStack {
                Text("Replying to " + replyName).font(.footnote.weight(.medium))
                Spacer()
                Button("Cancel reply") { cancelReply() }.font(.footnote).frame(minHeight: 44)
            }.padding(.horizontal, 12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .disabled(sending)
        }
        HStack {
            Button { emoji.toggle() } label: { NativeArt("post",10).scaledToFit().frame(width: 36,height: 36).frame(width: 44,height: 44) }.accessibilityLabel("Choose an emoji")
            TextField(replyID == nil ? "Write a comment…" : "Write a reply…", text: $text).font(ReactionPicker.textFont(for: text)).focused($editingComment).onChange(of: text) { value in
                if value.count > 1000 { text = String(value.prefix(1000)) }
                commentID = UUID()
            }
            Button(action: sendComment) { NativeArt("post",11).scaledToFit().frame(width: 68,height: 47) }
                .accessibilityLabel(replyID == nil ? "Send comment" : "Send reply")
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.disabled(sending).padding(.horizontal,4).padding(.vertical,2).background(.white,in: Capsule())
        if emoji { ReactionPicker { text += $0 }.disabled(sending) }
    }
}

let communityGradient = LinearGradient(colors: [Color(red:0.02,green:0.91,blue:0.61), Color(red:0.40,green:0.66,blue:1.0)], startPoint:.leading,endPoint:.trailing)

extension View {
    func communityPill() -> some View {
        font(.subheadline.weight(.semibold)).foregroundStyle(Color.black.opacity(0.8))
            .padding(.horizontal,15).padding(.vertical,5).background(communityGradient,in: Capsule())
    }
    func communityPrimary() -> some View {
        font(.headline).foregroundStyle(Color(red:0.02,green:0.22,blue:0.22))
            .frame(maxWidth:.infinity).frame(minHeight:58).background(communityGradient,in: Capsule())
    }
    func communityCard() -> some View { padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20)) }
}

private struct CommunityOwner: View {
    @EnvironmentObject var app: MiNaAppModel
    let row: CommunityRow
    let profile: CommunityRow
    var avatarSize: CGFloat = 40
    @State private var avatar: URL?
    var body: some View {
        let owner = row.communityString("owner_id")
        let name = profile.communityString("name").isEmpty ? "Night listener" : profile.communityString("name")
        Button { app.go(owner == app.api.userID ? "profile" : "person", owner == app.api.userID ? nil : owner) } label: {
            HStack {
                ZStack {
                    Circle().fill(Color.mint.opacity(0.2))
                    Text(String(name.prefix(1))).bold()
                    if let avatar { CloudPortraitImage(url: avatar) { image in image.resizable().scaledToFill() } placeholder: { Color.clear } }
                }.frame(width: avatarSize, height: avatarSize).clipShape(Circle())
                if avatarSize == 24 {
                    Text(name).font(.subheadline.weight(.medium))
                    Text(communityTimestamp(row.communityString("created_at"))).font(.caption2).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.headline)
                        if avatarSize == 62 && !profile.communityString("country").isEmpty {
                            Text(profile.communityString("country")).font(.caption).foregroundStyle(.teal)
                                .padding(.horizontal, 6).background(.mint.opacity(0.2), in: Capsule())
                        } else {
                            Text(communityTimestamp(row.communityString("created_at"))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.buttonStyle(.plain).task(id: profile.communityString("avatar_path")) {
            avatar = nil
            if let path = profile["avatar_path"] as? String, !path.isEmpty {
                let url = try? await app.api.mediaURL(path)
                if !Task.isCancelled { avatar = url }
            }
        }
    }
}

private struct CommunityComment: View {
    @EnvironmentObject var app: MiNaAppModel
    let note: DiscussionNote
    let profile: CommunityRow
    let name: String
    let sending: Bool
    let reply: () -> Void
    let report: (CommunityReportTarget) -> Void
    let issue: (String) -> Void
    @State private var confirmingBlock = false
    @State private var blocking = false
    private var owner: String { note.row.communityString("owner_id") }
    private var canModerate: Bool { !owner.isEmpty && !app.api.userID.isEmpty && owner != app.api.userID }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            CommunityOwner(row: note.row, profile: profile, avatarSize: 24)
                .frame(minHeight: 44)
            if !note.parentID.isEmpty {
                Text(note.parentName.map { "Reply to " + $0 } ?? "Reply to an unavailable comment")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(note.row.communityString("body")).font(ReactionPicker.textFont(for: note.row.communityString("body"), style: .subheadline))
            HStack(spacing: 6) {
                Button("Reply", action: reply).font(.caption.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    .disabled(sending || blocking)
                if canModerate {
                    PopupMenu("Comment options") {
                        PopupAction("Report comment", "flag") { report(CommunityReportTarget(id: note.id, kind: "comment", owner: owner)) }
                        if !profile.isEmpty {
                            PopupAction("Report author", "person.crop.circle.badge.exclamationmark") { report(CommunityReportTarget(id: owner, kind: "profile", owner: owner)) }
                        }
                        PopupAction("Block author", "person.crop.circle.badge.minus", role: .destructive) { confirmingBlock = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.accessibilityLabel("More comment options").disabled(blocking || sending)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, note.parentID.isEmpty ? 0 : 24)
        .popupDialog("Block " + name + "?", isPresented: $confirmingBlock) {
            PopupAction("Block author", "person.crop.circle.badge.minus", role: .destructive) {
                guard canModerate, !blocking else { return }
                blocking = true
                Task {
                    defer { blocking = false }
                    do { try await app.blockMember(owner, name: name) }
                    catch { issue(error.localizedDescription) }
                }
            }
        }
    }
}

private struct CommunityEntry: View {
    @EnvironmentObject var app: MiNaAppModel
    let row: CommunityRow
    let profile: CommunityRow
    let followed: Bool
    let detail: Bool
    let mine: Bool
    @Binding var detailOptions: Bool
    let update: () -> Void
    let issue: (String) -> Void
    let report: (CommunityReportTarget) -> Void
    let removed: () -> Void
    @State private var busy = false
    @State private var confirm = ""
    @State private var options = false
    private var me: String { app.api.userID }
    private var id: String { row.communityString("id") }
    private var owner: String { row.communityString("owner_id") }
    private var kind: String { row.communityString("kind") }
    private var dream: Bool { kind == "dream" }
    private var canModerate: Bool { !me.isEmpty && !owner.isEmpty && owner != me }
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
    private var caption: String {
        row.communityString("caption").isEmpty ? (dream ? "A voice from the night" : "A moment from my night") : row.communityString("caption")
    }
    private var entryMedia: some View {
        CommunityMedia(path: row.communityString("media_path"), duration: row.communitySeconds("duration"),
                       voice: dream, caption: postDetail ? caption : nil, liked: liked,
                       onLike: postDetail ? { toggle("like", liked) } : nil,
                       openPost: detail || dream ? nil : { open() })
    }
    private var postDetail: Bool { detail && !dream }
    private var liked: Bool { row["liked"] as? Bool ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if detail && !dream { entryMedia }
            HStack {
                CommunityOwner(row: row, profile: profile, avatarSize: postDetail ? 62 : 40)
                Spacer()
                if canModerate && !profile.isEmpty {
                    Button { run {
                        if followed { _ = try await app.api.rest("follows?follower_id=eq." + me + "&followed_id=eq." + owner, method: "DELETE") }
                        else { _ = try await app.api.rest("follows", method: "POST", body: ["follower_id":me,"followed_id":owner], prefer: "resolution=ignore-duplicates") }
                    } } label: {
                        NativeArt("feed", followed ? 5 : 4).scaledToFit().frame(width: 73, height: 34)
                    }.accessibilityLabel(followed ? "Following" : "Follow").frame(minHeight: 44)
                } else if mine && owner == me {
                    Button { confirm = "Delete" } label: { Text("Delete").communityPill() }.frame(minHeight:44)
                }
            }
            if !postDetail {
                Button { open() } label: { Text(caption).font(.body).multilineTextAlignment(.leading) }.buttonStyle(.plain)
                    .accessibilityIdentifier("community-entry-" + id)
                entryMedia
                HStack {
                    let saved = row["saved"] as? Bool ?? false
                    Button { toggle("like", liked) } label: { actionIcon("feed", liked ? 9 : 6, String(Int(row.communitySeconds("like_count")))) }.accessibilityLabel(liked ? "Remove like" : "Like")
                    if dream { Button { toggle("save", saved) } label: { actionIcon("dreams",saved ? 9 : 8, saved ? "Saved" : "Save") } }
                    else { Button { open() } label: { actionIcon("feed",7,String(Int(row.communitySeconds("comment_count")))) }.accessibilityLabel("Open discussion") }
                    Spacer()
                    Button { options = true } label: { NativeArt("feed",8).scaledToFit().frame(width: 22,height: 22).frame(width: 44,height: 44) }.accessibilityLabel("More options")
                }.disabled(busy)
            }
        }.padding(.vertical, postDetail ? 0 : 6)
        .overlay(alignment: .bottom) { if !postDetail { Divider() } }
        .popupDialog(dream ? "Dream options" : "Post options", isPresented: postDetail ? $detailOptions : $options) {
            if owner == me { PopupAction("Delete " + kind, "trash", role: .destructive) { confirm = "Delete" } }
            else if canModerate {
                PopupAction("Report " + kind, "flag") { report(CommunityReportTarget(id: id, kind: kind, owner: owner)) }
                if !profile.isEmpty {
                    PopupAction("Report author", "person.crop.circle.badge.exclamationmark") { report(CommunityReportTarget(id: owner, kind: "profile", owner: owner)) }
                    PopupAction("View author profile", "person.crop.circle") { app.go("person",owner) }
                }
                PopupAction("Block author", "person.crop.circle.badge.minus", role: .destructive) { confirm = "Block" }
            }
        }
        .popupDialog(confirm == "Block" ? "Block this author?" : "Delete this " + kind + "?", isPresented: Binding(get: { !confirm.isEmpty }, set: { if !$0 { confirm = "" } })) {
            if confirm == "Block" {
                PopupAction("Block author", "person.crop.circle.badge.minus", role: .destructive) {
                    guard canModerate else { return }
                    run {
                        let name = profile.communityString("name")
                        try await app.blockMember(owner, name: name.isEmpty ? "Night listener" : name)
                    }
                }
            } else {
                PopupAction("Delete " + kind, "trash", role: .destructive) { run {
                    guard owner == me, !me.isEmpty else { throw MiNaIssue("Only the author can delete this entry.") }
                    try await app.api.deleteEntry(id)
                    removed()
                } }
            }
        }
    }
    private func actionIcon(_ group: String, _ index: Int, _ text: String) -> some View {
        HStack { NativeArt(group,index).scaledToFit().frame(width: 20,height: 20); Text(text) }.frame(minWidth: 44,minHeight: 44)
    }
}

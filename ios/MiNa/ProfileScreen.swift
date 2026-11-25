import SwiftUI

private typealias ProfileRecord = [String: Any]

struct ProfileScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var profile: ProfileRecord = [:]
    @Environment(\.scenePhase) private var phase
    @State private var isFriend = false
    @State private var edges: [ProfileRecord] = []
    @State private var people: [ProfileRecord] = []
    @State private var savedFields: [String:String] = [:]
    @State private var savedBirthday = ""
    @State private var editingOwner = ""
    @State private var avatarID: String?
    @State private var avatarData: Data?
    @State private var avatarImage: UIImage?
    @State private var uploadedAvatar: String?
    @State private var loadID = UUID()
    private let editable = ["name","bio","country","gender","language","avatar_path"]
    @State private var birthday = ""
    @State private var term = ""
    @State private var searched = ""
    @State private var showDreams = false
    @State private var videoCount: Int?
    @State private var latestEntry: ProfileRecord?
    @State private var entriesLoaded = false
    @State private var busy = false
    @State private var ready = false
    @State private var notice = ""
    @State private var safety: String?
    @State private var reports: [ProfileRecord] = []
    @State private var undo: SafetyUndo?
    private enum SafetyUndo: Identifiable {
        case unblock(String, String), withdraw(String)
        var id: String {
            switch self { case .unblock(let id, _), .withdraw(let id): return id }
        }
        var title: String {
            switch self { case .unblock(_, let name): return "Unblock " + name + "?"
            case .withdraw: return "Withdraw this report?" }
        }
    }
    @State private var reportOpen = false
    @State private var reportReason = "Harassment"
    @State private var reportContext = ""
    @State private var reportID = UUID()
    private var me: String { app.api.userID }
    private var other: String { route.name == "person" ? route.id ?? me : me }
    private var following: Set<String> { Set(edges.filter { $0["follower_id"] as? String == other }.compactMap { $0["followed_id"] as? String }) }
    private var followers: Set<String> { Set(edges.filter { $0["followed_id"] as? String == other }.compactMap { $0["follower_id"] as? String }) }
    private let lists = ["profile.following","profile.followers","profile.friends","profile.blocked","profile.search"]
    private let menus: [(title: String, route: String, artwork: Int?)] = [
        ("Blocked users", "profile.blocked", 10), ("Report history", "profile.reports", nil),
        ("Privacy settings", "profile.privacy", 11), ("Terms of use", "legal.terms", 12),
        ("My level", "level", 13), ("Store & backpack", "store", 14),
        ("Contact us", "support", 16), ("Community guidelines", "legal.guidelines", 17),
        ("Delete account", "delete", 15)
    ]

    var body: some View {
        Group {
            if route.name == "profile.reports" { reportHistory }
            else if lists.contains(route.name) { peopleList }
            else if !ready || profile.isEmpty {
                VStack { if !ready { ProgressView() } else { Text("Profile unavailable") } }
            } else if route.name == "profile.edit" { edit }
            else if route.name == "profile.privacy" { privacy }
            else if route.name == "person" && other != me { publicProfile }
            else { overview }
        }
        .frame(maxWidth: .infinity,maxHeight: .infinity)
        .background { AccountBackdrop(group: route.name == "profile" ? "profile" : route.name == "person" ? "publicProfile" : "edit") }
        .minaAlert(notice)
        .safeAreaInset(edge: .bottom) {
            if !notice.isEmpty && (route.name != "profile.edit" || editingOwner.isEmpty) {
                Button("Reload") { Task { await load() } }.padding(10)
            }
        }
        .task(id: "\(route)-\(app.safetyRevision)-\(route.name != "person" || phase == .active)") {
            guard route.name != "person" || phase == .active else { return }
            await load()
            while route.name == "person", !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                await updateFriendship()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $reportOpen) {
            Form {
                Section("Report profile") {
                    Picker("Reason", selection: $reportReason) {
                        ForEach(["Harassment","Sexual content","Harmful content","Privacy concern","Spam","Other"],id: \.self) { Text($0) }
                    }
                    TextField("Additional details (optional)",text: $reportContext,axis: .vertical)
                }
                Button("Submit report") { Task { await submitReport() } }
                Button("Cancel") { reportOpen = false }
            }.disabled(busy).presentationDetents([.medium])
        }
        .confirmationDialog(safety ?? "", isPresented: Binding(get: { safety != nil }, set: { if !$0 { safety = nil } }), titleVisibility: .visible) {
            if safety == "Block listener?" {
                Button("Block", role: .destructive) { Task { await perform {
                    try await app.blockMember(other, name: profile["name"] as? String ?? "Listener")
                } } }
            }
        }
        .alert(undo?.title ?? "", isPresented: Binding(get: { undo != nil }, set: { if !$0 { undo = nil } }), presenting: undo) { action in
            Button("Cancel", role: .cancel) {}
            Button("Confirm", role: .destructive) { Task { await perform {
                switch action {
                case .unblock(let id, _):
                    try await app.api.rest("blocks?owner_id=eq." + me + "&blocked_id=eq." + id, method: "DELETE")
                case .withdraw(let id):
                    try await app.api.rest("rpc/withdraw_report", method: "POST", body: ["receipt": id])
                }
                app.safetyChanged()
            } } }
        }
    }

    private var reportHistory: some View {
        List {
            if !ready { ProgressView() }
            else if reports.isEmpty { Text("You have no reports.") }
            ForEach(reports.indices, id: \.self) { index in
                let row = reports[index]
                if let id = row["id"] as? String {
                    VStack(alignment: .leading, spacing: 6) {
                        Text((row["target_kind"] as? String ?? "Item").capitalized).font(.caption)
                        Text(row["target_label"] as? String ?? "Reported item").font(.headline)
                        Text(row["reason"] as? String ?? "")
                        Text("Receipt " + String(id.prefix(8))).font(.caption)
                        if row["withdrawn_at"] is String { Text("Withdrawn").foregroundStyle(.secondary) }
                        else { Button("Withdraw report") { undo = .withdraw(id) }.disabled(busy) }
                    }.padding(.vertical, 3)
                    .contextMenu {
                        if !(row["withdrawn_at"] is String) { Button("Withdraw report") { undo = .withdraw(id) } }
                    }
                }
            }
        }.navigationTitle("Report history")
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("Profile").font(.title.bold()).foregroundStyle(.white)
                    Spacer()
                    Button { app.go("profile.search") } label: {
                        HStack { Text("Find people"); NativeArt("profile", 3).scaledToFit().frame(width: 17) }
                            .font(.caption).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(.white.opacity(0.22), in: Capsule())
                    }.foregroundStyle(.white)
                }
                Button { app.go("profile.edit") } label: {
                    NativePortrait(path: profile["avatar_path"] as? String ?? "", size: 84)
                        .overlay(Circle().stroke(.white,lineWidth: 2))
                        .overlay(alignment: .bottomTrailing) { NativeArt("profile",4).scaledToFit().frame(width: 24) }
                }.accessibilityLabel("Edit profile")
                Text(profile["name"] as? String ?? "").font(.title3.bold())
                if let bio = profile["bio"] as? String, !bio.isEmpty { Text(bio).font(.footnote) }
                socialCounts
                HStack { workLink("My posts","feed.mine",5); workLink("My dreams","dreams.mine",6) }
                Button { app.go("wallet") } label: {
                    NativeArt("profile",7).scaledToFit().overlay(alignment: .leading) {
                        ProfileWalletBalance(wallet: app.wallet)
                    }.overlay(alignment: .trailing) { NativeArt("profile",8).scaledToFit().frame(width: 84).padding(.trailing,8) }
                }.accessibilityLabel("My wallet")
                Text("More settings").font(.headline).frame(maxWidth: .infinity,alignment: .leading)
                ForEach(menus, id: \.route) { item in
                    Button { app.go(item.route) } label: {
                        HStack(spacing: 14) {
                            if let artwork = item.artwork {
                                // The source rows are 350 by 54 points, with their icon centered at (30, 27).
                                NativeArt("profile", artwork).frame(width: 350, height: 54)
                                    .offset(x: -16, y: -13)
                                    .frame(width: 28, height: 28, alignment: .topLeading).clipped()
                            } else {
                                Image(systemName: "flag.fill").font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color(red: 0.07, green: 0.47, blue: 0.50))
                                    .frame(width: 28, height: 28)
                            }
                            Text(item.title).font(.body.weight(.semibold))
                                .foregroundStyle(item.route == "delete" ? Color(red: 0.65, green: 0.12, blue: 0.26)
                                                 : Color(red: 0.08, green: 0.19, blue: 0.25))
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.footnote.bold())
                                .foregroundStyle(Color(red: 0.22, green: 0.42, blue: 0.46))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
                Button { app.go("logout") } label: { NativeArt("profile",18).scaledToFit().frame(width: 175,height: 44) }.accessibilityLabel("Sign out")
            }.padding(.horizontal,16).padding(.bottom)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var publicProfile: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: -20) {
                    publicHeader
                        .frame(minHeight: viewport.size.width * 526 / 390, alignment: .bottom)
                        .background {
                            GeometryReader { box in
                                ZStack {
                                    Color(red: 0.22, green: 0.38, blue: 0.40)
                                    if let path = profile["avatar_path"] as? String, !path.isEmpty {
                                        PublicCoverPhoto(path: path, notice: $notice).id(loadID)
                                    }
                                    LinearGradient(stops: [
                                        .init(color: .clear, location: 0.42),
                                        .init(color: .black.opacity(0.72), location: 1)
                                    ], startPoint: .top, endPoint: .bottom)
                                }.frame(width: box.size.width, height: box.size.height).clipped()
                            }.accessibilityHidden(true)
                        }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Button { Task { await perform {
                                await updateFriendship()
                                if isFriend { app.go("messages.thread", other) }
                            } } } label: {
                                NativeArt("publicProfile", 4).scaledToFit()
                            }.grayscale(isFriend ? 0 : 1).opacity(isFriend ? 1 : 0.45)
                            .accessibilityLabel("Chat").disabled(!isFriend || busy)
                            followButton
                        }
                        HStack(spacing: 18) {
                            workTab(false)
                            workTab(true)
                        }
                        publicWork
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .top) {
                        ZStack(alignment: .top) {
                            Color(red: 0.92, green: 0.99, blue: 0.99)
                            NativeArt("publicProfile", 2).scaledToFit()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }.ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                HStack {
                    Button { app.back() } label: { coverControl(3) }.accessibilityLabel("Back")
                    Spacer()
                    Menu {
                        Button("Report profile") { notice = ""; reportOpen = true }
                        Button("Block listener", role: .destructive) { safety = "Block listener?" }
                    } label: { coverControl(12) }.accessibilityLabel("More")
                }.padding(.horizontal, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .buttonStyle(.plain)
        .task(id: other + String(showDreams)) { await loadPublicWork() }
    }

    private func coverControl(_ index: Int) -> some View {
        NativeArt("publicProfile", index).scaledToFit().frame(width: 24, height: 24)
            .padding(4).background(.white.opacity(0.55), in: Circle()).frame(width: 44, height: 44)
    }

    private var publicHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile["name"] as? String ?? "").font(.title.bold())
            if let bio = profile["bio"] as? String, !bio.isEmpty { Text(bio).font(.subheadline) }
            HStack(spacing: 0) {
                publicMetric("Following", following.count)
                metricDivider
                publicMetric("Followers", followers.count)
                metricDivider
                publicMetric("Friends", following.intersection(followers).count)
                metricDivider
                publicMetric("Videos", videoCount)
            }.padding(.top, 4)
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.bottom, 35).padding(.top, 110)
    }

    private var metricDivider: some View { Color.white.opacity(0.65).frame(width: 1, height: 24) }

    private func publicMetric(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 6) {
            Text(value?.formatted() ?? "–").font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.88))
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private var followButton: some View {
        Button { Task { await toggleFollow() } } label: {
            if followers.contains(me) {
                Capsule().fill(communityGradient).aspectRatio(338.0 / 108.0, contentMode: .fit)
                    .overlay { Text("Following").font(.headline.bold()).foregroundStyle(.black.opacity(0.78)) }
            } else { NativeArt("publicProfile", 5).scaledToFit() }
        }.disabled(busy).accessibilityLabel(followers.contains(me) ? "Following" : "Follow")
    }

    private func workTab(_ dreams: Bool) -> some View {
        let selected = showDreams == dreams
        return Button { showDreams = dreams } label: {
            VStack(spacing: 3) {
                NativeArt("publicProfile", dreams ? (selected ? 10 : 8) : (selected ? 7 : 9))
                    .scaledToFit().frame(maxWidth: dreams ? 127 : 119)
                NativeArt("publicProfile", 11).scaledToFit().frame(maxWidth: 115).opacity(selected ? 1 : 0)
            }.frame(minHeight: 44)
        }.accessibilityLabel(dreams ? "Previous dreams" : "Historical posts")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var publicWork: some View {
        if let entry = latestEntry, let id = entry["id"] as? String {
            HStack {
                NativePortrait(path: profile["avatar_path"] as? String ?? "", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile["name"] as? String ?? "").font(.subheadline.weight(.semibold))
                    if let raw = entry["created_at"] as? String {
                        Text(communityTimestamp(raw)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Button { app.go(showDreams ? "dreams.detail" : "feed.post", id) } label: {
                Text(entry["caption"] as? String ?? "").font(.subheadline)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let path = entry["media_path"] as? String {
                CommunityMedia(path: path, duration: entry.communitySeconds("duration"), voice: showDreams,
                               openPost: showDreams ? nil : { app.go("feed.post", id) })
            }
        } else if entriesLoaded {
            Text(showDreams ? "No dreams yet." : "No posts yet.").font(.subheadline)
        } else if notice.isEmpty { ProgressView() }
        Button(showDreams ? "View all dreams" : "View all posts") {
            app.go(showDreams ? "dreams.author" : "feed.author", other)
        }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
    }

    private func loadPublicWork() async {
        latestEntry = nil
        entriesLoaded = false
        let kind = showDreams ? "dream" : "post"
        do {
            let result = try await app.api.rows("entry_feed?select=id,caption,media_path,duration,created_at&owner_id=eq." + other + "&kind=eq." + kind + "&order=created_at.desc,id.desc&limit=1")
            try Task.checkCancellation()
            latestEntry = result.first
            entriesLoaded = true
        } catch { if !Task.isCancelled { notice = error.localizedDescription } }
    }

    private var socialCounts: some View {
        HStack {
            metric("Following", following.count, "profile.following")
            metric("Followers", followers.count, "profile.followers")
            metric("Friends", following.intersection(followers).count, "profile.friends")
        }
    }
    private func metric(_ title: String, _ count: Int, _ page: String) -> some View {
        Button { if other == me { app.go(page) } } label: {
            VStack(spacing: 3) { Text(count.formatted()).bold(); Text(title).font(.caption) }.frame(maxWidth: .infinity,minHeight:44)
        }.buttonStyle(.plain).disabled(other != me)
    }

    private func workLink(_ title: String, _ page: String, _ art: Int) -> some View {
        Button { app.go(page) } label: { NativeArt("profile",art).scaledToFit() }.accessibilityLabel(title)
    }

    private var peopleList: some View {
        List {
            if route.name == "profile.search" {
                HStack {
                    TextField("Search by nickname", text: $term).onSubmit { search() }
                    Button("Search") { search() }
                }
            }
            ForEach(people.indices, id: \.self) { i in
                let item = people[i]
                if let id = item["id"] as? String {
                    HStack {
                        NativePortrait(path: item["avatar_path"] as? String ?? "", size: 44)
                        Text(item["name"] as? String ?? "Listener")
                        Spacer()
                        if route.name == "profile.blocked" {
                            Button("Unblock") { undo = .unblock(id, item["name"] as? String ?? "listener") }
                                .disabled(busy)
                                .contextMenu { Button("Unblock") { undo = .unblock(id, item["name"] as? String ?? "listener") } }
                        } else { Button("View") { app.go("person", id) } }
                    }
                }
            }
            if !ready { ProgressView() }
            else if people.isEmpty { Text(route.name == "profile.search" && searched.isEmpty ? "Find a listener by nickname." : "No listeners to show.") }
        }.scrollContentBackground(.hidden).listStyle(.insetGrouped).navigationTitle(["profile.blocked":"Blocked users","profile.search":"Find people","profile.following":"Following","profile.followers":"Followers","profile.friends":"Friends"][route.name] ?? "People")
    }

    private func search() { searched = term.trimmingCharacters(in: .whitespacesAndNewlines); Task { await load() } }

    private var edit: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 16) {
                field("Nickname","name")
                Text("Profile photo").font(.caption).foregroundStyle(.secondary)
                Button { Task { await pickAvatar() } } label: {
                    ZStack(alignment: .bottom) {
                        if let avatarImage {
                            Image(uiImage: avatarImage).resizable().scaledToFill().frame(width: 116,height: 116).clipped()
                        } else if let path = profile["avatar_path"] as? String, !path.isEmpty {
                            PublicCoverPhoto(path: path, notice: $notice).frame(width: 124,height: 124).clipped()
                        } else { NativeArt("edit",4).scaledToFit().frame(width: 124,height: 124) }
                        NativeArt("edit",6).scaledToFit().frame(width:64).padding(5)
                    }.frame(width:124,height:124).clipShape(RoundedRectangle(cornerRadius: 12))
                }.frame(maxWidth: .infinity).accessibilityLabel("Choose photo")
                field("Country or region","country")
                VStack(alignment: .leading,spacing: 5) {
                    HStack {
                        Text("Gender").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Button("Nonbinary") { profile["gender"] = "Nonbinary" }
                            Button("Prefer not to say") { profile["gender"] = "" }
                        } label: {
                            Text((profile["gender"] as? String) == "Nonbinary" ? "Nonbinary" : (profile["gender"] as? String ?? "").isEmpty ? "Prefer not to say" : "More options")
                                .font(.caption).padding(.vertical,5)
                        }.accessibilityLabel("More gender options")
                    }
                    HStack {
                        ForEach(["Male","Female"],id: \.self) { value in
                            let chosen = (profile["gender"] as? String) == value
                            Button { profile["gender"] = value } label: {
                                HStack(spacing: 7) {
                                    NativeArt("edit",value == "Male" ? (chosen ? 13 : 11) : (chosen ? 12 : 10))
                                        .scaledToFit().frame(width: 20,height: 20)
                                    Text(value)
                                }.frame(maxWidth: .infinity,minHeight: 44)
                                    .background(.white,in: RoundedRectangle(cornerRadius: 10))
                                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(chosen ? Color.teal : .clear,lineWidth: 2) }
                            }.buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Birthday").font(.caption).foregroundStyle(.secondary)
                    TextField("YYYY-MM-DD",text: $birthday).keyboardType(.numbersAndPunctuation)
                        .padding(12).background(.white,in: RoundedRectangle(cornerRadius: 10))
                }
                field("Language","language")
                field("Signature","bio")
            }.padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { Task { await saveProfile() } } label: {
                NativeArt("edit",14).scaledToFit().frame(maxWidth: 282).frame(height: 52)
            }.frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(.regularMaterial).accessibilityLabel("Save")
        }
        .disabled(busy).navigationTitle("Edit profile")
        .navigationBarBackButtonHidden(busy)
        .onDisappear { discardAvatar() }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { profile[key] as? String ?? "" }, set: { profile[key] = $0 })
    }
    private func field(_ label: String, _ key: String) -> some View {
        VStack(alignment: .leading,spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label,text: binding(key),axis: .vertical).lineLimit(key == "bio" ? 3...5 : 1...1)
                .padding(12).background(.white,in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var privacy: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(["private_profile","show_status","allow_messages","allow_calls"], id: \.self) { key in
                        let label = ["private_profile":"Private profile", "show_status":"Show activity status", "allow_messages":"Allow messages", "allow_calls":"Allow voice calls"][key] ?? key
                        Toggle(label, isOn: Binding(get: { profile[key] as? Bool ?? false }, set: { next in
                            Task { await perform {
                                try await app.api.rest("profiles?id=eq." + me, method: "PATCH", body: [key: next])
                                profile[key] = next
                            } }
                        })).disabled(busy).tint(.mint).padding(.horizontal).frame(minHeight: 52)
                        if key != "allow_calls" { Divider().opacity(0.4) }
                    }
                }.background(.white,in: RoundedRectangle(cornerRadius: 10))
                VStack(spacing: 0) {
                    ForEach([("User agreement","legal.terms"),("Privacy policy","legal.privacy")],id: \.0) { item in
                        Button { app.go(item.1) } label: {
                            HStack { Text(item.0); Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary) }
                                .frame(minHeight: 52).padding(.horizontal).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if item.1 == "legal.terms" { Divider().opacity(0.4) }
                    }
                }.background(.white,in: RoundedRectangle(cornerRadius: 10))
            }.padding()
        }.navigationTitle("Privacy settings")
    }

    private func load() async {
        let version = UUID()
        loadID = version
        do {
            notice = ""
            let owner = other
            guard UUID(uuidString: owner) != nil else { throw MiNaIssue("This listener is unavailable.") }
            let remote = try await app.api.rows("profiles?select=*&id=eq." + owner).first ?? [:]
            if route.name == "profile.edit" {
                guard !remote.isEmpty, let settings = try await app.api.rows("personal_settings?select=birthday&id=eq." + owner).first else {
                    throw MiNaIssue("Your profile settings could not be loaded. Please retry.")
                }
                try Task.checkCancellation()
                guard loadID == version, app.api.userID == owner else { return }
                profile = remote
                savedFields = Dictionary(uniqueKeysWithValues: editable.map { ($0,remote[$0] as? String ?? "") })
                savedBirthday = settings["birthday"] as? String ?? ""
                birthday = savedBirthday; editingOwner = owner; ready = true
                return
            }
            try Task.checkCancellation()
            guard loadID == version else { return }
            profile = remote
            if route.name == "person" { await updateFriendship() }
            if route.name == "profile", owner == me, !remote.isEmpty {
                do { try cacheProfile(remote) } catch { notice = "Your profile loaded. Its copy on this iPhone could not be updated." }
            }
            edges = try await app.api.rows("follows?select=follower_id,followed_id&or=(follower_id.eq." + owner + ",followed_id.eq." + owner + ")")
            if route.name == "person", owner != me {
                videoCount = try await app.api.rest("entry_feed?select=id&owner_id=eq." + owner + "&kind=eq.post&limit=1", method: "HEAD", prefer: "count=exact") as? Int
            }
            if route.name == "profile" { app.didRefreshRoot("profile") }
            if route.name == "profile.reports" {
                reports = try await app.api.rows("reports?select=id,target_kind,target_label,reason,withdrawn_at&reporter_id=eq." + me + "&order=created_at.desc")
            } else if route.name == "profile.blocked" {
                let names = app.state("people") as? [String:String] ?? [:]
                people = try await app.api.rows("blocks?select=blocked_id,blocked_name&owner_id=eq." + me).compactMap { row in
                    guard let id = row["blocked_id"] as? String else { return nil }
                    return ["id":id, "name":row["blocked_name"] as? String ?? names[id] ?? "Listener " + String(id.prefix(6))]
                }
            } else if lists.contains(route.name) {
                var filter = ""
                if route.name == "profile.search" {
                    let allowed = CharacterSet.alphanumerics.union(.whitespaces)
                    let cleaned = searched.unicodeScalars.filter(allowed.contains).map(String.init).joined()
                    if !cleaned.isEmpty { filter = "name=ilike.*" + (cleaned.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") + "*&id=neq." + me }
                } else {
                    let ids = route.name == "profile.friends" ? following.intersection(followers) : route.name == "profile.followers" ? followers : following
                    if !ids.isEmpty { filter = "id=in.(" + ids.joined(separator: ",") + ")" }
                }
                let results = filter.isEmpty ? [] : try await app.api.rows("profiles?select=id,name,avatar_path&" + filter + "&order=name&limit=100")
                guard loadID == version, !Task.isCancelled else { return }
                people = results
            }
        } catch { if !Task.isCancelled && loadID == version { isFriend = false; notice = error.localizedDescription } }
        if loadID == version && !Task.isCancelled { ready = true }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; notice = ""
        defer { busy = false }
        do { try await action() } catch { notice = error.localizedDescription }
    }

    @MainActor private func updateFriendship() async {
        let owner = other
        let value = (try? await app.api.isChatFriend(owner)) ?? false
        guard !Task.isCancelled, other == owner else { return }
        isFriend = value
    }

    private func toggleFollow() async {
        await perform {
            if followers.contains(me) { try await app.api.rest("follows?follower_id=eq." + me + "&followed_id=eq." + other, method: "DELETE") }
            else { try await app.api.rest("follows", method: "POST", body: ["followed_id":other]) }
            await load()
        }
    }

    private func submitReport() async {
        await perform {
            let receipt = try await app.api.report(other, kind: "profile", reason: reportReason, details: reportContext, operation: reportID)
            reportOpen = false; reportID = UUID(); reportContext = ""
            app.back(); app.safetyChanged()
            app.safetyNotice = "Report received · " + String(receipt.prefix(8))
        }
    }

    private func discardAvatar() {
        avatarData = nil
        avatarID = nil; avatarImage = nil; uploadedAvatar = nil
    }

    private func pickAvatar() async {
        await perform {
            let chosen = try await app.pick("image")
            guard let id = chosen["id"] as? String else { return }
            guard me == editingOwner, let raw = chosen["url"] as? String, let url = URL(string: raw),
                  let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                if me == editingOwner { try? app.media.remove(id) }
                throw MiNaIssue("The selected image could not be opened.")
            }
            discardAvatar()
            try app.media.remove(id)
            avatarID = id; avatarImage = image; avatarData = data
        }
    }

    private func cacheProfile(_ fields: ProfileRecord) throws {
        let next = ["name":fields["name"] as? String ?? "", "avatarId":fields["avatar_path"] as? String ?? ""]
        if app.state("profile") as? [String:String] != next { try app.save("profile",next) }
    }

    private func patch(_ table: String, _ fields: ProfileRecord) async throws {
        guard me == editingOwner, !me.isEmpty else { throw MiNaIssue("Reopen your profile to continue.") }
        let result = try await app.api.rest(table + "?id=eq." + me + "&select=id", method: "PATCH", body: fields, prefer: "return=representation")
        guard let saved = (result as? [ProfileRecord])?.first?["id"] as? String, saved == editingOwner else {
            throw MiNaIssue("The service could not confirm this update.")
        }
    }

    private func saveProfile() async {
        await perform {
            let name = (profile["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let bio = profile["bio"] as? String ?? ""
            guard (1...50).contains(name.count), bio.split(whereSeparator: { $0.isWhitespace }).count <= 50, bio.count <= 500 else {
                throw MiNaIssue("Enter a nickname and a signature of up to 50 words.")
            }
            if !birthday.isEmpty {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                guard let date = formatter.date(from: birthday), formatter.string(from: date) == birthday, date <= Date() else { throw MiNaIssue("Enter a valid birthday in YYYY-MM-DD format.") }
            }
            guard me == editingOwner, !editingOwner.isEmpty else { throw MiNaIssue("Reopen your profile to continue.") }
            if let avatarID, uploadedAvatar == nil {
                guard let data = avatarData else { throw MiNaIssue("Choose your profile photo again.") }
                uploadedAvatar = try await app.api.upload(data, type: "image/jpeg", extension: "jpg", id: avatarID)
            }
            if let uploadedAvatar { profile["avatar_path"] = uploadedAvatar }
            profile["name"] = name
            let fields = Dictionary(uniqueKeysWithValues: editable.map { ($0, profile[$0] as? String ?? "") })
            let changes = fields.filter { savedFields[$0.key] != $0.value }
            if !changes.isEmpty {
                try await patch("profiles", changes)
                savedFields = fields
                discardAvatar()
            }
            if birthday != savedBirthday {
                let dateValue: Any = birthday.isEmpty ? NSNull() as Any : birthday
                do { try await patch("personal_settings", ["birthday":dateValue]) }
                catch { throw MiNaIssue("Your profile details are up to date. The birthday update is unconfirmed. Tap Save to retry. " + error.localizedDescription) }
                savedBirthday = birthday
            }
            do { try cacheProfile(profile) }
            catch { throw MiNaIssue("Your profile is saved on MiNa. Tap Save to retry updating this iPhone’s local copy.") }
            app.back()
        }
    }
}

struct AccountBackdrop: View {
    let group: String
    var body: some View {
        GeometryReader { box in
            NativeArt(group,1).frame(width: box.size.width,height: box.size.height)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct PublicCoverPhoto: View {
    @EnvironmentObject var app: MiNaAppModel
    let path: String
    @Binding var notice: String
    @State private var url: URL?
    var body: some View {
        CloudPortraitImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color.clear.onAppear { notice = "The profile photo couldn’t be loaded. Please try again." }
            default:
                Color.clear
            }
        }
        .task(id: path) {
            url = nil
            do {
                let signedURL = try await app.api.mediaURL(path)
                try Task.checkCancellation()
                url = signedURL
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                notice = "The profile photo couldn’t be loaded. Please try again."
            }
        }
    }
}

private struct ProfileWalletBalance: View {
    @ObservedObject var wallet: WalletStore

    var body: some View {
        if let balance = wallet.ledger?.balance {
            Text(balance.formatted()).font(.footnote.bold()).padding(.leading, 70).padding(.top, 22)
        }
    }
}

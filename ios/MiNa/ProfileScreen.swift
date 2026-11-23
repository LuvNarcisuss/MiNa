import SwiftUI

private typealias ProfileRecord = [String: Any]

struct ProfileScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var profile: ProfileRecord = [:]
    @State private var edges: [ProfileRecord] = []
    @State private var people: [ProfileRecord] = []
    @State private var balance: Int?
    @State private var savedFields: [String:String] = [:]
    @State private var savedBirthday = ""
    @State private var editingOwner = ""
    @State private var avatarID: String?
    @State private var avatarImage: UIImage?
    @State private var uploadedAvatar: String?
    @State private var loadID = UUID()
    private let editable = ["name","bio","country","gender","language","avatar_path"]
    @State private var birthday = ""
    @State private var term = ""
    @State private var searched = ""
    @State private var showDreams = false
    @State private var latestEntry: ProfileRecord?
    @State private var entriesLoaded = false
    @State private var busy = false
    @State private var ready = false
    @State private var notice = ""
    @State private var safety: String?
    @State private var reportOpen = false
    @State private var reportReason = "Harassment"
    @State private var reportContext = ""
    @State private var reportID = UUID()
    private var me: String { app.api.userID }
    private var other: String { route.name == "person" ? route.id ?? me : me }
    private var following: Set<String> { Set(edges.filter { $0["follower_id"] as? String == other }.compactMap { $0["followed_id"] as? String }) }
    private var followers: Set<String> { Set(edges.filter { $0["followed_id"] as? String == other }.compactMap { $0["follower_id"] as? String }) }
    private let lists = ["profile.following","profile.followers","profile.friends","profile.blocked","profile.search"]
    private let menus = [("Blocked users","profile.blocked",10), ("Privacy settings","profile.privacy",11),
                         ("Terms of use","legal.terms",12), ("My level","level",13), ("Store & backpack","store",14),
                         ("Contact us","support",16), ("Community guidelines","legal.guidelines",17), ("Delete account","delete",15)]

    var body: some View {
        Group {
            if lists.contains(route.name) { peopleList }
            else if !ready || profile.isEmpty {
                VStack { if !ready { ProgressView() } else { Text("Profile unavailable") } }
            } else if route.name == "profile.edit" { edit }
            else if route.name == "profile.privacy" { privacy }
            else { overview }
        }
        .frame(maxWidth: .infinity,maxHeight: .infinity)
        .background { AccountBackdrop(group: route.name == "profile" ? "profile" : route.name == "person" ? "publicProfile" : "edit") }
        .safeAreaInset(edge: .bottom) {
            if !notice.isEmpty {
                HStack { Text(notice).font(.footnote); Spacer(); if route.name != "profile.edit" || editingOwner.isEmpty { Button("Reload") { Task { await load() } } } }
                    .padding(10).background(.regularMaterial)
            }
        }
        .task(id: route) { await load() }
        .environment(\.colorScheme,.light)
        .preferredColorScheme(route.name == "profile" ? .dark : .light)
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
                if !notice.isEmpty { Text(notice) }
            }.disabled(busy).presentationDetents([.medium])
        }
        .confirmationDialog(safety ?? "", isPresented: Binding(get: { safety != nil }, set: { if !$0 { safety = nil } }), titleVisibility: .visible) {
            if safety == "Block listener?" {
                Button("Block", role: .destructive) { Task { await perform {
                    try await app.api.rest("blocks", method: "POST", body: ["blocked_id": other], prefer: "resolution=ignore-duplicates")
                    var names = app.state("people") as? [String: String] ?? [:]
                    names[other] = profile["name"] as? String
                    do { try app.save("people", names) }
                    catch { throw MiNaIssue("This listener is blocked. Their name could not be saved in the local blocked list.") }
                    app.back()
                } } }
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 12) {
                if other == me {
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
                            if let balance { Text(balance.formatted()).font(.footnote.bold()).padding(.leading,70).padding(.top,22) }
                        }.overlay(alignment: .trailing) { NativeArt("profile",8).scaledToFit().frame(width: 84).padding(.trailing,8) }
                    }.accessibilityLabel("My wallet")
                    Text("More settings").font(.headline).frame(maxWidth: .infinity,alignment: .leading)
                    ForEach(menus.indices, id: \.self) { index in
                        let item = menus[index]
                        Button { app.go(item.1) } label: { NativeArt("profile",item.2).scaledToFit() }.accessibilityLabel(item.0)
                    }
                    Button { app.go("logout") } label: { NativeArt("profile",18).scaledToFit().frame(width: 175,height: 44) }.accessibilityLabel("Sign out")
                } else {
                    publicHeader
                    HStack {
                        Button { app.go("messages.thread",other) } label: { NativeArt("publicProfile",4).scaledToFit() }
                            .accessibilityLabel("Chat").disabled(profile["allow_messages"] as? Bool == false)
                        Button { Task { await toggleFollow() } } label: {
                            if followers.contains(me) { Text("Following").frame(maxWidth: .infinity,minHeight: 48).background(.mint.opacity(0.25),in: Capsule()) }
                            else { NativeArt("publicProfile",5).scaledToFit() }
                        }.disabled(busy).accessibilityLabel(followers.contains(me) ? "Following" : "Follow")
                    }
                    Picker("Published work",selection: $showDreams) {
                        Text("Historical posts").tag(false); Text("Previous dreams").tag(true)
                    }.pickerStyle(.segmented)
                    if let entry = latestEntry, let id = entry["id"] as? String {
                        VStack(alignment: .leading,spacing: 10) {
                            HStack {
                                NativePortrait(path: profile["avatar_path"] as? String ?? "",size: 38)
                                Text(profile["name"] as? String ?? "Listener").bold()
                            }
                            Button { app.go(showDreams ? "dreams.detail" : "feed.post",id) } label: {
                                Text(entry["caption"] as? String ?? "").frame(maxWidth: .infinity,alignment: .leading)
                            }.buttonStyle(.plain)
                            if let path = entry["media_path"] as? String {
                                CommunityMedia(path:path,duration:(entry["duration"] as? NSNumber)?.doubleValue ?? 0,voice:showDreams,remote:true)
                            }
                        }.padding().background(.white,in: RoundedRectangle(cornerRadius: 14))
                    } else if entriesLoaded { Text(showDreams ? "No dreams yet." : "No posts yet.").font(.footnote) }
                    Button(showDreams ? "View all dreams" : "View all posts") { app.go(showDreams ? "dreams.author" : "feed.author",other) }
                        .task(id: other + String(showDreams)) {
                            latestEntry = nil; entriesLoaded = false
                            do {
                                let kind = showDreams ? "dream" : "post"
                                let rows = try await app.api.rows("entry_feed?select=id,caption,media_path,duration&owner_id=eq." + other + "&kind=eq." + kind + "&order=created_at.desc,id.desc&limit=1")
                                try Task.checkCancellation()
                                latestEntry = rows.first; entriesLoaded = true
                            } catch { if !Task.isCancelled { notice = error.localizedDescription } }
                        }
                }
            }.padding(.horizontal,16).padding(.bottom)
        }
        .toolbar(other == me ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if other != me {
                Menu {
                    Button("Report profile") { notice = ""; reportOpen = true }
                    Button("Block listener", role: .destructive) { safety = "Block listener?" }
                } label: { NativeArt("publicProfile",12).scaledToFit().frame(width:24) }.accessibilityLabel("More")
            }
        }
    }

    private var publicHeader: some View {
        VStack(alignment: .leading,spacing: 10) {
            Spacer(minLength: 150)
            Text(profile["name"] as? String ?? "").font(.title.bold())
            if let bio = profile["bio"] as? String, !bio.isEmpty { Text(bio) }
            socialCounts
        }.padding().frame(maxWidth: .infinity,alignment: .leading).foregroundStyle(.white)
            .background {
                GeometryReader { box in
                    ZStack {
                        NativeArt("publicProfile",1).scaledToFill()
                        if let path = profile["avatar_path"] as? String, !path.isEmpty {
                            PublicCoverPhoto(path: path)
                        }
                        LinearGradient(colors: [.clear,.black.opacity(0.76)],startPoint: .top,endPoint: .bottom)
                    }.frame(width:box.size.width,height:box.size.height).clipped()
                }
            }.clipShape(RoundedRectangle(cornerRadius: 16))
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
                            Button("Unblock") { Task { await perform {
                                try await app.api.rest("blocks?owner_id=eq." + me + "&blocked_id=eq." + id, method: "DELETE")
                                await load()
                            } } }.disabled(busy)
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
                            PublicCoverPhoto(path: path).frame(width: 124,height: 124).clipped()
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
                Button { Task { await saveProfile() } } label: {
                    NativeArt("edit",14).scaledToFit().frame(maxWidth: 282)
                }.frame(maxWidth: .infinity).accessibilityLabel("Save")
            }.padding()
        }.disabled(busy).navigationTitle("Edit profile")
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
            if route.name == "profile", owner == me, !remote.isEmpty {
                do { try cacheProfile(remote) } catch { notice = "Your profile loaded. Its copy on this iPhone could not be updated." }
            }
            edges = try await app.api.rows("follows?select=follower_id,followed_id&or=(follower_id.eq." + owner + ",followed_id.eq." + owner + ")")
            if route.name == "profile" { balance = try await app.api.rows("wallets?select=balance&owner_id=eq." + me).first?["balance"] as? Int }
            if route.name == "profile.blocked" {
                let names = app.state("people") as? [String:String] ?? [:]
                people = try await app.api.rows("blocks?select=blocked_id&owner_id=eq." + me).compactMap { row in
                    guard let id = row["blocked_id"] as? String else { return nil }
                    return ["id":id, "name":names[id] ?? "Listener " + String(id.prefix(6))]
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
        } catch { if !Task.isCancelled && loadID == version { notice = error.localizedDescription } }
        if loadID == version && !Task.isCancelled { ready = true }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; notice = ""
        defer { busy = false }
        do { try await action() } catch { notice = error.localizedDescription }
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
            let id = reportID.uuidString.lowercased()
            let reason = String((reportReason + (reportContext.isEmpty ? "" : " · " + reportContext)).prefix(1000))
            let result = try await app.api.rest("reports?select=id", method: "POST", body: ["id":id,"reporter_id":me,"target_id":other,"target_kind":"profile","reason":reason], prefer: "return=representation,resolution=ignore-duplicates")
            var receipt = (result as? [ProfileRecord])?.first?["id"] as? String
            if receipt == nil { receipt = try await app.api.rows("reports?select=id&id=eq." + id + "&reporter_id=eq." + me).first?["id"] as? String }
            guard let receipt else { throw MiNaIssue("Your report could not be confirmed. Please retry.") }
            reportOpen = false; reportID = UUID(); reportContext = ""
            notice = "Report received · " + String(receipt.prefix(8))
        }
    }

    private func discardAvatar() {
        if let avatarID, editingOwner == me { try? app.media.remove(avatarID) }
        avatarID = nil; avatarImage = nil; uploadedAvatar = nil
    }

    private func pickAvatar() async {
        await perform {
            let chosen = try await app.pick("image")
            guard let id = chosen["id"] as? String else { return }
            guard me == editingOwner, let raw = chosen["url"] as? String, let url = URL(string: raw),
                  let image = UIImage(contentsOfFile: url.path) else {
                if me == editingOwner { try? app.media.remove(id) }
                throw MiNaIssue("The selected image could not be opened.")
            }
            discardAvatar()
            avatarID = id; avatarImage = image
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
                guard let raw = try app.media.resolve(avatarID)["url"] as? String, let url = URL(string: raw) else { throw MiNaIssue("Choose your profile photo again.") }
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                guard me == editingOwner else { throw MiNaIssue("Reopen your profile to continue.") }
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
    @State private var url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
        }.task(id: path) { url = try? await app.api.mediaURL(path) }
    }
}

import SwiftUI
import AVFoundation

typealias RoomRow = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func roomText(_ key: String) -> String { self[key] as? String ?? "" }
    func roomFlag(_ key: String) -> Bool { self[key] as? Bool ?? false }
}

struct RoomSound: Identifiable {
    let id: String
    let title: String
    let detail: String
    let topic: String
    static let all = [
        RoomSound(id: "moon-seat", title: "A Moon to Lean On", detail: "Slow, warm harmonies", topic: "Light music"),
        RoomSound(id: "star-pillow", title: "Starlight Lullaby", detail: "Soft bells under the stars", topic: "Light music"),
        RoomSound(id: "moonlit-sea", title: "The Midnight Tide", detail: "Gentle waves on a quiet shore", topic: "Nature sounds")
    ]
    static func find(_ id: String) -> Self? { all.first { $0.id == id } }
}

struct RoomArtwork: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        nativeArtwork("rooms-extra", name).accessibilityHidden(true)
    }
}

@MainActor final class RoomPlayer: ObservableObject {
    @Published var playing = ""
    @Published var error = ""
    private var audio: AVAudioPlayer?
    func stop() { audio?.stop(); audio = nil; playing = "" }
    func play(_ sound: RoomSound, from start: Date? = nil) {
        stop()
        do {
            guard let url = Bundle.main.url(forResource: sound.id, withExtension: "wav", subdirectory: "Artwork/rooms-extra") else {
                throw MiNaIssue("This soundscape is unavailable.")
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.72
            if let start, player.duration > 0 { player.currentTime = max(0, -start.timeIntervalSinceNow).truncatingRemainder(dividingBy: player.duration) }
            guard player.play() else { throw MiNaIssue("Playback could not start.") }
            audio = player
            playing = sound.id
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}

func roomDate(_ text: String) -> Date? {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}
func roomStamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
func roomFilter(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
}
func roomUUID() -> String { UUID().uuidString.lowercased() }

struct RoomsScreen: View {
    let route: NativeRoute
    var body: some View {
        Group {
            switch route.name {
            case "rooms.live":
                if let id = route.id, UUID(uuidString: id) != nil { RoomLiveView(id: id).id(id) }
                else { Text("This room is unavailable.") }
            case "rooms.stage": RoomLocalStage(id: route.id ?? "")
            case "rooms.create": RoomEditorView(id: route.id)
            case "rooms.ranks": RoomRankings(room: nil)
            default: RoomDiscovery(route: route.name)
            }
        }.tint(Color(red: 0.04, green: 0.46, blue: 0.51))
    }
}

struct RoomChoiceRow: View {
    let cover: String
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                RoomArtwork(cover).scaledToFill().frame(width: 58, height: 58).clipped().cornerRadius(13)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("›").font(.title2)
            }.padding(9).background(.background, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

private struct RoomDiscovery: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: String
    @State private var followed = false
    @State private var query = ""
    @State private var rooms: [RoomRow] = []
    @State private var status = "Finding rooms…"
    @State private var retry = 0
    var home: Bool { route == "rooms" }
    var search: Bool { route == "rooms.search" }
    var drafts: [RoomRow] { app.state("room.drafts") as? [RoomRow] ?? [] }
    func matches(_ value: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || value.localizedCaseInsensitiveContains(text)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if home {
                    HStack {
                        Picker("Discover rooms", selection: $followed) {
                            Text("Voice Rooms").tag(false)
                            Text("Followed").tag(true)
                        }.pickerStyle(.segmented)
                        Button { app.go("rooms.ranks") } label: { RoomArtwork("rank-button").scaledToFit().frame(width: 48,height: 48) }.accessibilityLabel("Open rankings")
                    }
                    Button { app.go("rooms.search") } label: {
                        HStack { NativeArt("home", 6).frame(width: 20,height: 20); Text("Search rooms and sounds"); Spacer() }.padding(12).background(.white.opacity(0.85), in: Capsule())
                    }
                    if !followed {
                        Button { app.go("dreams") } label: {
                            ZStack(alignment: .leading) {
                                RoomArtwork("dream-banner").scaledToFill()
                                VStack(alignment: .leading) {
                                    Text("Mysterious\nDream Space").font(.title.bold())
                                    Text("Explore dreams ›").font(.subheadline.bold())
                                }.foregroundColor(.white).shadow(radius: 3).padding()
                            }.frame(height: 135).clipped().cornerRadius(20)
                        }
                        HStack { Text("Tonight’s soundscapes").font(.headline); Spacer(); Button("More") { app.go("rooms.sounds") } }
                        HStack {
                            ForEach(RoomSound.all.prefix(2)) { sound in
                                Button { app.go("rooms.stage", sound.id) } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        RoomArtwork(sound.id).scaledToFill()
                                        Text(sound.title).font(.headline).foregroundColor(.white).shadow(radius: 4).padding(8)
                                    }.frame(maxWidth: .infinity).frame(height: 112).clipped().cornerRadius(14)
                                }
                            }
                        }
                    }
                }
                if search { TextField("Search by name or topic", text: $query).textFieldStyle(.roundedBorder) }
                if route != "rooms.sounds" {
                    HStack {
                        Text(followed ? "Followed rooms" : "Live rooms").font(.title3.bold())
                        Spacer()
                        if home && rooms.count > 3 { Button("More") { app.go("rooms.liveList") } }
                    }
                    let found = rooms.filter { matches($0.roomText("title") + " " + $0.roomText("topic")) }
                    ForEach(Array(found.prefix(home ? 3 : 100).enumerated()), id: \.offset) { _, r in
                        RoomChoiceRow(cover: r.roomText("cover"), title: r.roomText("title"), detail: r.roomText("topic") + " · " + (["private":"Only me","followers":"Followers only"][r.roomText("visibility")] ?? "Public room")) { app.go("rooms.live", r.roomText("id")) }
                    }
                    if found.isEmpty {
                        Text(status.isEmpty ? (search && !query.isEmpty ? "No matching live rooms." : "No open rooms right now.") : status).foregroundStyle(.secondary)
                        if status == "Live rooms could not load." { Button("Retry") { retry += 1 } }
                    }
                }
                if route != "rooms.liveList" {
                    Text(followed ? "Saved sounds" : home ? "Recommended" : "Listen offline").font(.title3.bold())
                    let saved = app.state("room.savedSounds") as? [String] ?? []
                    let sounds = RoomSound.all.filter { (!followed || saved.contains($0.id)) && matches([$0.title,$0.detail,$0.topic].joined(separator: " ")) }
                    ForEach(sounds) { sound in
                        RoomChoiceRow(cover: sound.id, title: sound.title, detail: sound.detail + " · Offline soundscape") { app.go("rooms.stage", sound.id) }
                    }
                    if sounds.isEmpty { Text(followed ? "Save a soundscape from its listening room." : "No matching soundscapes.") }
                    if !followed && route != "rooms.sounds" {
                        Text("Your room drafts").font(.title3.bold())
                        ForEach(Array(drafts.filter { matches($0.roomText("title") + " " + $0.roomText("topic")) }.enumerated()), id: \.offset) { _, draft in
                            RoomChoiceRow(cover: draft.roomText("cover"), title: draft.roomText("title"), detail: draft.roomText("topic") + " · Private draft") { app.go("rooms.stage", draft.roomText("id")) }
                        }
                        if home && drafts.isEmpty { Button("Create your first room draft") { app.go("rooms.create") } }
                    }
                }
            }.padding().padding(.bottom, home ? 55 : 0)
        }
        .background(alignment: .top) { if home { NativeArt("home",1).scaledToFill().ignoresSafeArea().allowsHitTesting(false) } }
        .overlay(alignment: .bottomTrailing) { if home {
            Button { app.go("rooms.create") } label: { RoomArtwork("create-button").frame(width: 62,height: 62) }.padding().accessibilityLabel("Create a room")
        } }
        .navigationTitle(home ? "" : search ? "Search rooms" : route == "rooms.sounds" ? "Soundscapes" : "Live rooms")
        .task(id: "\(route)-\(followed)-\(retry)") {
            guard route != "rooms.sounds" else { return }
            rooms = []; status = "Finding rooms…"
            while !Task.isCancelled {
                do {
                    var path = "rooms?closed=eq.false&order=created_at.desc&limit=100"
                    var skip = false
                    if followed {
                        let links = try await app.api.rows("follows?select=followed_id&follower_id=eq." + app.api.userID)
                        let ids = links.map { $0.roomText("followed_id") }
                        skip = ids.isEmpty
                        path += "&host_id=in.(" + ids.joined(separator: ",") + ")"
                    }
                    let result = skip ? [] : try await app.api.rows(path)
                    try Task.checkCancellation()
                    rooms = result; status = ""
                } catch { if Task.isCancelled { return }; rooms = []; status = "Live rooms could not load." }
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }
}

private struct RoomEditorView: View {
    @EnvironmentObject var app: MiNaAppModel
    let id: String?
    @State private var title = ""
    @State private var cover = RoomSound.all[0].id
    @State private var topic = "Light music"
    @State private var visibility = "Only me"
    @State private var follow = true
    @State private var gifts = false
    @State private var comments = true
    @State private var operation = roomUUID()
    @State private var busy = false
    @State private var error = ""
    var drafts: [RoomRow] { app.state("room.drafts") as? [RoomRow] ?? [] }
    var body: some View {
        Form {
            Section { ZStack(alignment: .leading) {
                RoomArtwork("cloud-bank").scaledToFill()
                Text("Good night,\nvoice room").font(.largeTitle.bold()).padding()
            }.frame(height: 112).clipped() }
            Section("Room cover") { HStack { ForEach(RoomSound.all) { sound in
                Button { cover = sound.id } label: {
                    RoomArtwork(sound.id).scaledToFill().frame(width: 70,height: 65).clipped().cornerRadius(12).overlay(alignment: .bottomTrailing) {
                        if cover == sound.id { Text("✓").foregroundColor(.white).padding(4).background(.teal, in: Circle()) }
                    }
                }.accessibilityLabel(sound.title).buttonStyle(.plain)
            } } }
            Section("Room details") {
                TextField("A name for your room", text: $title).onChange(of: title) { title = String($0.prefix(20)) }
                Picker("Topic", selection: $topic) { ForEach(["Light music","Bedtime stories","Night chat"],id: \.self) { Text($0) } }
                Picker("Visibility when live", selection: $visibility) { ForEach(["Public","Followers only","Only me"],id: \.self) { Text($0) } }
            }
            Section("Room settings") { Toggle("Allow follows",isOn: $follow); Toggle("Allow gifts",isOn: $gifts); Toggle("Allow comments",isOn: $comments) }
            Text("Your microphone starts off.")
            if !error.isEmpty { Text(error).foregroundColor(.red) }
            Button("Open room") { save(live: true) }
            Button("Save private draft") { save(live: false) }
        }.disabled(busy).navigationTitle(id == nil ? "Create a room" : "Edit room draft").onAppear {
            if let id, let d = drafts.first(where: { $0.roomText("id") == id }) {
                title = d.roomText("title"); cover = d.roomText("cover"); topic = d.roomText("topic"); visibility = d.roomText("visibility")
                follow = d.roomFlag("follow"); gifts = d.roomFlag("gifts"); comments = d.roomFlag("comments")
            }
        }
    }
    func save(live: Bool) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Give your room a title."; return }
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                if live {
                    if try await app.api.rows("rooms?id=eq." + operation).isEmpty {
                        let body: RoomRow = ["id":operation,"host_id":app.api.userID,"title":name,"topic":topic,"cover":cover,"visibility":["Public":"public","Followers only":"followers"][visibility] ?? "private","allow_follow":follow,"allow_gifts":gifts,"allow_comments":comments]
                        _ = try await app.api.rest("rooms", method: "POST", body: body)
                    }
                    app.go("rooms.live", operation)
                } else {
                    if let id, !drafts.contains(where: { $0.roomText("id") == id }) { throw MiNaIssue("This draft is no longer available.") }
                    let key = id ?? "draft-" + roomUUID()
                    let draft: RoomRow = ["id":key,"title":name,"topic":topic,"cover":cover,"visibility":visibility,"follow":follow,"gifts":gifts,"comments":comments]
                    try app.save("room.drafts", [draft] + drafts.filter { $0.roomText("id") != key })
                    app.go("rooms.stage", key)
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

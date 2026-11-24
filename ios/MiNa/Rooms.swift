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
    private var entries: [DiscoveryEntry] {
        rooms.map(DiscoveryEntry.init(room:)) + RoomSound.all.map(DiscoveryEntry.init(sound:))
    }
    private var hot: [DiscoveryEntry] {
        let live = entries.filter { $0.live }.sorted { ($0.listeners ?? 0) > ($1.listeners ?? 0) }
        return live + entries.filter { !$0.live }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if home {
                        homeHeader
                        if !followed {
                            Button { app.go("dreams") } label: {
                                NativeArt("home", 7).aspectRatio(700.0 / 288, contentMode: .fit)
                            }
                            .buttonStyle(.plain).accessibilityLabel("Mysterious Dream Space. Record dreams")
                            .padding(.bottom, 10)
                            sectionHeader(2, "Hot Rooms", "rooms.hot")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 0) {
                                ForEach(hot.prefix(2)) { item in
                                    DiscoveryCard(entry: item, featured: true) { open(item) }
                                }
                            }
                            .padding(.bottom, 8)
                            sectionHeader(3, "Recommended", "rooms.recommended")
                            recommendations(Array(entries.prefix(3)))
                            if status == "Live rooms could not load." { statusMessage }
                            draftList
                        } else { standardList }
                    } else if search { searchPage } else if route == "rooms.hot" || route == "rooms.recommended" {
                        recommendations(route == "rooms.hot" ? hot : entries)
                        if !status.isEmpty { statusMessage }
                    } else { standardList }
                }
                .padding(.horizontal, home ? 20 : 16)
                .padding(.bottom, home ? 75 : 12)
                .frame(width: geometry.size.width, alignment: .topLeading)
            }
        }
        .background {
            if home { NativeArt("home", 1).ignoresSafeArea().accessibilityHidden(true) }
            else if search { NativeArt("search",1).ignoresSafeArea().accessibilityHidden(true) }
        }
        .navigationTitle(home ? "" : search ? "Search rooms" : ["rooms.hot":"Hot Rooms", "rooms.recommended":"Recommended", "rooms.sounds":"Soundscapes"][route] ?? "Live rooms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(home || search ? .hidden : .visible, for: .navigationBar)
        .task(id: "\(route)-\(followed)-\(retry)") {
            guard route != "rooms.sounds" else { return }
            rooms = []; status = "Finding rooms…"
            while !Task.isCancelled {
                do {
                    var path = "rooms?closed=eq.false&order=created_at.desc&limit=100"
                    if home || route == "rooms.hot" || route == "rooms.recommended" {
                        let cutoff = roomFilter(roomStamp(Date().addingTimeInterval(-60)))
                        path += "&select=*,room_members(seat)&room_members.last_seen=gte." + cutoff
                    }
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
                    if home { app.didRefreshRoot("rooms") }
                } catch { if Task.isCancelled { return }; rooms = []; status = "Live rooms could not load." }
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }
    private var homeHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach([false, true], id: \.self) { value in
                    if value { Spacer().frame(width: 24) }
                    Button { followed = value } label: {
                        Text(value ? "Followed" : "Voice Rooms")
                            .font(.system(size: value == followed ? 17 : 15, weight: value == followed ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(value == followed ? 1 : 0.72))
                            .frame(width: 104, height: 44)
                            .overlay(alignment: .bottom) {
                                if followed == value { NativeArt("home", 4).frame(width: 104, height: 6).padding(.bottom, 2) }
                            }
                    }.accessibilityAddTraits(followed == value ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button { app.go("rooms.ranks") } label: {
                    NativeArt("home", 5).frame(width: 36, height: 36).frame(width: 44, height: 44, alignment: .trailing)
                }.accessibilityLabel("Open rankings")
            }
            Button { app.go("rooms.search") } label: {
                HStack(spacing: 14) {
                    NativeArt("home", 6).frame(width: 22, height: 22)
                    Text("Search for a voice room").font(.system(size: 14))
                    Spacer()
                }
                .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 40)
                .background(.white.opacity(0.24), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.30)) }
                .frame(minHeight: 44)
            }
        }.buttonStyle(.plain).padding(.bottom, 10)
    }

    private func sectionHeader(_ image: Int, _ label: String, _ page: String) -> some View {
        HStack {
            NativeArt("home", image).scaledToFit().frame(height: 14).accessibilityLabel(label).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { app.go(page) } label: {
                HStack(spacing: 5) { Text("More").font(.system(size: 12)); NativeArt("home", 8).frame(width: 12, height: 12) }
                    .foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel("More " + label)
        }.padding(.horizontal, 3)
    }

    private func open(_ entry: DiscoveryEntry) {
        app.go(entry.live ? "rooms.live" : "rooms.stage", entry.id)
    }

    private func recommendations(_ items: [DiscoveryEntry]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(items) { item in DiscoveryCard(entry: item, featured: false) { open(item) } }
        }
    }

    @ViewBuilder private var draftList: some View {
        if !drafts.isEmpty {
            Text("Your room drafts").font(.headline).padding(.vertical, 10)
            ForEach(Array(drafts.filter { matches($0.roomText("title") + " " + $0.roomText("topic")) }.enumerated()), id: \.offset) { _, draft in
                RoomChoiceRow(cover: draft.roomText("cover"), title: draft.roomText("title"), detail: draft.roomText("topic") + " · Private draft") { app.go("rooms.stage", draft.roomText("id")) }
            }
        }
    }

    private var statusMessage: some View {
        HStack {
            Text(status.isEmpty ? (search && !query.isEmpty ? "No matching live rooms." : "No open rooms right now.") : status)
            if status == "Live rooms could not load." { Button("Retry") { retry += 1 } }
        }.font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
    }

    private var searchPage: some View {
        let results = entries.filter { matches([$0.title,$0.detail,RoomSound.find($0.id)?.topic ?? ""].joined(separator: " ")) }
        return VStack(alignment: .leading,spacing: 12) {
            HStack(spacing: 4) {
                Button { app.back() } label: { NativeArt("search",2).scaledToFit().frame(width: 22,height: 22).frame(width: 44,height: 44) }.accessibilityLabel("Back")
                HStack {
                    NativeArt("search",3).scaledToFit().frame(width: 22,height: 22)
                    TextField("",text: $query,prompt: Text("Search for a voice room").foregroundColor(.white.opacity(0.85))).foregroundColor(.white).submitLabel(.search)
                    Button { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to: nil,from: nil,for: nil) } label: { NativeArt("search",9).scaledToFit().frame(width: 42,height: 40) }.accessibilityLabel("Search")
                }.padding(.leading,12).padding(.trailing,3).background(.white.opacity(0.27),in: Capsule())
            }.buttonStyle(.plain)
            VStack(spacing: 4) {
                NativeArt("search",10).scaledToFit().frame(height: 98)
                Text(query.isEmpty ? "Search rooms and sounds" : results.isEmpty ? "No matching rooms or sounds" : "\(results.count) matching results")
                    .font(.subheadline.weight(.medium)).foregroundColor(Color(red: 0.18,green: 0.27,blue: 0.55))
            }.frame(maxWidth: .infinity).padding(.top,20).padding(.bottom,15)
            Text(query.isEmpty ? "Recommended content" : "Search results").font(.headline)
            recommendations(results)
            draftList
            if status == "Live rooms could not load." { statusMessage }
        }
    }

    private var standardList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if search { TextField("Search by name or topic", text: $query).textFieldStyle(.roundedBorder) }
            if route != "rooms.sounds" {
                Text(followed ? "Followed rooms" : "Live rooms").font(.title3.bold())
                let found = rooms.filter { matches($0.roomText("title") + " " + $0.roomText("topic")) }
                recommendations(found.map(DiscoveryEntry.init(room:)))
                if found.isEmpty { statusMessage }
            }
            if route != "rooms.liveList" {
                Text(followed ? "Saved sounds" : "Listen offline").font(.title3.bold())
                let saved = app.state("room.savedSounds") as? [String] ?? []
                let sounds = RoomSound.all.filter { (!followed || saved.contains($0.id)) && matches([$0.title,$0.detail,RoomSound.find($0.id)?.topic ?? ""].joined(separator: " ")) }
                recommendations(sounds.map(DiscoveryEntry.init(sound:)))
                if sounds.isEmpty { Text(followed ? "Save a soundscape from its listening room." : "No matching soundscapes.") }
                if !followed && route != "rooms.sounds" { draftList }
            }
        }
    }

}

private struct DiscoveryEntry: Identifiable {
    let id: String
    let title: String
    let cover: String
    let detail: String
    let visibility: String
    let live: Bool
    let listeners: Int?
    let started: Date?
    let loop: TimeInterval?

    init(room: RoomRow) {
        id = room.roomText("id")
        title = room.roomText("title")
        cover = room.roomText("cover")
        detail = room.roomText("topic")
        visibility = ["private": "Only me", "followers": "Followers only"][room.roomText("visibility")] ?? "Public room"
        live = true
        listeners = (room["room_members"] as? [RoomRow])?.count
        started = roomDate(room.roomText("created_at"))
        loop = nil
    }

    init(sound: RoomSound) {
        id = sound.id
        title = sound.title
        cover = sound.id
        detail = sound.detail
        visibility = "Offline soundscape"
        live = false
        listeners = nil
        started = nil
        loop = Self.durations[sound.id]
    }

    private static let durations = RoomSound.all.reduce(into: [String: TimeInterval]()) { result, sound in
        guard let url = Bundle.main.url(forResource: sound.id, withExtension: "wav", subdirectory: "Artwork/rooms-extra"),
              let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return }
        result[sound.id] = Double(file.length) / file.fileFormat.sampleRate
    }

    func time(at date: Date) -> String? {
        guard let interval = started.map({ date.timeIntervalSince($0) }) ?? loop else { return nil }
        let t = max(0, Int(interval))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t/3600, t/60%60, t%60)
                         : String(format: "%02d:%02d", t/60, t%60)
    }
}

private struct DiscoveryCard: View {
    let entry: DiscoveryEntry
    let featured: Bool
    let action: () -> Void
    private let ink = Color(red: 0.13, green: 0.17, blue: 0.19)
    private let green = Color(red: 0.0, green: 0.53, blue: 0.26)

    var body: some View {
        Button(action: action) {
            if featured { hotCard } else { listCard }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title + ", " + entry.visibility)
        .accessibilityHint(entry.live ? "Enter voice room" : "Open soundscape")
    }

    private var hotCard: some View {
        Color.clear.aspectRatio(169.0 / 137, contentMode: .fit)
            .overlay {
                RoomArtwork(entry.cover).scaledToFill().blur(radius: 8)
            }
            .overlay(alignment: .top) {
                RoomArtwork(entry.cover).scaledToFit()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    HStack(spacing: 3) {
                        NativeArt("home", entry.live ? 10 : 12).scaledToFit().frame(width: 13, height: 13)
                        Text(entry.listeners.map(String.init) ?? (entry.live ? "Live" : "Offline"))
                        Spacer(minLength: 2)
                        timeLabel.foregroundStyle(Color(red: 0.64, green: 1, blue: 0.63))
                    }.font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(.black.opacity(0.43), in: RoundedRectangle(cornerRadius: 12))
            }.clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var timeLabel: some View {
        if entry.started != nil {
            TimelineView(.periodic(from: .now, by: 1)) { tick in Text(entry.time(at: tick.date) ?? "").monospacedDigit() }
        } else if let time = entry.time(at: .now) { Text(time).monospacedDigit() }
    }

    private var listCard: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 76, height: 76)
                .overlay { RoomArtwork(entry.cover).scaledToFill() }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 3) {
                        NativeArt("home", entry.live ? 11 : 12).frame(width: 13, height: 13)
                        Text(entry.listeners.map(String.init) ?? (entry.live ? "Live" : "Offline"))
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 3).background(.black.opacity(0.45))
                }.clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.system(size: 16, weight: .medium)).foregroundStyle(ink)
                    .padding(.trailing, 58).lineLimit(1)
                Text(entry.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        metadata(14, entry.visibility, Color(red: 0.01, green: 0.47, blue: 0.79))
                        metadata(12, entry.live ? "Voice room" : "Looping audio", green)
                    }
                    Spacer(minLength: 2)
                    NativeArt("home", 15).scaledToFit().frame(width: 71).accessibilityHidden(true)
                }
            }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.87, green: 0.95, blue: 0.97))
        .overlay(alignment: .topTrailing) {
            if entry.started != nil || entry.loop != nil {
                HStack(spacing: 3) { NativeArt("home", 13).frame(width: 12, height: 12); timeLabel }
                    .font(.system(size: 11)).foregroundStyle(Color(red: 0.76, green: 0.4, blue: 0))
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(Color(red: 1, green: 0.98, blue: 0.76), in: Capsule())
            }
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metadata(_ icon: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) { NativeArt("home", icon).frame(width: 12, height: 12); Text(label).lineLimit(1) }
            .font(.system(size: 11)).foregroundStyle(color)
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
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button { app.back() } label: { NativeArt("createRoom",2).scaledToFit().frame(width: 24,height: 24).frame(width: 44,height: 44) }.accessibilityLabel("Back")
                    Spacer(); Text(id == nil ? "Create a room" : "Edit room draft").font(.headline.bold()).foregroundColor(.white).shadow(color: .black.opacity(0.85),radius: 2,y: 1); Spacer(); Color.clear.frame(width: 44,height: 1)
                }
                Spacer().frame(height: 129)
                VStack(alignment: .leading,spacing: 13) {
                    HStack(spacing: 14) {
                        Menu {
                            ForEach(RoomSound.all) { sound in Button(sound.title) { cover = sound.id } }
                        } label: {
                            RoomArtwork(cover).scaledToFill().frame(width: 80,height: 80).clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay { NativeArt("createRoom",5).scaledToFit().frame(width: 18,height: 18).padding(8).background(.black.opacity(0.35),in: Circle()) }
                        }.accessibilityLabel("Choose room cover")
                        VStack(alignment: .leading,spacing: 7) { Text("Room cover").bold(); Text("Choose a cover for your voice room.").font(.caption).foregroundColor(.white.opacity(0.75)) }
                    }
                    Divider().overlay(.white.opacity(0.24))
                    editorLabel(5,"Room title")
                    TextField("",text: $title,prompt: Text("Room title (up to 20 characters)").foregroundColor(.white.opacity(0.6)),axis: .vertical)
                        .lineLimit(2...3).padding(10).background(fieldColor,in: RoundedRectangle(cornerRadius: 8)).onChange(of: title) { title = String($0.prefix(20)) }
                    HStack {
                        editorLabel(4,"Room topic"); Spacer()
                        Menu { ForEach(["Light music","Bedtime stories","Night chat"],id: \.self) { t in Button(t) { topic = t } } }
                            label: { HStack(spacing: 5) { NativeArt("room",4).frame(width: 17,height: 17); Text(topic); Text("›") }.font(.caption).padding(8).background(fieldColor,in: Capsule()) }
                    }
                    HStack(spacing: 5) {
                        editorLabel(13,"Visibility"); Spacer(minLength: 0)
                        ForEach(["Public","Followers only","Only me"],id: \.self) { choice in
                            Button { visibility = choice } label: {
                                Text(choice).font(.system(size: 11,weight: .medium)).padding(.horizontal,6).padding(.vertical,7)
                                    .foregroundColor(visibility == choice ? .black : .white).background(visibility == choice ? Color.mint : fieldColor,in: Capsule()).frame(minHeight: 44)
                            }.accessibilityAddTraits(visibility == choice ? .isSelected : [])
                        }
                    }
                    editorLabel(3,"Room settings")
                    VStack(spacing: 0) {
                        option("Allow follows","Listeners can follow you in the room.",7,$follow)
                        Divider(); option("Allow gifts","Receive gifts from other listeners.",15,$gifts)
                        Divider(); option("Allow comments","Let listeners take part in room chat.",6,$comments)
                    }.padding(.horizontal,10).background(fieldColor,in: RoundedRectangle(cornerRadius: 10))
                }.padding(13).background(Color(red: 0.015,green: 0.19,blue: 0.23),in: RoundedRectangle(cornerRadius: 15))
                    .overlay { RoundedRectangle(cornerRadius: 15).stroke(Color.yellow.opacity(0.58),lineWidth: 1) }
                Button(busy ? "Opening…" : "Open room") { save(live: true) }.buttonStyle(RoomCapsuleStyle()).padding(.horizontal,27).padding(.top,8)
                Button("Save private draft") { save(live: false) }.frame(minHeight: 44)
                Text("Your microphone starts off.").font(.caption)
                if !error.isEmpty { Text(error).font(.callout) }
            }.padding(.horizontal,19).padding(.bottom,18)
        }.background { NativeArt("createRoom",1).ignoresSafeArea().accessibilityHidden(true) }
        .tint(.mint).foregroundColor(.white).buttonStyle(.plain).disabled(busy).toolbar(.hidden,for: .navigationBar).onAppear {
            if let id, let d = drafts.first(where: { $0.roomText("id") == id }) {
                title = d.roomText("title"); cover = d.roomText("cover"); topic = d.roomText("topic"); visibility = d.roomText("visibility")
                follow = d.roomFlag("follow"); gifts = d.roomFlag("gifts"); comments = d.roomFlag("comments")
            }
        }
    }
    private var fieldColor: Color { Color(red: 0.014,green: 0.15,blue: 0.12) }
    private func editorLabel(_ index: Int,_ title: String) -> some View {
        HStack(spacing: 6) { NativeArt("createRoom",index).scaledToFit().frame(width: 15,height: 15); Text(title).font(.subheadline.bold()) }
    }
    private func option(_ name: String,_ detail: String,_ icon: Int,_ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { HStack {
            NativeArt("createRoom",icon).scaledToFit().frame(width: 16,height: 16)
            VStack(alignment: .leading,spacing: 4) { Text(name).font(.subheadline); Text(detail).font(.caption2).foregroundColor(.white.opacity(0.72)) }
        } }.padding(.vertical,7)
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

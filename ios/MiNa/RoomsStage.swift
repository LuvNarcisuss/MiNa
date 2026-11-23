import SwiftUI
import AVFoundation

enum RoomPanel: String, Identifiable {
    case host = "Room details", audience = "Room audience", mic = "Microphone seats", music = "Music on demand", gift = "Gifts", share = "Share with friends", exit = "Leave room?", chat = "Room chat", ranking = "Rankings"
    var id: String { rawValue }
}

struct RoomStageFrame<Bottom: View>: View {
    let title: String
    let topic: String
    let cover: String
    let host: String
    let hostStatus: String
    var audience: Int?
    var runtime: Int?
    var seats: [Int:String] = [:]
    var portraits: [Int:URL] = [:]
    var gifts = true
    let open: (RoomPanel,Int) -> Void
    @ViewBuilder let bottom: () -> Bottom
    func tool(_ label: String,_ index: Int,_ panel: RoomPanel) -> some View {
        Button { open(panel,1) } label: { NativeArt("room",index).scaledToFit().frame(width: 24,height: 24).frame(width: 44,height: 44).background(.white.opacity(0.15), in: Circle()) }.accessibilityLabel(label)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Button { open(.host,0) } label: {
                        HStack { RoomArtwork(cover).scaledToFill().frame(width: 36,height: 36).clipped().cornerRadius(10); Text(title).font(.headline).multilineTextAlignment(.leading) }
                    }
                    Spacer()
                    Button { open(.audience,1) } label: { HStack { NativeArt("room",3).frame(width: 20,height: 20); if let audience { Text("\(audience)") } }.frame(minWidth: 44,minHeight: 44) }.accessibilityLabel("Room audience")
                    tool("Invite friends",2,.share); tool("Leave room",1,.exit)
                }
                HStack { Text(topic); Spacer(); Button("Rankings ›") { open(.ranking,1) }; if let runtime { Text("\(runtime) min") } }.font(.subheadline)
                Button { open(.host,0) } label: {
                    VStack {
                        if let portrait = portraits[0] { AsyncImage(url: portrait) { image in image.resizable().scaledToFill() } placeholder: { RoomArtwork(cover) }.frame(width: 72,height: 72).clipShape(Circle()) }
                        else { RoomArtwork(cover).scaledToFill().frame(width: 72,height: 72).clipShape(Circle()) }
                        Text(host).bold(); Text(hostStatus).font(.caption)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()),count: 4), spacing: 14) {
                    ForEach(1...8,id: \.self) { seat in
                        Button { open(.mic,seat) } label: { VStack {
                            ZStack {
                                Circle().fill(.white.opacity(0.17))
                                if let portrait = portraits[seat] { AsyncImage(url: portrait) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }.clipShape(Circle()) }
                                else if let name = seats[seat] { Text(String(name.prefix(2))).bold() }
                                else { NativeArt("room",7).scaledToFit().padding(12) }
                            }.frame(width: 44,height: 44)
                            Text(seats[seat] ?? "Mic \(seat)").font(.caption).lineLimit(1)
                        } }
                    }
                }
                bottom()
                HStack { Button("Room audience") { open(.audience,1) }; Spacer(); tool("Microphone settings",15,.mic); tool("Choose a gift",19,.gift).disabled(!gifts); tool("Music on demand",16,.music) }
            }.padding()
        }.background { GeometryReader { geo in
            ZStack { Color(red: 0.03,green: 0.12,blue: 0.24); RoomArtwork("moonlit-sea").scaledToFill().opacity(0.42) }
                .frame(width: geo.size.width,height: geo.size.height).clipped()
        }.ignoresSafeArea() }.foregroundColor(.white).buttonStyle(.plain)
    }
}

struct RoomLocalStage: View {
    @EnvironmentObject var app: MiNaAppModel
    @Environment(\.scenePhase) var phase
    let id: String
    @StateObject private var player = RoomPlayer()
    @State private var panel: RoomPanel?
    @State private var seat = 1
    @State private var error = ""
    @State private var gift = 0
    @State private var quantity = 1
    var draft: RoomRow? { (app.state("room.drafts") as? [RoomRow])?.first { $0.roomText("id") == id } }
    var sound: RoomSound? { RoomSound.find(id) ?? draft.map { RoomSound.find($0.roomText("cover")) ?? RoomSound.all[0] } }
    var saved: [String] { app.state("room.savedSounds") as? [String] ?? [] }
    var body: some View {
        Group {
            if let sound {
                let title = draft?.roomText("title") ?? sound.title
                RoomStageFrame(title: title,topic: draft?.roomText("topic") ?? sound.topic,cover: sound.id,host: draft == nil ? "Host seat" : (app.state("profile") as? RoomRow)?.roomText("name") ?? "You",hostStatus: draft == nil ? "Unoccupied" : "Draft owner",open: { next, n in seat = n; if next == .ranking { app.go("rooms.ranks") } else { panel = next } }) {
                    VStack(spacing: 12) {
                        Text("ON THIS DEVICE").font(.caption)
                        Text(RoomSound.find(player.playing)?.title ?? sound.title).font(.title2.bold())
                        Text(RoomSound.find(player.playing)?.detail ?? sound.detail)
                        HStack {
                            Button(player.playing.isEmpty ? "Play soundscape" : "Pause sound") { if player.playing.isEmpty { player.play(sound) } else { player.stop() } }
                            if draft != nil { Button("Edit draft") { app.go("rooms.create",id) } }
                            else { Button(saved.contains(id) ? "Saved ✓" : "Save sound") {
                                do { try app.save("room.savedSounds", saved.contains(id) ? saved.filter { $0 != id } : saved + [id]) } catch { self.error = error.localizedDescription }
                            } }
                        }.buttonStyle(.borderedProminent)
                        Text(error + player.error).font(.caption)
                    }.frame(maxWidth: .infinity).padding().background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
                }
                .sheet(item: $panel) { item in
                    NavigationStack { Form {
                        switch item {
                        case .host:
                            Text(title); Text(draft == nil ? "Offline soundscape · No live host" : "Private draft · " + (draft?.roomText("visibility") ?? ""))
                            Button(draft == nil ? "Browse soundscapes" : "View your profile") { if draft == nil { panel = .music } else { panel = nil; app.go("profile") } }
                        case .audience, .chat: Text("No live audience. Participants and comments appear in live rooms.")
                        case .share: Text("This room is on your device. Open a live room to invite a friend.")
                        case .mic: Text("Microphone seat \(seat)"); Text("Speaking and the seat queue require a live connection.")
                            Button("Browse sounds") { panel = .music }
                        case .music:
                            ForEach(RoomSound.all) { s in RoomChoiceRow(cover: s.id,title: s.title,detail: player.playing == s.id ? "Pause" : "Play · " + s.detail) { if player.playing == s.id { player.stop() } else { player.play(s) } } }
                            if !player.error.isEmpty { Text(player.error) }
                        case .gift:
                            Picker("Gift",selection: $gift) { ForEach(RoomGifts.names.indices,id: \.self) { Text(RoomGifts.names[$0]).tag($0) } }
                            Stepper("Quantity: \(quantity)",value: $quantity,in: 1...99)
                            Text("No live recipient · Price unavailable")
                            Button("Open wallet") { panel = nil; app.go("wallet") }
                        case .exit: Text(draft == nil ? "Audio will stop when you leave." : "Your draft will stay on this device."); Button("Leave room") { player.stop(); panel = nil; app.go("rooms") }
                        case .ranking: EmptyView()
                        }
                    }.navigationTitle(item.rawValue).navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { panel = nil } } }
                }
            } else { Text("This room is unavailable.") }
        }.onChange(of: phase) { if $0 != .active { player.stop() } }.onDisappear { player.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in player.stop() }
    }
}

struct RoomRankings: View {
    @EnvironmentObject var app: MiNaAppModel
    let room: String?
    @State private var gift = false
    @State private var last = false
    @State private var rows: [RoomRow] = []
    @State private var titles: [String:String] = [:]
    @State private var days = Set<String>()
    @State private var ready = false
    @State private var busy = false
    @State private var error = ""
    @State private var version = 0
    var dates: [Date] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = cal.startOfDay(for: Date())
        let offset = (cal.component(.weekday,from: day) + 5) % 7 + (last ? 7 : 0)
        return (0..<7).map { day.addingTimeInterval(Double($0-offset)*86400) }
    }
    func day(_ date: Date) -> String { String(roomStamp(date).prefix(10)) }
    var body: some View {
        ScrollView { VStack(alignment: .leading,spacing: 16) {
            Picker("Ranking category",selection: $gift) { Text("Room ranking").tag(false); Text("Gift ranking").tag(true) }.pickerStyle(.segmented)
            Picker("Ranking period",selection: $last) { Text("This week").tag(false); Text("Last week").tag(true) }.pickerStyle(.segmented)
            Text(day(dates[0]) + " – " + day(dates[6]) + " UTC").font(.caption)
            HStack(alignment: .bottom) { ForEach([2,1,3],id: \.self) { number in
                VStack {
                    NativeArt("rank",[11,9,10][number-1]).scaledToFit().frame(height: number == 1 ? 82 : 60)
                    Text("#\(number)").bold()
                    if rows.count >= number {
                        let row = rows[number-1]
                        Text(titles[row.roomText("room_id")] ?? "Room").font(.caption.bold())
                        Text("\(row["score"] as? Int ?? 0) " + (gift ? "coins" : "check-ins")).font(.caption2)
                    } else { Text("—") }
                }.frame(maxWidth: .infinity)
            } }
            ForEach(Array(rows.dropFirst(3).enumerated()),id: \.offset) { i,row in HStack { Text("\(i+4). " + (titles[row.roomText("room_id")] ?? "Room")); Spacer(); Text("\(row["score"] as? Int ?? 0)") } }
            if rows.isEmpty && error.isEmpty { Text(ready ? "No ranked rooms for this period." : "Loading rankings…") }
            if !error.isEmpty { Text(error); Button("Retry") { version += 1 } }
            if let room {
                Text("This room").font(.headline)
                Text(rows.firstIndex(where: { $0.roomText("room_id") == room }).map { "Rank \($0+1)" } ?? "Unranked")
                if !gift {
                    HStack { ForEach(dates,id: \.self) { d in Text(days.contains(day(d)) ? "✓" : String(day(d).suffix(2))).frame(maxWidth: .infinity) } }
                    if !last { Button(days.contains(day(Date())) ? "Checked in today" : "Check in today") {
                        busy = true
                        Task { defer { busy = false }; do { _ = try await app.api.rest("rpc/check_in", method: "POST",body: ["target_room":room]); version += 1 } catch { self.error = error.localizedDescription } }
                    }.disabled(!ready || busy || days.contains(day(Date()))) }
                }
            } else { Button("Find a room to check in") { app.go("rooms.liveList") } }
        }.padding() }.navigationTitle("Rankings").task(id: "\(gift)-\(last)-\(version)") {
            ready = false; rows = []; days = []; error = ""
            do {
                let start = day(dates[0])
                guard let ranks = try await app.api.rest("rpc/room_rankings",method: "POST",body: ["start_day":start,"gift_ranking":gift] as RoomRow) as? [RoomRow] else {
                    throw MiNaIssue("Rankings could not load.")
                }
                let ids = ranks.map { $0.roomText("room_id") }.joined(separator: ",")
                let rooms = ids.isEmpty ? [] : try await app.api.rows("rooms?select=id,title&id=in.(" + ids + ")")
                var checkins: [RoomRow] = []
                if let room { checkins = try await app.api.rows("room_checkins?select=day&room_id=eq." + room + "&user_id=eq." + app.api.userID + "&day=gte." + start) }
                try Task.checkCancellation()
                titles = Dictionary(uniqueKeysWithValues: rooms.map { ($0.roomText("id"),$0.roomText("title")) })
                rows = ranks; days = Set(checkins.map { $0.roomText("day") }); ready = true
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

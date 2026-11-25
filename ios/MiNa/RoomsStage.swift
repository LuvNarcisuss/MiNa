import SwiftUI
import AVFoundation

enum RoomPanel: String, Identifiable {
    case host = "Room details", listener = "Audience information", audience = "Room audience", mic = "Microphone seats", music = "Music on demand", gift = "Gifts", share = "Share with friends", exit = "Leave room?", chat = "Room chat", ranking = "Rankings"
    var id: String { rawValue }
}

struct RoomCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).foregroundColor(Color(red: 0.025,green: 0.18,blue: 0.19))
            .frame(maxWidth: .infinity,minHeight: 46)
            .background(LinearGradient(colors: [.mint, Color(red: 0.31,green: 0.74,blue: 1)],startPoint: .leading,endPoint: .trailing),in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension RoomPanel {
    var artwork: String {
        switch self {
        case .host: return "host"
        case .listener: return "listener"
        case .audience,.chat: return "audience"
        case .mic: return "queue"
        case .gift: return "gift"
        case .music: return "music"
        case .share: return "share"
        case .exit: return "exit"
        case .ranking: return "rank"
        }
    }
    var fraction: CGFloat {
        switch self {
        case .exit: return 0.35
        case .music: return 1
        case .ranking: return 0.82
        case .gift: return 0.61
        default: return 0.55
        }
    }
}

private struct RoomPanelOutline: Shape {
    let drawer: Bool
    func path(in rect: CGRect) -> Path {
        if drawer { return Path(rect) }
        return Path(UIBezierPath(roundedRect: rect,byRoundingCorners: [.topLeft,.topRight],cornerRadii: CGSize(width: 22,height: 22)).cgPath)
    }
}

extension View {
    func roomOverlay<PanelContent: View>(_ selection: Binding<RoomPanel?>, @ViewBuilder content: @escaping (RoomPanel) -> PanelContent) -> some View {
        self.accessibilityHidden(selection.wrappedValue != nil)
            .overlay { if let item = selection.wrappedValue {
                GeometryReader { geo in
                    let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                        .first(where: { $0.activationState == .foregroundActive })?.keyWindow
                    let visible = geo.frame(in: .global)
                    let topInset = max(geo.safeAreaInsets.top,min(window?.safeAreaInsets.top ?? 0,max(0,visible.minY)))
                    let bottomInset = max(geo.safeAreaInsets.bottom,min(window?.safeAreaInsets.bottom ?? 0,max(0,(window?.bounds.maxY ?? visible.maxY) - visible.maxY)))
                    let giftBottomInset = item == .gift ? window.map {
                        max(0, visible.maxY - ($0.bounds.maxY - $0.safeAreaInsets.bottom))
                    } ?? geo.safeAreaInsets.bottom : 0
                    ZStack(alignment: item == .music ? .trailing : .bottom) {
                        Color.black.opacity(0.46).ignoresSafeArea().onTapGesture { selection.wrappedValue = nil }.accessibilityHidden(true)
                        VStack(alignment: .leading,spacing: 0) {
                            HStack {
                                if item == .music {
                                    Button { selection.wrappedValue = nil } label: { NativeArt("music",2).scaledToFit().frame(width: 27,height: 27) }.frame(width: 44,height: 44).accessibilityLabel("Close")
                                }
                                Text(item.rawValue).font(.system(size: 19,weight: .heavy,design: .rounded))
                                    .foregroundColor(Color(red: 0.06,green: 0.27,blue: 0.23))
                                Spacer()
                                if item != .music {
                                    Button { selection.wrappedValue = nil } label: { NativeArt(item == .ranking ? "host" : item.artwork,item == .exit ? 2 : 3).scaledToFit().frame(width: 22,height: 22).frame(width: 44,height: 44) }.accessibilityLabel("Close")
                                }
                            }.padding(.horizontal,14).padding(.top,6)
                            content(item).frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .topLeading)
                        }
                        .frame(width: item == .music ? geo.size.width * 0.78 : geo.size.width,height: geo.size.height * item.fraction)
                        .background {
                            // Extend only the paint into system areas. The panel's controls keep their safe-area frame.
                            GeometryReader { bounds in
                                let top = item == .music ? topInset : 0
                                let bottom = bottomInset + giftBottomInset
                                ZStack {
                                    Color(red: 0.91,green: 0.99,blue: 0.99)
                                    NativeArt(item == .ranking ? "audience" : item.artwork,1)
                                }
                                .frame(width: bounds.size.width,height: bounds.size.height + top + bottom)
                                .clipShape(RoomPanelOutline(drawer: item == .music))
                                .offset(y: -top)
                            }.allowsHitTesting(false)
                        }
                        .padding(.bottom, giftBottomInset)
                        .accessibilityAddTraits(.isModal).accessibilityAction(.escape) { selection.wrappedValue = nil }
                    }.frame(width: geo.size.width,height: geo.size.height)
                }.environment(\.colorScheme,.light)
            } }
    }
}

struct RoomPanelList<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView { VStack(alignment: .leading,spacing: 12) { content() }
            .frame(maxWidth: .infinity,alignment: .leading).padding(.horizontal,16).padding(.bottom,20)
        }.foregroundColor(Color(red: 0.09,green: 0.17,blue: 0.18))
    }
}

struct RoomEmptyPanel: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 9) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical,26).padding(.horizontal,12)
            .background(.white.opacity(0.8),in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RoomMusicRow: View {
    let sound: RoomSound
    let button: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                NativeArt("music",3).scaledToFit().frame(width: 48,height: 48)
                VStack(alignment: .leading,spacing: 5) { Text(sound.title).font(.subheadline.bold()); Text("Free soundscape").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 1)
                Text(button).font(.caption.bold()).foregroundColor(.black).padding(.horizontal,8).padding(.vertical,6).background(.mint.gradient,in: Capsule())
            }.padding(8).frame(maxWidth: .infinity).background(.white,in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
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
    var hostPortrait: URL? = nil
    var portraits: [Int:URL] = [:]
    var safetyMenu: AnyView?
    var participants: [RoomParticipant] = []
    var selectParticipant: ((String) -> Void)?
    let open: (RoomPanel,Int) -> Void
    @ViewBuilder let bottom: () -> Bottom
    func tool(_ label: String,_ index: Int,_ panel: RoomPanel) -> some View {
        Button { open(panel,1) } label: {
            NativeArt("room",index).scaledToFit().frame(width: index >= 15 ? 36 : 17,height: index >= 15 ? 36 : 17)
                .frame(width: index >= 15 ? 44 : 33,height: index >= 15 ? 44 : 26)
                .background(index >= 15 ? Color.clear : .white.opacity(0.2),in: Capsule()).frame(minWidth: 44,minHeight: 44)
        }.accessibilityLabel(label)
    }
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 680
            let spacing: CGFloat = compact ? 3 : 7
            let hostSize: CGFloat = compact ? 56 : 76
            let seatSize: CGFloat = compact ? 36 : 46
            VStack(alignment: .leading, spacing: spacing) {
                HStack(spacing: 1) {
                    Button { open(.host,0) } label: {
                        HStack(spacing: 8) {
                            RoomArtwork(cover).scaledToFill().frame(width: 40,height: 40).clipShape(Circle())
                            VStack(alignment: .leading,spacing: 3) { Text(title).font(.subheadline.bold()).lineLimit(2); Text(hostStatus).font(.caption).foregroundColor(.white.opacity(0.74)) }
                        }
                    }
                    Spacer(minLength: 0)
                    Button { open(.audience,1) } label: { HStack(spacing: 2) { NativeArt("room",3).frame(width: 13,height: 13); if let audience { Text("\(audience)").font(.caption) } }.padding(6).background(.white.opacity(0.2),in: Capsule()).frame(minWidth: 44,minHeight: 44) }.accessibilityLabel("Room audience")
                    tool("Invite friends",2,.share); tool("Leave room",1,.exit)
                }
                HStack { NativeArt("room",4).frame(width: 18,height: 18); Text(topic).font(.caption).lineLimit(1); Spacer() }
                HStack {
                    Button { open(.ranking,1) } label: { NativeArt("room",14).frame(width: 33,height: 24).frame(width: 44,height: 44,alignment: .leading) }.accessibilityLabel("Rankings")
                    Spacer()
                    if let safetyMenu { safetyMenu }
                    if let runtime { HStack { NativeArt("room",13).frame(width: 14,height: 14); Text("\(runtime) min").font(.caption) }.padding(6).background(.white.opacity(0.2),in: Capsule()) }
                }
                Button { open(.host,0) } label: {
                    VStack(spacing: 4) {
                        ZStack { Circle().fill(.teal.opacity(0.45))
                            if let portrait = hostPortrait { CloudPortraitImage(url: portrait) { image in image.resizable().scaledToFill() } placeholder: { RoomArtwork(cover) }.frame(width: hostSize - 10,height: hostSize - 10).clipShape(Circle()) }
                            else { RoomArtwork(cover).scaledToFill().frame(width: hostSize - 10,height: hostSize - 10).clipShape(Circle()) }
                        }.frame(width: hostSize,height: hostSize)
                        Text(host).font(.headline).lineLimit(1); Text(hostStatus).font(.caption).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                }
                if !participants.isEmpty {
                    Text("Listeners & contributors").font(.subheadline.bold())
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(participants.prefix(4)) { person in
                            Button { selectParticipant?(person.id) } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        Circle().fill(.white.opacity(0.18))
                                        Text(String(person.name.prefix(1))).bold()
                                        if let url = person.portrait {
                                            CloudPortraitImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                                        }
                                    }.frame(width: compact ? 28 : 34, height: compact ? 28 : 34).clipShape(Circle())
                                    Text(person.name).font(.caption.bold()).lineLimit(1)
                                    Text(person.role).font(.caption2).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.white.opacity(0.82))
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).accessibilityLabel(person.name + ", " + person.role)
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()),count: 4),spacing: spacing) {
                    ForEach(1...8,id: \.self) { seat in
                        Button { open(.mic,seat) } label: { VStack(spacing: 5) {
                            ZStack {
                                Circle().fill(.white.opacity(0.16)).overlay { Circle().stroke(.white.opacity(0.20)) }
                                if let portrait = portraits[seat] { CloudPortraitImage(url: portrait) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }.clipShape(Circle()) }
                                else if let name = seats[seat] { Text(String(name.prefix(2))).bold() }
                                else { NativeArt("room",7).scaledToFit().padding(13) }
                            }.frame(width: seatSize,height: seatSize)
                            Text(seats[seat] ?? "Mic \(seat)").font(.caption).lineLimit(1)
                        } }.accessibilityLabel(seats[seat] ?? "Microphone seat \(seat)")
                    }
                }
                GeometryReader { space in
                    bottom().frame(maxWidth: .infinity, maxHeight: space.size.height, alignment: .bottomLeading)
                }
                .frame(minHeight: selectParticipant == nil ? 0 : 90)
                .clipped()
                HStack(spacing: 4) {
                    Button { open(.chat,1) } label: {
                        HStack { NativeArt("room",18).frame(width: 21,height: 21); Text("Room chat").font(.caption); Spacer(); NativeArt("room",20).scaledToFit().frame(width: 36,height: 29) }
                            .padding(.horizontal,7).frame(height: 36).background(.white.opacity(0.23),in: Capsule())
                    }.accessibilityLabel("Room chat")
                    tool("Microphone settings",15,.mic); tool("Choose a gift",19,.gift); tool("Music on demand",16,.music)
                }
                .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 16).padding(.vertical, spacing)
            .frame(width: geo.size.width, height: geo.size.height)
            .background { ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.015,green: 0.08,blue: 0.2), Color(red: 0.07,green: 0.18,blue: 0.34)],startPoint: .top,endPoint: .bottom)
                RoomArtwork("moonlit-sea").scaledToFill().frame(width: geo.size.width,height: geo.size.height * 0.35).clipped().mask(LinearGradient(colors: [.clear,.black,.black],startPoint: .top,endPoint: .bottom))
            }.ignoresSafeArea() }
        }.foregroundColor(.white).buttonStyle(.plain).toolbar(.hidden,for: .navigationBar)
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
                RoomStageFrame(title: title,topic: draft?.roomText("topic") ?? sound.topic,cover: sound.id,host: draft == nil ? "Host seat" : (app.state("profile") as? RoomRow)?.roomText("name") ?? "You",hostStatus: draft == nil ? "Unoccupied" : "Draft owner",open: { next, n in seat = n; panel = next }) {
                    VStack(spacing: 12) {
                        Text(RoomSound.find(player.playing)?.title ?? sound.title).font(.title2.bold())
                        Text(RoomSound.find(player.playing)?.detail ?? sound.detail)
                        HStack {
                            Button(player.playing.isEmpty ? "Play soundscape" : "Pause sound") { if player.playing.isEmpty { player.play(sound) } else { player.stop() } }
                            if draft != nil { Button("Edit draft") { app.go("rooms.create",id) } }
                            else { Button(saved.contains(id) ? "Saved ✓" : "Save sound") {
                                do { try app.save("room.savedSounds", saved.contains(id) ? saved.filter { $0 != id } : saved + [id]) } catch { self.error = error.localizedDescription }
                            } }
                        }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity).padding().background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
                }
                .roomOverlay($panel) { item in
                    if item == .ranking { RoomRankings(room: nil) } else { RoomPanelList {
                        switch item {
                        case .host:
                            HStack(spacing: 12) { RoomArtwork(sound.id).scaledToFill().frame(width: 50,height: 50).clipShape(Circle()); Text(title).bold() }
                            Text(draft == nil ? "Soundscape · No live host" : "Private draft · " + (draft?.roomText("visibility") ?? ""))
                            Button(draft == nil ? "Browse soundscapes" : "View your profile") { if draft == nil { panel = .music } else { panel = nil; app.go("profile") } }.buttonStyle(RoomCapsuleStyle())
                        case .audience, .chat: RoomEmptyPanel(title: "No live audience",detail: "Participants and comments appear in live rooms.")
                        case .share: RoomEmptyPanel(title: "This soundscape has no live room",detail: "Open a live room to invite a friend.")
                        case .mic: HStack { NativeArt("queue",7).scaledToFit().frame(width: 60,height: 60); Text("Microphone seat \(seat)").bold() }; RoomEmptyPanel(title: "Microphone off",detail: "Open a live room to request a seat or join the queue.")
                            Button("Browse sounds") { panel = .music }.buttonStyle(RoomCapsuleStyle())
                        case .music:
                            ForEach(RoomSound.all) { s in RoomMusicRow(sound: s,button: player.playing == s.id ? "Pause" : "Play") { if player.playing == s.id { player.stop() } else { player.play(s) } } }
                        case .gift:
                            RoomGiftCatalog(choices: Array(RoomGifts.names.indices),selected: gift,price: { _ in nil },select: { gift = $0 })
                            Stepper("Quantity: \(quantity)",value: $quantity,in: 1...99)
                            Text("No live recipient · Price unavailable")
                            Button("Open wallet") { panel = nil; app.go("wallet") }
                        case .exit: Text(draft == nil ? "Audio will stop when you leave." : "Your draft will stay on this device."); Button("Leave room") { player.stop(); panel = nil; app.go("rooms") }.buttonStyle(RoomCapsuleStyle())
                            Button("Keep listening") { panel = nil }.frame(maxWidth: .infinity,minHeight: 44)
                        case .ranking,.listener: EmptyView()
                        }
                    } }
                }
            } else { Color.clear.minaAlert("This room is unavailable.") }
        }.minaAlert(error).minaAlert(player.error).onChange(of: phase) { if $0 != .active { player.stop() } }.onDisappear { player.stop() }
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
            HStack(spacing: 0) {
                ForEach([false,true],id: \.self) { value in
                    Button { gift = value } label: {
                        Text(value ? "Gift Ranking" : "Room Ranking").font(.system(size: 20,weight: .heavy,design: .rounded)).foregroundColor(gift == value ? .teal : .teal.opacity(0.60))
                            .frame(maxWidth: .infinity,minHeight: 52).background(gift == value ? Color.white.opacity(0.66) : Color.mint.opacity(0.25),in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityAddTraits(gift == value ? .isSelected : [])
                }
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(last ? "Last week" : "Time remaining").font(.caption.bold())
                    if last { Text(day(dates[0]) + " UTC").font(.caption) }
                    else { Text(dates[6].addingTimeInterval(86400),style: .relative).font(.caption) }
                }; Spacer()
                Picker("Ranking period",selection: $last) { Text("This week").tag(false); Text("Last week").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 180)
            }
            HStack(alignment: .bottom,spacing: 0) { ForEach([2,1,3],id: \.self) { number in
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(.white.opacity(0.78))
                        NativeArt("rank",[11,9,10][number-1]).scaledToFit().padding(14)
                    }.frame(width: number == 1 ? 78 : 62,height: number == 1 ? 78 : 62)
                    NativeArt("rank",[13,14,12][number-1]).scaledToFit().frame(height: 25).padding(.top,-8)
                    if rows.count >= number {
                        let row = rows[number-1]
                        Text(titles[row.roomText("room_id")] ?? "Room").font(.caption.bold())
                        Text("\(row["score"] as? Int ?? 0) " + (gift ? "coins" : "check-ins")).font(.caption2)
                    } else { Text("Unfilled").font(.caption).foregroundStyle(.secondary); Text("—").font(.caption) }
                }.padding(.bottom,number == 1 ? 42 : 20).frame(maxWidth: .infinity)
            } }.padding(.top,12).background(alignment: .bottom) { NativeArt("rank",5).scaledToFit().accessibilityHidden(true) }
            ForEach(Array(rows.dropFirst(3).enumerated()),id: \.offset) { i,row in HStack { Text("\(i+4). " + (titles[row.roomText("room_id")] ?? "Room")); Spacer(); Text("\(row["score"] as? Int ?? 0)") } }
            if rows.isEmpty && error.isEmpty { Text(ready ? "No ranked rooms for this period." : "Loading rankings…") }
            if !error.isEmpty { Button("Retry") { error = ""; version += 1 } }
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
            } else { Button("Find a room to check in") { app.go("rooms.liveList") }.buttonStyle(RoomCapsuleStyle()) }
        }.padding() }.background { ZStack { Color(red: 0.9,green: 0.99,blue: 1); NativeArt("rank",2) }.ignoresSafeArea() }.minaAlert(error).navigationTitle("Rankings").navigationBarTitleDisplayMode(.inline).task(id: "\(gift)-\(last)-\(version)") {
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

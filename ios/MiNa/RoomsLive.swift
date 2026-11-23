import SwiftUI
import AVFoundation
import AVKit

private struct RoomAudioOutput: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

struct RoomLiveView: View {
    @EnvironmentObject var app: MiNaAppModel
    @Environment(\.scenePhase) var phase
    let id: String
    @StateObject private var session = NativeRoomSession()
    @StateObject private var player = RoomPlayer()
    @State private var panel: RoomPanel?
    @State private var seat = 1
    @State private var message = ""
    @State private var ops: [String:String] = [:]
    @State private var busy = false
    @State private var followed: Bool?
    @State private var listen = false
    @State private var retry = 0
    @State private var interrupted = false
    var me: String { app.api.userID.lowercased() }
    var hostID: String { session.room?.roomText("host_id") ?? "" }
    var track: RoomSound? { RoomSound.find(session.room?.roomText("music_track") ?? "") }
    var playKey: String { [track?.id ?? "",session.room?.roomText("music_started_at") ?? "",String(listen),String(session.active)].joined(separator: "|") }
    var resumeKey: String { "room.resumeGift." + id }
    var body: some View {
        Group {
            if let room = session.room {
                let members = session.members.filter { $0["seat"] is Int }
                let seats = members.reduce(into: [Int:String]()) { result,row in if let n = row["seat"] as? Int { result[n] = session.name(row.roomText("user_id")) } }
                let portraits = members.reduce(into: [Int:URL]()) { result,row in if let n = row["seat"] as? Int { result[n] = session.pictures[row.roomText("user_id")] } }
                RoomStageFrame(title: room.roomText("title"),topic: room.roomText("topic"),cover: room.roomText("cover"),host: session.name(hostID),hostStatus: seats[0] == nil ? "Host away" : "Host",audience: session.active ? session.members.count : nil,runtime: max(0,Int(-(roomDate(room.roomText("created_at")) ?? Date()).timeIntervalSinceNow / 60)),seats: seats,portraits: portraits,gifts: room.roomFlag("allow_gifts") && session.active,open: { next,n in seat = n; panel = next }) {
                    VStack(alignment: .leading,spacing: 10) {
                        Text(session.active ? (session.connections > 0 ? "Voice connected · \(session.connections) peers" : "In room · No voice connection yet") : session.status)
                        Text("Microphone: " + session.mic).font(.caption)
                        ForEach(Array(session.messages.suffix(3).enumerated()),id: \.offset) { _,row in Text(chatText(row)).font(.subheadline) }
                        Button("Room chat") { panel = .chat }.buttonStyle(.bordered)
                        if !session.notice.isEmpty { Text(session.notice).font(.caption) }
                    }.frame(maxWidth: .infinity,alignment: .leading).padding().background(.black.opacity(0.35),in: RoundedRectangle(cornerRadius: 16))
                }
            } else { VStack(spacing: 16) { Text(session.status); if session.status == "Reconnecting…" { Button("Retry") { session.leave(app.api,id); retry += 1 } }; Button("Back to rooms") { app.go("rooms") } } }
        }
        .navigationBarBackButtonHidden(session.room != nil)
        .task(id: "\(phase == .background)-\(interrupted)-\(retry)") {
            if phase != .background && !interrupted { await session.run(app.api,id) }
        }
        .onChange(of: phase) { if $0 == .background { session.leave(app.api,id); player.stop(); listen = false } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue == AVAudioSession.InterruptionType.began.rawValue {
                interrupted = true; session.leave(app.api,id); player.stop(); listen = false
            } else { interrupted = false }
        }
        .onReceive(Timer.publish(every: 3,on: .main,in: .common).autoconnect()) { _ in session.watchdog() }
        .onDisappear { session.leave(app.api,id); player.stop() }
        .onAppear { if let stamp = app.state(resumeKey) as? Double, Date().timeIntervalSince1970 - stamp < 600 {
            panel = .gift; try? app.save(resumeKey,nil)
        } }
        .task(id: hostID) { guard !hostID.isEmpty, !session.host else { return }; followed = nil
            do { let rows = try await app.api.rows("follows?follower_id=eq." + me + "&followed_id=eq." + hostID); try Task.checkCancellation(); followed = !rows.isEmpty } catch { }
        }
        .onChange(of: playKey) { _ in
            if listen, session.active, let track { player.play(track,from: roomDate(session.room?.roomText("music_started_at") ?? "")) } else { player.stop() }
        }
        .sheet(item: $panel) { next in
            NavigationStack {
                Group {
                    switch next {
                    case .ranking: RoomRankings(room: id)
                    case .gift: RoomGifts(id: id,session: session,openWallet: {
                        try app.save(resumeKey,Date().timeIntervalSince1970); panel = nil; app.go("wallet")
                    })
                    case .share: RoomInvitations(id: id)
                    default: Form {
                        controls(next)
                        if !session.notice.isEmpty { Text(session.notice) }
                    }
                    }
                }.navigationTitle(next == .exit && session.host ? "End this room?" : next.rawValue)
                    .navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { panel = nil } }
            }
        }
    }
    func chatText(_ row: RoomRow) -> String {
        let text = row.roomText("body")
        let sound = RoomSound.all.first { "mina:music:" + $0.id == text }
        return session.name(row.roomText("owner_id")) + ": " + (sound.map { "Requested “" + $0.title + "”." } ?? text)
    }
    func act(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; session.notice = ""
        Task { @MainActor in defer { busy = false }; do { try await action() } catch { session.notice = error.localizedDescription } }
    }
    func send(_ text: String) async throws {
        guard session.active, session.room?.roomFlag("allow_comments") == true else { throw MiNaIssue("Room chat is unavailable.") }
        let op = ops[text] ?? roomUUID(); ops[text] = op
        if try await app.api.rows("room_messages?select=id&id=eq." + op).isEmpty {
            _ = try await app.api.rest("room_messages",method: "POST",body: ["id":op,"room_id":id,"owner_id":me,"body":text])
        }
        ops.removeValue(forKey: text)
    }
    @ViewBuilder func controls(_ next: RoomPanel) -> some View {
        switch next {
        case .host:
            Text(session.room?.roomText("title") ?? "Room")
            Text("Host: " + session.name(hostID)); Text("Audience: \(session.members.count)")
            Button("View host profile") { panel = nil; app.go(session.host ? "profile" : "person",hostID) }
            if !session.host,session.room?.roomFlag("allow_follow") == true {
                Button(followed == true ? "Unfollow host" : "Follow host") { act {
                    let path = "follows?follower_id=eq." + me + "&followed_id=eq." + hostID
                    let links = try await app.api.rows(path)
                    let linked = !links.isEmpty
                    if linked { _ = try await app.api.rest(path,method: "DELETE") }
                    else { _ = try await app.api.rest("follows",method: "POST",body: ["follower_id":me,"followed_id":hostID]) }
                    followed = !linked
                } }.disabled(busy)
            }
        case .audience:
            ForEach(Array(session.members.enumerated()),id: \.offset) { _,m in
                let who = m.roomText("user_id")
                Button(session.name(who)) { panel = nil; app.go(who == me ? "profile" : "person",who) }
                Text((m["seat"] as? Int).map { $0 == 0 ? "Host" : "Mic \($0)" } ?? "Listening").font(.caption)
                if session.host && who != me && m["seat"] is Int {
                    Button("Remove from mic") { act { try await updateMember(who,["seat":NSNull()]) } }.disabled(busy)
                }
            }
        case .mic: seatControls
        case .music:
            Text(track.map { "Room selection: " + $0.title } ?? "No music is selected.")
            if track != nil { Button(player.playing.isEmpty ? "Listen to room music" : "Mute room music") {
                if player.playing.isEmpty,let track { listen = true; player.play(track,from: roomDate(session.room?.roomText("music_started_at") ?? "")) } else { listen = false; player.stop() }
            } }
            ForEach(RoomSound.all) { sound in
                RoomChoiceRow(cover: sound.id,title: sound.title,detail: "Free · " + (session.host ? (track?.id == sound.id ? "Stop" : "Play") : "Request")) { act {
                    if session.host {
                        let stop = track?.id == sound.id
                        let body: RoomRow = ["music_track":stop ? NSNull() as Any : sound.id,"music_started_at":stop ? NSNull() as Any : roomStamp(Date())]
                        let result = try await app.api.rest("rooms?id=eq." + id + "&host_id=eq." + me + "&closed=eq.false",method: "PATCH",body: body,prefer: "return=representation") as? [RoomRow]
                        guard let room = result?.first else { throw MiNaIssue("Room music could not be updated.") }
                        session.room = room; listen = !stop
                    } else { try await send("mina:music:" + sound.id); session.notice = "Requested " + sound.title + "." }
                } }.disabled(busy || !session.active || (!session.host && session.room?.roomFlag("allow_comments") != true))
            }
            if !player.error.isEmpty { Text(player.error) }
        case .chat:
            ForEach(Array(session.messages.enumerated()),id: \.offset) { _,row in Text(chatText(row)) }
            if session.messages.isEmpty { Text("No room messages yet.") }
            if session.room?.roomFlag("allow_comments") == true {
                TextField("Say hello…",text: $message).onChange(of: message) { message = String($0.prefix(1200)) }
                Button("Send") { let text = message.trimmingCharacters(in: .whitespacesAndNewlines); act { try await send(text); if message.trimmingCharacters(in: .whitespacesAndNewlines) == text { message = "" } } }.disabled(!session.active || busy || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else { Text("Comments are off in this room.") }
        case .exit:
            Text(session.host ? "Ending the room disconnects every participant and closes its chat." : "Your microphone and room audio will disconnect.")
            Button(session.host ? "End room for everyone" : "Leave room",role: .destructive) { act {
                if session.host {
                    let rows = try await app.api.rest("rooms?id=eq." + id + "&host_id=eq." + me,method: "PATCH",body: ["closed":true],prefer: "return=representation") as? [RoomRow]
                    guard rows?.first != nil else { throw MiNaIssue("Could not end this room.") }
                }
                session.leave(app.api,id); player.stop(); panel = nil; app.go("rooms")
            } }.disabled(busy)
            Button("Stay in room") { panel = nil }
        default: EmptyView()
        }
    }
    func updateMember(_ uid: String,_ body: RoomRow) async throws {
        let result = try await app.api.rest("room_members?" + session.memberFilter(id,uid),method: "PATCH",body: body,prefer: "return=representation") as? [RoomRow]
        guard result?.first != nil else { throw MiNaIssue("This listener has left.") }
    }
    func removeRequest(_ uid: String) async throws {
        _ = try await app.api.rest("room_seat_requests?" + session.memberFilter(id,uid),method: "DELETE")
    }
    @ViewBuilder var seatControls: some View {
        Text("Microphone audio stops when MiNa goes into the background. You choose when to turn it on again.")
        if session.mySeat != nil {
            Button(session.mic == "On" ? "Mute microphone" : session.mic == "Muted" ? "Unmute microphone" : "Turn on microphone") { act { try await session.speak(app.api,id) } }.disabled(!session.active || busy)
            Button(session.host ? "Turn microphone off" : "Leave microphone seat") { act { try await session.release(app.api,id) } }.disabled(busy)
            HStack { Text("Audio output"); Spacer(); RoomAudioOutput().frame(width: 44,height: 44) }
        } else if let index = session.requests.firstIndex(where: { $0.roomText("user_id") == me }) {
            Text("Seat \(session.requests[index]["seat"] as? Int ?? seat) · Queue position \(index+1)")
            Button("Cancel request") { act { try await removeRequest(me) } }.disabled(busy)
        } else {
            Button("Request microphone seat \(max(1,seat))") { act {
                _ = try await app.api.rest("room_seat_requests",method: "POST",body: ["room_id":id,"user_id":me,"seat":max(1,seat)] as RoomRow)
            } }.disabled(!session.active || busy)
        }
        if session.host {
            Section("Speaker requests") {
                if session.requests.isEmpty { Text("No one is waiting for a seat.") }
                ForEach(Array(session.requests.enumerated()),id: \.offset) { _,r in
                    let who = r.roomText("user_id"), number = r["seat"] as? Int ?? 1
                    Text(session.name(who) + " · Mic \(number)")
                    Button("Admit") { act { try await updateMember(who,["seat":number]) } }.disabled(busy || session.members.contains { ($0["seat"] as? Int) == number })
                    Button("Decline") { act { try await removeRequest(who) } }.disabled(busy)
                }
            }
        }
    }
}

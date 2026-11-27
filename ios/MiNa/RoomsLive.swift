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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewOffset = 0
    @State private var moderation: RoomModerationTarget?
    @State private var reportedRoom = false
    @State private var panel: RoomPanel?
    @State private var seat = 1
    @State private var listenerID = ""
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
                RoomStageFrame(title: room.roomText("title"),topic: room.roomText("topic"),cover: room.roomText("cover"),host: session.name(hostID),hostStatus: seats[0] == nil ? "Room host" : "Host",audience: session.active ? session.audience.count : nil,runtime: max(0,Int(-(roomDate(room.roomText("created_at")) ?? Date()).timeIntervalSinceNow / 60)),seats: seats,hostPortrait: session.pictures[hostID],portraits: portraits,safetyMenu: AnyView(safetyMenu),participants: session.participants.filter { $0.group == .present },selectParticipant: showListener,open: { next,n in seat = n; listenerID = ""; panel = next }) {
                    stageChat
                }
            } else { VStack(spacing: 16) { if session.status != "This room has ended or is private." { Text(session.status) }; if session.status == "Reconnecting…" { Button("Retry") { session.leave(app.api,id); retry += 1 } }; Button("Back to rooms") { app.go("rooms") } } }
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
        .minaAlert(player.error)
        .minaAlert(session.problem)
        .minaAlert(session.status == "Reconnecting…" ? "The room connection was interrupted. MiNa will retry." : "")
        .minaAlert(session.status == "This room has ended or is private." ? session.status : "")
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
        .roomOverlay($panel) { next in
                Group {
                    switch next {
                    case .ranking: RoomRankings(room: id)
                    case .gift: RoomGifts(id: id,session: session,initialRecipient: listenerID.isEmpty ? nil : listenerID,close: { panel = nil },inviteFriend: { panel = .share },openWallet: {
                        try app.save(resumeKey,Date().timeIntervalSince1970); panel = nil; app.go("wallet")
                    })
                    case .share: RoomInvitations(id: id)
                    default: RoomPanelList {
                        controls(next)
                        if !session.notice.isEmpty { Text(session.notice) }
                    }
                    }
                }
        }
        .sheet(item: $moderation, onDismiss: {
            if reportedRoom {
                reportedRoom = false
                session.leave(app.api, id)
                if app.route == NativeRoute(name: "rooms.live", id: id) { app.back() }
            }
        }) { target in
            if target.block {
                RoomBlockForm(target: target) {
                    moderation = nil
                    session.leave(app.api, id)
                }
            } else {
                ReportForm(targetID: target.uid, kind: target.kind, targetName: target.name) {
                    panel = nil
                    reportedRoom = target.kind == "room"
                    app.safetyChanged()
                }
            }
        }
    }
    private var safetyMenu: some View {
        PopupMenu("Room options") {
            PopupAction("Report room", "flag") { moderation = .init(uid: id, name: session.room?.roomText("title") ?? "Room", kind: "room") }
            if hostID != me && !hostID.isEmpty { personActions(hostID, label: "host") }
        } label: {
            Label("Report / Block", systemImage: "shield").font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 5).background(.white.opacity(0.16), in: Capsule())
                .frame(minHeight: 44)
        }.accessibilityLabel("Report or block")
    }

    @ViewBuilder private func personActions(_ uid: String, label: String) -> some View {
        PopupAction("Report " + label, "person.crop.circle.badge.exclamationmark") { moderation = .init(uid: uid, name: session.name(uid), kind: "profile") }
        PopupAction("Block " + label, "person.crop.circle.badge.minus", role: .destructive) { moderation = .init(uid: uid, name: session.name(uid), kind: "profile", block: true) }
    }

    private var stageChat: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.active ? (session.connections > 0 ? "Voice connected" : "Listening") : session.status)
                Spacer()
                Text("Mic " + session.mic.lowercased())
            }.font(.caption).lineLimit(1)
            let recent = Array(session.messages.suffix(5).reversed())
            if recent.isEmpty {
                Text(session.active ? "No room messages yet." : "Loading room chat…").font(.subheadline)
            } else {
                let row = recent[previewOffset % recent.count]
                let uid = row.roomText("owner_id")
                Button { showListener(uid) } label: {
                    HStack(spacing: 8) {
                        memberPortrait(uid, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(session.name(uid)).bold()
                                if !session.isCurrentMessage(row) { Text("Earlier").foregroundStyle(.white.opacity(0.8)) }
                            }.font(.caption)
                            Text(chatText(row)).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).id(row.roomMessageID)
                    .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            if !session.notice.isEmpty { Text(session.notice).font(.caption).lineLimit(1) }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .clipped()
            .task(id: session.messages.last?.roomMessageID) {
                previewOffset = 0
                while session.messages.count > 1 {
                    do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { previewOffset += 1 }
                }
            }
    }

    private func showListener(_ uid: String) {
        listenerID = uid
        panel = .listener
    }

    private func messageLine(_ row: RoomRow) -> some View {
        let uid = row.roomText("owner_id")
        return Button { showListener(uid) } label: {
            HStack(alignment: .top, spacing: 8) {
                memberPortrait(uid, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(session.name(uid)).font(.subheadline.bold())
                        Spacer()
                        if let sent = roomDate(row.roomText("created_at")) {
                            Text(sent, style: .relative).font(.caption2)
                        }
                    }
                    if !session.isCurrentMessage(row) { Text("Earlier in this room").font(.caption2) }
                    Text(chatText(row)).font(.subheadline).multilineTextAlignment(.leading)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    func chatText(_ row: RoomRow) -> String {
        let text = row.roomText("body")
        let sound = RoomSound.all.first { "mina:music:" + $0.id == text }
        return sound.map { "Requested “" + $0.title + "”." } ?? text
    }
    func act(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; session.notice = ""; session.problem = ""
        Task { @MainActor in defer { busy = false }; do { try await action() } catch { session.problem = error.localizedDescription } }
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
            HStack {
                if let url = session.pictures[hostID] { CloudPortraitImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.teal }.frame(width: 48,height: 48).clipShape(Circle()) }
                else { RoomArtwork(session.room?.roomText("cover") ?? "moon-seat").scaledToFill().frame(width: 48,height: 48).clipShape(Circle()) }
                VStack(alignment: .leading) { Text(session.name(hostID)).bold(); Text("Room host").font(.caption) }
            }
            VStack(alignment: .leading,spacing: 8) { Text(session.room?.roomText("title") ?? "Room").bold(); Text(session.room?.roomText("topic") ?? ""); if session.active { Text(roomAudienceLabel(session.audience.count) + " · " + roomOnlineLabel(session.members.count)) } }.frame(maxWidth: .infinity,alignment: .leading).padding().background(.white.opacity(0.85),in: RoundedRectangle(cornerRadius: 14))
            if !session.host { personActions(hostID, label: "host") }
            Button("View host profile") { panel = nil; app.go(session.host ? "profile" : "person",hostID) }.buttonStyle(RoomCapsuleStyle())
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
            ForEach(RoomParticipant.Group.allCases, id: \.self) { group in
                let people = session.participants.filter { $0.group == group }
                if !people.isEmpty { Text(group.rawValue).font(.headline) }
                ForEach(people) { person in
                    Button { showListener(person.id) } label: {
                        HStack(spacing: 9) {
                            memberPortrait(person.id)
                            VStack(alignment: .leading) { Text(person.name).bold(); Text(person.role).font(.caption) }
                            Spacer(); Text("›")
                        }.padding(10).background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain)
                    if group == .present, session.host, person.id != me,
                       session.members.contains(where: { $0.roomText("user_id") == person.id && $0["seat"] is Int }) {
                        Button("Remove from mic") { act { try await updateMember(person.id, ["seat": NSNull()]) } }.disabled(busy)
                    }
                }
            }
        case .listener:
            HStack { memberPortrait(listenerID); Text(session.name(listenerID)).font(.headline) }
            if let person = session.participants.first(where: { $0.id == listenerID }) {
                Text(person.group == .present ? "In this room" : person.role)
            }
            if listenerID != me { personActions(listenerID, label: "listener") }
            Button("View profile") { panel = nil; app.go(listenerID == me ? "profile" : "person",listenerID) }.buttonStyle(RoomCapsuleStyle())
            if listenerID != me, session.members.contains(where: { $0.roomText("user_id") == listenerID }), session.room?.roomFlag("allow_gifts") == true {
                Button("Choose a gift") { panel = .gift }.buttonStyle(RoomCapsuleStyle())
            }
        case .mic: seatControls
        case .music:
            Text(track.map { "Room selection: " + $0.title } ?? "No music is selected.")
            if track != nil { Button(player.playing.isEmpty ? "Listen to room music" : "Mute room music") {
                if player.playing.isEmpty,let track { listen = true; player.play(track,from: roomDate(session.room?.roomText("music_started_at") ?? "")) } else { listen = false; player.stop() }
            } }
            ForEach(RoomSound.all) { sound in
                RoomMusicRow(sound: sound,button: session.host ? (track?.id == sound.id ? "Stop" : "Play") : "Request") { act {
                    if session.host {
                        let stop = track?.id == sound.id
                        let body: RoomRow = ["music_track":stop ? NSNull() as Any : sound.id,"music_started_at":stop ? NSNull() as Any : roomStamp(Date())]
                        let result = try await app.api.rest("rooms?id=eq." + id + "&host_id=eq." + me + "&closed=eq.false",method: "PATCH",body: body,prefer: "return=representation") as? [RoomRow]
                        guard let room = result?.first else { throw MiNaIssue("Room music could not be updated.") }
                        session.room?.merge(room) { _, new in new }; listen = !stop
                    } else { try await send("mina:music:" + sound.id); session.notice = "Requested " + sound.title + "." }
                } }.disabled(busy || !session.active || (!session.host && session.room?.roomFlag("allow_comments") != true))
            }
        case .chat:
            ForEach(session.messages, id: \.roomMessageID) { row in messageLine(row) }
            if session.messages.isEmpty { Text("No room messages yet.") }
            if session.room?.roomFlag("allow_comments") == true {
                TextField("Say hello…",text: $message).onChange(of: message) { message = String($0.prefix(1200)) }
                Button("Send") { let text = message.trimmingCharacters(in: .whitespacesAndNewlines); act { try await send(text); if message.trimmingCharacters(in: .whitespacesAndNewlines) == text { message = "" } } }.disabled(!session.active || busy || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else { Text("Comments are off in this room.") }
        case .exit:
            Text(session.host ? "Ending the room disconnects every participant and closes its chat." : "Your microphone and room audio will disconnect.")
            PopupAction(session.host ? "End room for everyone" : "Leave room", "rectangle.portrait.and.arrow.right", role: .destructive) { act {
                if session.host {
                    let rows = try await app.api.rest("rooms?id=eq." + id + "&host_id=eq." + me,method: "PATCH",body: ["closed":true],prefer: "return=representation") as? [RoomRow]
                    guard rows?.first != nil else { throw MiNaIssue("Could not end this room.") }
                    session.leave(app.api, id)
                } else {
                    do {
                        try await session.leave(app.api, id)?.value
                    } catch {
                        retry += 1
                        throw MiNaIssue("Leaving the room could not be confirmed. Please try again.")
                    }
                }
                player.stop(); panel = nil; app.go("rooms")
            } }.disabled(busy)
            PopupAction("Stay in room", "arrow.uturn.backward") { panel = nil }
        default: EmptyView()
        }
    }
    @ViewBuilder private func memberPortrait(_ uid: String, size: CGFloat = 44) -> some View {
        if let url = session.pictures[uid] {
            CloudPortraitImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.teal.opacity(0.15) }.frame(width: size,height: size).clipShape(Circle())
        } else { Text(String(session.name(uid).prefix(2))).bold().frame(width: size,height: size).background(Color.teal.opacity(0.15),in: Circle()) }
    }
    func updateMember(_ uid: String,_ body: RoomRow) async throws {
        let result = try await app.api.rest("room_members?" + session.memberFilter(id,uid),method: "PATCH",body: body,prefer: "return=representation") as? [RoomRow]
        guard result?.first != nil else { throw MiNaIssue("This listener has left.") }
    }
    func removeRequest(_ uid: String) async throws {
        _ = try await app.api.rest("room_seat_requests?" + session.memberFilter(id,uid),method: "DELETE")
    }
    @ViewBuilder var seatControls: some View {
        HStack { NativeArt("queue",7).scaledToFit().frame(width: 60,height: 60)
            VStack(alignment: .leading) { Text(session.mySeat != nil ? "Voice chatting" : "Microphone seats").font(.headline)
                Text("Microphone " + session.mic.lowercased()).font(.caption) }
        }.frame(maxWidth: .infinity,alignment: .leading).padding(9).background(.white.opacity(0.8),in: RoundedRectangle(cornerRadius: 13))
        Text("Microphone audio stops when MiNa goes into the background.").font(.footnote)
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

private extension Dictionary where Key == String, Value == Any {
    var roomMessageID: String { roomText("id") }
}

private struct RoomModerationTarget: Identifiable {
    let id = UUID()
    let uid: String
    let name: String
    let kind: String
    var block = false
}

private struct RoomBlockForm: View {
    @EnvironmentObject private var app: MiNaAppModel
    @Environment(\.dismiss) private var dismiss
    let target: RoomModerationTarget
    let completed: () -> Void
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        PopupPanel(title: "Block listener?", message: target.name, close: { dismiss() }) {
            Text("Their messages will be hidden. You can unblock this person in your profile settings.")
                .font(.subheadline).foregroundStyle(PopupTheme.ink)
            PopupAction("Confirm block", "person.crop.circle.badge.minus", role: .destructive) { Task { await submit() } }
        }.disabled(busy).modifier(FittedPopup()).minaAlert(error).interactiveDismissDisabled(busy)
    }

    @MainActor private func submit() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await app.blockMember(target.uid, name: target.name)
            completed()
        } catch { self.error = error.localizedDescription }
    }
}

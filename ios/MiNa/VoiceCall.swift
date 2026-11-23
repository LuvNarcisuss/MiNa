import AVFoundation
import SwiftUI

@MainActor
private func callAction(_ api: MiNaAPI, _ id: String, _ action: String, sdp: String? = nil) async throws -> String {
    var body: [String:Any] = ["p_id":id, "p_action":action]
    if let sdp { body["p_sdp"] = sdp }
    guard let state = try await api.rest("rpc/voice_action", method:"POST", body:body) as? String else {
        throw VoiceFailure("The call state could not be confirmed.")
    }
    return state
}

struct IncomingCallBanner: View {
    @EnvironmentObject var app: MiNaAppModel
    @Environment(\.scenePhase) private var phase
    var route: NativeRoute { app.route }
    @State private var call: InboxRow?
    @State private var name = ""
    @State private var error = ""
    @State private var switching = false

    var body: some View {
        Group {
            if let call, route.name != "messages.call", phase == .active {
                VStack {
                    Text("\(name) is calling").bold()
                    if !error.isEmpty { Text(error).font(.caption) }
                    HStack {
                        Button("Decline", role: .destructive) { Task {
                            do { _ = try await callAction(app.api,call.id,"decline"); self.call = nil }
                            catch { self.error = error.localizedDescription }
                        } }
                        Button("Open call") {
                            if route.name.hasPrefix("rooms.live") || route.name == "dreams.record" { switching = true }
                            else { app.go("messages.call",call.id) }
                        }
                    }.buttonStyle(.bordered)
                }.padding().background(.regularMaterial,in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal)
                .confirmationDialog("Leave your current audio session?", isPresented: $switching) {
                    Button("Leave and open call") { app.go("messages.call",call.id) }
                    Button("Stay here",role: .cancel) {}
                }
            }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                do {
                    let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-45))
                    let result = try await app.api.rows("voice_calls?select=id,caller_id&callee_id=eq.\(app.api.userID)&state=eq.ringing&created_at=gte.\(cutoff)&order=created_at.desc&limit=1")
                    let row = result.first.map(InboxRow.init(values:))
                    if let row, call?.id != row.id {
                        let caller = row.string("caller_id")
                        let people = try await inboxPeople([caller], api: app.api)
                        name = people[caller]?.string("name") ?? "A listener"
                        error = ""
                    }
                    try Task.checkCancellation()
                    call = row
                } catch { if !Task.isCancelled { call = nil } }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                do { try await subscribe() } catch {}
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func subscribe() async throws {
        let token = try await app.api.accessToken()
        var components = URLComponents(url: MiNaAPI.origin, resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        components?.path = "/realtime/v1/websocket"
        components?.queryItems = [URLQueryItem(name:"apikey",value:MiNaAPI.key),URLQueryItem(name:"vsn",value:"1.0.0")]
        guard let url = components?.url else { throw VoiceFailure("Realtime inbox unavailable.") }
        let socket = URLSession.shared.webSocketTask(with:url)
        socket.resume()
        try await withTaskCancellationHandler {
            defer { socket.cancel(with:.goingAway,reason:nil) }
            let change = ["event":"INSERT","schema":"public","table":"messages"]
            let join: [String:Any] = ["topic":"realtime:mina-inbox","event":"phx_join","ref":"1","payload":["access_token":token,"config":["postgres_changes":[change]]]]
            let payload = try JSONSerialization.data(withJSONObject:join)
            try await socket.send(.string(String(decoding:payload,as:UTF8.self)))
            let heartbeat = Task {
                defer { socket.cancel(with:.goingAway,reason:nil) }
                // Rejoin with a refreshed access token periodically.
                for index in 2...25 {
                    try await Task.sleep(nanoseconds: 25_000_000_000)
                    try await socket.send(.string("{\"topic\":\"phoenix\",\"event\":\"heartbeat\",\"payload\":{},\"ref\":\"\(index)\"}"))
                }
            }
            defer { heartbeat.cancel() }
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .string(text): data = Data(text.utf8)
                case let .data(bytes): data = bytes
                @unknown default: continue
                }
                if let row = try JSONSerialization.jsonObject(with:data) as? [String:Any], row["event"] as? String == "postgres_changes" {
                    NotificationCenter.default.post(name:.inboxUpdated,object:nil)
                }
            }
        } onCancel: { socket.cancel(with:.goingAway,reason:nil) }
    }
}

struct VoiceCallScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    @Environment(\.scenePhase) private var phase
    let id: String
    @State private var person: InboxRow?
    @State private var state = ""
    @State private var incoming = false
    @State private var error = ""
    @State private var peer: VoicePeer?
    @State private var offer: String?
    @State private var answer: String?
    @State private var applied = false
    @State private var busy = false
    @State private var stopped = false
    @State private var endingAction: String?
    @State private var endingError = ""
    @State private var confirmingEnd = false
    @State private var connectedAt: Date?
    @State private var deadline: Date?
    @State private var lastBeat = Date.distantPast
    @State private var lastContact = Date()
    @State private var muted = false
    @State private var speaker = false

    var active: Bool { state == "ringing" || state == "accepted" }
    var label: String {
        if endingAction != nil { return "Call stopped on this iPhone" }
        if stopped && state.isEmpty { return "Call unavailable" }
        switch state {
        case "ringing": return incoming ? "Incoming voice call" : "Calling…"
        case "accepted": return stopped ? "Disconnected" : "Connecting audio…"
        case "busy": return "Line busy"
        case "ended": return "Call ended"
        case "declined": return "Call declined"
        case "disconnected": return "Call disconnected"
        case "missed": return "Missed call"
        default: return "Opening call…"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack { Button { if active && !stopped { end(incoming && state == "ringing" ? "decline" : "end") } else { app.back() } } label: {
                Image(systemName:"chevron.left").frame(width:44,height:44)
            }.accessibilityLabel("Back"); Spacer(); Text("Voice call").bold(); Spacer(); Color.clear.frame(width:44,height:44) }
            Spacer()
            ZStack { NativeArt("call",4).frame(width:180,height:180); InboxAvatar(person:person,size:120) }
            Text(person?.string("name") ?? "Voice call").font(.title.bold())
            if let connectedAt { Text(connectedAt,style:.timer).monospacedDigit() } else { Text(label) }
            if !error.isEmpty { Text(error).font(.footnote).multilineTextAlignment(.center) }
            if !endingError.isEmpty {
                Text(endingError).font(.footnote).multilineTextAlignment(.center)
                Button("Retry confirmation") { confirmEnd() }.disabled(confirmingEnd)
            }
            Spacer()
            if !stopped && state == "ringing" && incoming { Button("Answer", action: accept).buttonStyle(.borderedProminent).disabled(busy) }
            HStack(spacing:24) {
                if state == "accepted" && !stopped {
                    Button { do {
                        let audio = AVAudioSession.sharedInstance()
                        try audio.overrideOutputAudioPort(speaker ? .none : .speaker)
                        speaker = audio.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
                    } catch { self.error = error.localizedDescription } } label: { NativeArt("call",speaker ? 6 : 7).frame(width:52,height:52) }
                    .accessibilityLabel(speaker ? "Use earpiece" : "Use speaker")
                }
                if active && !stopped {
                    Button { end(incoming && state == "ringing" ? "decline" : "end") } label: { NativeArt("call",5).frame(width:62,height:62) }
                    .accessibilityLabel(incoming && state == "ringing" ? "Decline" : "End call")
                } else { Button("Close") { app.back() }.buttonStyle(.bordered) }
                if state == "accepted" && !stopped {
                    Button { muted.toggle(); peer?.microphone(!muted) } label: { NativeArt("call",muted ? 9 : 8).frame(width:52,height:52) }
                    .disabled(peer == nil).accessibilityLabel(muted ? "Unmute" : "Mute")
                }
            }.padding(.bottom,30)
        }.padding().background { NativeArt("chat",1).ignoresSafeArea() }
        .task {
            while !Task.isCancelled {
                await synchronize()
                if stopped { break }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
            }
        }
        .onDisappear { if !stopped { end("end") } }
        .onChange(of:phase) { if $0 == .background && active { end("disconnect") } }
        .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification)) { note in
            if active, note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue { end("disconnect") }
        }
    }

    @MainActor private func stop() {
        peer?.close(); peer = nil
        if speaker { try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none) }
        speaker = false; stopped = true; connectedAt = nil
    }

    @MainActor private func end(_ action: String) {
        guard !stopped else { return }
        let needsUpdate = active || state.isEmpty
        stop()
        if needsUpdate {
            endingAction = action
            confirmEnd()
        }
    }

    @MainActor private func confirmEnd() {
        guard let action = endingAction, !confirmingEnd else { return }
        confirmingEnd = true
        Task {
            defer { confirmingEnd = false }
            do {
                let confirmed = try await callAction(app.api,id,action)
                guard ["ended","declined","disconnected","missed","busy"].contains(confirmed) else {
                    throw VoiceFailure("The call is still active on the server.")
                }
                state = confirmed
                endingAction = nil
                endingError = ""
            } catch {
                endingError = "The service could not confirm the call ended. " + error.localizedDescription
            }
        }
    }

    @MainActor private func accept() {
        guard !busy && !stopped else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                guard await VoicePeer.requestMicrophone() else { throw VoiceFailure("Enable microphone access in Settings to answer.") }
                guard !stopped && phase != .background else { return }
                let confirmed = try await callAction(app.api,id,"accept")
                if !stopped { state = confirmed }
            } catch { if !stopped { self.error = error.localizedDescription } }
        }
    }

    @MainActor private func synchronize() async {
        guard !stopped, !busy else { return }
        do {
            guard UUID(uuidString:id) != nil, let value = try await app.api.rows("voice_calls?id=eq.\(id)&limit=1").first else {
                stop(); error = "This call is unavailable."; return
            }
            try Task.checkCancellation()
            guard !stopped else { return }
            let call = InboxRow(values:value)
            incoming = call.string("callee_id") == app.api.userID
            state = call.string("state")
            guard active else { stop(); return }
            if Date().timeIntervalSince(lastBeat) >= 6 {
                let current = try await callAction(app.api,id,"heartbeat")
                guard !stopped else { return }
                state = current; lastBeat = Date()
                guard active else { stop(); return }
            }
            lastContact = Date()
            if person == nil {
                let id = call.string(incoming ? "caller_id" : "callee_id")
                person = try await inboxPeople([id],api:app.api)[id]
            }
            guard !stopped && state == "accepted" else { return }
            if deadline == nil { deadline = Date().addingTimeInterval(36) }
            if peer == nil {
                guard await VoicePeer.requestMicrophone() else { throw VoiceFailure("Microphone permission is required for a voice call.") }
                try Task.checkCancellation()
                guard !stopped && phase != .background else { return }
                let fresh = try VoicePeer()
                fresh.microphone(!muted)
                peer = fresh
            }
            guard let peer else { return }
            if !incoming {
                if call.string("offer").isEmpty {
                    if offer == nil { offer = try await peer.offer()["sdp"] }
                    guard !stopped else { return }
                    _ = try await callAction(app.api,id,"offer",sdp:offer)
                } else if offer == nil { throw VoiceFailure("The previous call session ended.") }
                if !applied && !call.string("answer").isEmpty {
                    try await peer.receiveAnswer(["type":"answer","sdp":call.string("answer")]); applied = true
                }
            } else if !call.string("offer").isEmpty {
                if call.string("answer").isEmpty {
                    if answer == nil { answer = try await peer.answer(["type":"offer","sdp":call.string("offer")])["sdp"] }
                    guard !stopped else { return }
                    _ = try await callAction(app.api,id,"answer",sdp:answer)
                } else if answer == nil { throw VoiceFailure("The previous call session ended.") }
            }
            if peer.connected {
                if connectedAt == nil { connectedAt = Date() }
                deadline = Date().addingTimeInterval(9)
            } else {
                connectedAt = nil
                if peer.failed || (deadline ?? .distantFuture) < Date() { throw VoiceFailure("A voice connection could not be established.") }
            }
        } catch {
            guard !Task.isCancelled && !stopped else { return }
            self.error = error.localizedDescription
            if error is VoiceFailure || Date().timeIntervalSince(lastContact) > 9 || (deadline ?? .distantFuture) < Date() { end("disconnect") }
        }
    }
}

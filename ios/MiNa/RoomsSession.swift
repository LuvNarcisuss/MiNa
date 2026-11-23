import Foundation
import SwiftUI
import AVFoundation

@MainActor final class NativeRoomSession: ObservableObject {
    @Published var room: RoomRow?
    @Published var members: [RoomRow] = []
    @Published var messages: [RoomRow] = []
    @Published var requests: [RoomRow] = []
    @Published var profiles: [String:String] = [:]
    @Published var pictures: [String:URL] = [:]
    @Published var active = false
    @Published var status = "Connecting to the room…"
    @Published var connections = 0
    @Published var mic = "Off"
    @Published var notice = ""
    private var joined = ""
    private var lastBeat = Date.distantPast
    private var confirmed = Date.distantPast
    private var lastProfiles = Date.distantPast
    private var cursor = 0
    // The read cursor advances only after valid descriptions have entered their sender's retry slot.
    private var pendingSignals: [String:RoomRow] = [:]
    private var epoch = UUID()
    private var audioWork: Task<Void, Never>?
    private var audioGeneration = UUID()
    private var profileWork: Task<Void, Never>?
    var mySeat: Int? { members.first { $0.roomText("user_id") == me }?["seat"] as? Int }
    var host: Bool { room?.roomText("host_id") == me }
    private var me = ""
    private struct Peer {
        let link: VoicePeer
        let session: String
        let exchange: String
        let started = Date()
        var receivedAnswer = false
    }
    private var peers: [String:Peer] = [:]
    func name(_ who: String) -> String { profiles[who] ?? (who == me ? "You" : "Listener") }
    func memberFilter(_ id: String,_ user: String) -> String { "room_id=eq." + id + "&user_id=eq." + user }
    private func membership(_ id: String,_ stamp: String) -> String { "room_members?" + memberFilter(id,me) + "&joined_at=eq." + roomFilter(stamp) }
    private func disconnect() {
        audioGeneration = UUID()
        audioWork?.cancel(); audioWork = nil
        profileWork?.cancel(); profileWork = nil
        mic = "Off"
        peers.values.forEach { $0.link.microphone(false); $0.link.close() }
        peers.removeAll(); connections = 0; active = false; members = []; requests = []
    }
    func leave(_ api: MiNaAPI,_ id: String) {
        epoch = UUID()
        disconnect()
        if !joined.isEmpty { let path = membership(id,joined); Task { _ = try? await api.rest(path,method: "DELETE") } }
        joined = ""; cursor = 0; pendingSignals.removeAll(); confirmed = .distantPast
    }
    func watchdog() {
        if active && -confirmed.timeIntervalSinceNow > 30 { disconnect(); status = "Reconnecting…" }
    }
    private func check(_ generation: UUID) throws {
        try Task.checkCancellation()
        if generation != epoch { throw CancellationError() }
    }
    func run(_ api: MiNaAPI,_ id: String) async {
        let generation = epoch
        me = api.userID.lowercased()
        let filter = "room_id=eq." + id
        while !Task.isCancelled && generation == epoch {
            do {
                let records = try await api.rows("rooms?id=eq." + id + "&limit=1")
                try check(generation)
                guard let current = records.first, !current.roomFlag("closed") else {
                    leave(api,id); room = nil; status = "This room has ended or is private."; return
                }
                room = current
                if joined.isEmpty {
                    let prev = try await api.rows("room_members?" + memberFilter(id,me))
                    try check(generation)
                    if let old = prev.first { _ = try await api.rest(membership(id,old.roomText("joined_at")),method: "DELETE"); try check(generation) }
                    let rows = try await api.rest("room_members",method: "POST",body: ["room_id":id,"user_id":me,"seat":host ? 0 as Any : NSNull()] as RoomRow,prefer: "return=representation") as? [RoomRow]
                    guard let timestamp = rows?.first?.roomText("joined_at"), !timestamp.isEmpty else { throw MiNaIssue("Could not join this room.") }
                    if Task.isCancelled || generation != epoch {
                        let path = membership(id,timestamp)
                        Task { _ = try? await api.rest(path,method: "DELETE") }; return
                    }
                    joined = timestamp; lastBeat = Date(); cursor = 0; pendingSignals.removeAll()
                }
                if -lastBeat.timeIntervalSinceNow >= 9 {
                    let rows = try await api.rest(membership(id,joined),method: "PATCH",body: ["last_seen":roomStamp(Date())],prefer: "return=representation") as? [RoomRow]
                    try check(generation)
                    guard rows?.first != nil else { joined = ""; throw MiNaIssue("Membership expired.") }
                    lastBeat = Date()
                }
                async let roster = api.rows("room_members?" + filter + "&last_seen=gte." + roomFilter(roomStamp(Date().addingTimeInterval(-60))) + "&order=joined_at.asc")
                async let chat = api.rows("room_messages?" + filter + "&order=created_at.desc&limit=45")
                async let queue = api.rows("room_seat_requests?" + filter + "&order=created_at.asc")
                async let signals = api.rows("room_signals?" + filter + "&recipient_id=eq." + me + "&id=gt.\(cursor)&created_at=gte." + roomFilter(joined) + "&order=id.asc&limit=100")
                let (present,history,waiting,incoming) = try await (roster,chat,queue,signals)
                try check(generation)
                guard present.contains(where: { $0.roomText("user_id") == me && $0.roomText("joined_at") == joined }) else { joined = ""; throw MiNaIssue("Membership expired.") }
                members = present; messages = Array(history.reversed()); requests = waiting
                if mySeat == nil { setMic("Off") }
                for (uid,peer) in peers {
                    let member = present.first { $0.roomText("user_id") == uid && $0.roomText("joined_at") == peer.session }
                    peer.link.remoteAudio(member?["seat"] is Int)
                    if member == nil || (mySeat == nil && !(member?["seat"] is Int)) {
                        peer.link.close()
                        peers.removeValue(forKey: uid)
                    }
                }
                active = true; status = "In room"; confirmed = Date()
                let ids = Set(present.map { $0.roomText("user_id") } + history.map { $0.roomText("owner_id") } + [current.roomText("host_id")])
                if profileWork == nil && (-lastProfiles.timeIntervalSinceNow > 480 || !ids.isSubset(of: Set(profiles.keys))) {
                    let token = audioGeneration
                    profileWork = Task {
                        defer { if audioGeneration == token { profileWork = nil } }
                        do {
                            let list = try await api.rows("profiles?select=id,name,avatar_path&id=in.(" + ids.joined(separator: ",") + ")")
                            try check(generation)
                            for key in ids where profiles[key] == nil { profiles[key] = "Listener" }
                            for p in list {
                                let key = p.roomText("id"), path = p.roomText("avatar_path")
                                profiles[key] = p.roomText("name")
                                if !path.isEmpty {
                                    let image = try? await api.mediaURL(path)
                                    try check(generation)
                                    pictures[key] = image
                                } else { pictures.removeValue(forKey: key) }
                            }
                            lastProfiles = Date()
                        } catch { }
                    }
                }
                if audioWork == nil {
                    let audioToken = audioGeneration
                    audioWork = Task {
                        defer { if audioGeneration == audioToken { audioWork = nil } }
                        do {
                            try await refreshAudio(api,id,incoming,generation)
                        } catch {
                            guard !Task.isCancelled, generation == epoch, audioGeneration == audioToken else { return }
                            notice = "A voice connection was interrupted. Audio will retry."
                        }
                    }
                }
            } catch {
                if Task.isCancelled || generation != epoch { return }
                disconnect(); status = "Reconnecting…"
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
        }
    }
    private func refreshAudio(_ api: MiNaAPI,_ id: String,_ incoming: [RoomRow],_ generation: UUID) async throws {
        let wanted = members.filter { $0.roomText("user_id") != me && (mySeat != nil || $0["seat"] is Int) }
        for (key,peer) in peers {
            guard let m = wanted.first(where: { $0.roomText("user_id") == key }), m.roomText("joined_at") == peer.session else {
                peer.link.close(); peers.removeValue(forKey: key); continue
            }
            peer.link.remoteAudio(m["seat"] is Int)
        }
        func create(_ member: RoomRow,_ exchange: String) throws -> Peer {
            try check(generation)
            let who = member.roomText("user_id")
            guard active, let current = members.first(where: { $0.roomText("user_id") == who && $0.roomText("joined_at") == member.roomText("joined_at") }),
                  mySeat != nil || current["seat"] is Int else { throw CancellationError() }
            peers.removeValue(forKey: who)?.link.close()
            let link = try VoicePeer()
            link.microphone(mic == "On" && mySeat != nil); link.remoteAudio(current["seat"] is Int)
            let peer = Peer(link: link, session: member.roomText("joined_at"),exchange: exchange)
            peers[who] = peer
            return peer
        }
        func send(_ peer: Peer,_ target: String,_ description: [String:String]) async throws {
            try check(generation)
            guard active, peers[target]?.exchange == peer.exchange else { return }
            let body: RoomRow = ["fromSession":joined,"toSession":peer.session,"exchange":peer.exchange,"description":description]
            _ = try await api.rest("room_signals",method: "POST",body: ["room_id":id,"sender_id":me,"recipient_id":target,"body":body] as RoomRow)
        }
        // Offers from the designated initiator supersede that sender's previous exchange.
        // Answers are eligible only for the local offer that is still outstanding.
        for signal in incoming {
            try check(generation)
            guard let number = signal["id"] as? Int, number > cursor else { continue }
            let who = signal.roomText("sender_id")
            if let body = signal["body"] as? RoomRow, body.roomText("toSession") == joined,
               !body.roomText("exchange").isEmpty,
               wanted.contains(where: { $0.roomText("user_id") == who && $0.roomText("joined_at") == body.roomText("fromSession") }),
               let desc = body["description"] as? [String:String], !(desc["sdp"] ?? "").isEmpty {
                let offer = who < me && desc["type"] == "offer"
                let answer = me < who && desc["type"] == "answer" && peers[who]?.exchange == body.roomText("exchange") && peers[who]?.receivedAnswer == false
                if offer || answer { pendingSignals[who] = signal }
            }
            cursor = number
        }
        for (who,signal) in pendingSignals {
            try check(generation)
            guard let body = signal["body"] as? RoomRow, let desc = body["description"] as? [String:String],
                  let member = wanted.first(where: { $0.roomText("user_id") == who && $0.roomText("joined_at") == body.roomText("fromSession") })
            else { pendingSignals.removeValue(forKey: who); continue }
            do {
                let exchange = body.roomText("exchange")
                if desc["type"] == "offer" {
                    let peer = try create(member,exchange)
                    let answer = try await peer.link.answer(desc)
                    try await send(peer,who,answer)
                } else if let peer = peers[who], peer.exchange == exchange, !peer.receivedAnswer {
                    try await peer.link.receiveAnswer(desc)
                    try check(generation)
                    if peers[who]?.exchange == exchange { peers[who]?.receivedAnswer = true }
                }
                try check(generation)
                pendingSignals.removeValue(forKey: who)
            } catch {
                try check(generation)
                notice = "A voice connection was interrupted. Audio will retry."
            }
        }
        for member in wanted {
            try check(generation)
            let who = member.roomText("user_id")
            guard me < who else { continue }
            if let existing = peers[who], existing.link.connected || -existing.started.timeIntervalSinceNow < 24 { continue }
            do {
                let peer = try create(member,roomUUID())
                let offer = try await peer.link.offer()
                try await send(peer,who,offer)
            } catch {
                try check(generation)
                peers.removeValue(forKey: who)?.link.close()
                notice = "A voice connection was interrupted. Audio will retry."
            }
        }
        try check(generation)
        connections = peers.values.filter { $0.link.connected }.count
    }
    private func setMic(_ state: String) { mic = state; peers.values.forEach { $0.link.microphone(state == "On") } }
    func speak(_ api: MiNaAPI,_ id: String) async throws {
        guard active, let seat = mySeat else { throw MiNaIssue("Join a microphone seat first.") }
        if mic == "On" { setMic("Muted"); return }
        let generation = epoch
        let audioToken = audioGeneration
        let sessionTime = joined
        guard await VoicePeer.requestMicrophone() else { throw MiNaIssue("Allow microphone access in Settings to speak.") }
        try check(generation)
        guard audioToken == audioGeneration, joined == sessionTime, active, mySeat == seat else { throw MiNaIssue("Microphone access was interrupted.") }
        let rows = try await api.rest(membership(id,sessionTime),method: "PATCH",body: ["seat":seat],prefer: "return=representation") as? [RoomRow]
        try check(generation)
        guard active,audioToken == audioGeneration,joined == sessionTime,mySeat == seat,let assigned = rows?.first?["seat"] as? Int, assigned == seat else { throw MiNaIssue("This seat is no longer available.") }
        setMic("On")
    }
    func release(_ api: MiNaAPI,_ id: String) async throws {
        setMic("Off")
        if !host && !joined.isEmpty { _ = try await api.rest(membership(id,joined),method: "PATCH",body: ["seat":NSNull()]) }
    }
}

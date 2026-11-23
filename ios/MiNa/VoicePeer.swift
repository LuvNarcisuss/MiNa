import AVFoundation
import SwiftUI
import WebRTC

struct VoiceFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Audio-only unified-plan transport. The database exchanges complete SDP descriptions.
@MainActor
final class VoicePeer: ObservableObject {
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()
    private let connection: RTCPeerConnection
    private let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    private var sender: RTCRtpSender?
    private var track: RTCAudioTrack?
    private var transmitting = false
    private var receiving = true
    private var closed = false

    var connected: Bool { !closed && connection.connectionState == .connected }
    var failed: Bool { closed || connection.connectionState == .failed }

    init() throws {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let servers = Bundle.main.object(forInfoDictionaryKey: "MiNaIceServers") as? [[String: Any]] ?? []
        config.iceServers = servers.compactMap { entry in
            guard let urls = entry["urls"] as? [String], !urls.isEmpty else { return nil }
            return RTCIceServer(urlStrings: urls, username: entry["username"] as? String, credential: entry["credential"] as? String)
        }
        let candidate: RTCPeerConnection? = Self.factory.peerConnection(with: config, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: nil)
        guard let pc = candidate else {
            throw VoiceFailure("Voice audio is unavailable on this device.")
        }
        connection = pc
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func microphone(_ enabled: Bool) {
        guard !closed else { return }
        transmitting = enabled
        if enabled && track == nil {
            track = Self.factory.audioTrack(with: Self.factory.audioSource(with: constraints), trackId: UUID().uuidString)
        }
        track?.isEnabled = enabled
        sender?.track = enabled ? track : nil
    }

    func remoteAudio(_ enabled: Bool) {
        receiving = enabled
        for receiver in connection.receivers { receiver.track?.isEnabled = enabled }
    }

    private func attach(_ transceiver: RTCRtpTransceiver?) throws {
        guard let transceiver else { throw VoiceFailure("The audio channel is unavailable.") }
        if transceiver.direction != .sendRecv {
            var error: NSError?
            transceiver.setDirection(.sendRecv, error: &error)
            if let error { throw error }
        }
        sender = transceiver.sender
        sender?.track = transmitting ? track : nil
        remoteAudio(receiving)
    }

    func offer() async throws -> [String: String] {
        let settings = RTCRtpTransceiverInit()
        settings.direction = .sendRecv
        try attach(connection.addTransceiver(of: .audio, init: settings))
        let description: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            connection.offer(for: constraints) { value, error in
                if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: error ?? VoiceFailure("Could not create a voice offer.")) }
            }
        }
        return try await gather(description, type: "offer")
    }

    func answer(_ offer: [String: String]) async throws -> [String: String] {
        try await receive(offer, type: .offer)
        try attach(connection.transceivers.first)
        let description: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            connection.answer(for: constraints) { value, error in
                if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: error ?? VoiceFailure("Could not answer this voice session.")) }
            }
        }
        return try await gather(description, type: "answer")
    }

    func receiveAnswer(_ answer: [String: String]) async throws {
        try await receive(answer, type: .answer)
        remoteAudio(receiving)
    }

    private func receive(_ data: [String: String], type: RTCSdpType) async throws {
        guard !closed, let sdp = data["sdp"], !sdp.isEmpty else { throw VoiceFailure("Voice description unavailable.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(RTCSessionDescription(type: type, sdp: sdp)) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func gather(_ description: RTCSessionDescription, type: String) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setLocalDescription(description) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        let deadline = Date().addingTimeInterval(6)
        while !closed && connection.iceGatheringState != .complete && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !closed, let sdp = connection.localDescription?.sdp else { throw VoiceFailure("Voice negotiation was interrupted.") }
        return ["type": type, "sdp": sdp]
    }

    func close() {
        guard !closed else { return }
        closed = true
        track?.isEnabled = false
        connection.close()
        track = nil
        sender = nil
    }
}

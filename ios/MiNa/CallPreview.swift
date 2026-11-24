import Accelerate
import AVFoundation
import SwiftUI

enum CallPreviewMode: String, Identifiable, CaseIterable {
    case voice = "Voice preview"
    case video = "Video preview"
    var id: Self { self }
    var icon: String { self == .video ? "video.fill" : "phone.fill" }
}

// All capture session mutations run on the camera queue.
private final class PreviewCamera: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.mina.bedtime.preview-camera")

    func start(position: AVCaptureDevice.Position) async throws {
        try await withCheckedThrowingContinuation { (result: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                        throw MiNaIssue("This device has no available camera.")
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    session.automaticallyConfiguresApplicationAudioSession = false
                    session.beginConfiguration()
                    let old = session.inputs.first
                    if let old { session.removeInput(old) }
                    guard session.canAddInput(input) else {
                        if let old, session.canAddInput(old) { session.addInput(old) }
                        session.commitConfiguration()
                        throw MiNaIssue("The camera could not be opened.")
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning else { throw MiNaIssue("The camera could not start.") }
                    result.resume()
                } catch { result.resume(throwing: error) }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            guard !session.inputs.isEmpty else { return }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
        }
    }
}

private final class CameraSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct CameraView: UIViewRepresentable {
    let camera: PreviewCamera
    let mirrored: Bool

    func makeUIView(context: Context) -> CameraSurface {
        let view = CameraSurface()
        view.preview.videoGravity = .resizeAspectFill
        view.preview.session = camera.session
        return view
    }

    func updateUIView(_ view: CameraSurface, context: Context) {
        guard let connection = view.preview.connection else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}

@MainActor
private final class CallPreviewMedia: ObservableObject {
    let camera = PreviewCamera()
    let audio = AVAudioSession.sharedInstance()
    @Published var micOn = false
    @Published private(set) var speakerOn = true
    @Published private(set) var outputName = ""
    @Published private(set) var outputIssue = ""
    @Published private(set) var ready = false
    @Published var cameraOn = false
    @Published var level: Float = 0
    @Published var position: AVCaptureDevice.Position = .front
    @Published var micIssue = ""
    @Published var cameraIssue = ""
    @Published private(set) var microphoneDenied = false
    @Published private(set) var cameraDenied = false
    @Published var configuring = false
    @Published private(set) var requestingMic = false
    private var generation = 0
    private var engine: AVAudioEngine?
    private var previous: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    func start(_ mode: CallPreviewMode) async {
        stop()
        let attempt = generation
        configuring = true
        micIssue = ""
        cameraIssue = ""
        microphoneDenied = audio.recordPermission == .denied
        if microphoneDenied { micIssue = "Allow microphone access in Settings." }
        cameraDenied = false
        var cameraGranted = false
        if mode == .video { cameraGranted = await AVCaptureDevice.requestAccess(for: .video) }
        guard generation == attempt, !Task.isCancelled else { return }
        // Permission sheets can finish before the scene becomes active again.
        while UIApplication.shared.applicationState == .inactive {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard generation == attempt, !Task.isCancelled else { return }
        }
        guard UIApplication.shared.applicationState == .active else { return }
        cameraDenied = mode == .video && AVCaptureDevice.authorizationStatus(for: .video) == .denied
        ready = true
        if mode == .video {
            if cameraGranted { await openCamera(position, attempt: attempt) }
            else { cameraIssue = "Allow camera access in Settings." }
        }
        if generation == attempt { configuring = false }
    }

    private func startMic() {
        guard engine == nil else { return }
        let next = AVAudioEngine()
        guard audio.isInputAvailable else { micIssue = "No microphone input is available."; return }
        let input = next.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            micIssue = "No microphone input is available."
            return
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self, weak next] buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(samples, vDSP_Stride(buffer.stride), &rms, vDSP_Length(buffer.frameLength))
            let value = max(0, min(1, (20 * log10(max(0.001, rms)) + 60) / 60))
            DispatchQueue.main.async { [weak self, weak next] in
                guard let self, let next, self.engine === next else { return }
                self.level = value
            }
        }
        do {
            try next.start()
            engine = next
            micOn = true
            micIssue = ""
        } catch {
            input.removeTap(onBus: 0)
            micIssue = "The microphone could not start."
        }
    }

    private func stopMic() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        micOn = false
        level = 0
    }

    func toggleMic() async {
        guard ready, !requestingMic else { return }
        if micOn {
            stopMic()
            releaseAudio()
            return
        }
        let attempt = generation
        requestingMic = true
        defer { if attempt == generation { requestingMic = false } }
        let granted = await VoicePeer.requestMicrophone()
        guard attempt == generation, !Task.isCancelled else { return }
        guard granted else {
            microphoneDenied = audio.recordPermission == .denied
            micIssue = "Allow microphone access in Settings."
            return
        }
        while UIApplication.shared.applicationState == .inactive {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard attempt == generation, !Task.isCancelled else { return }
        }
        guard UIApplication.shared.applicationState == .active else { return }
        previous = (audio.category, audio.mode, audio.categoryOptions)
        do {
            try audio.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
            try audio.setActive(true)
            route(toSpeaker: speakerOn)
            startMic()
        } catch { micIssue = "The microphone could not start." }
        if !micOn { releaseAudio() }
    }

    func route(toSpeaker enabled: Bool) {
        // A silent preview keeps the route preference until audio starts.
        if previous != nil {
            do {
                try audio.overrideOutputAudioPort(enabled ? .speaker : .none)
            } catch {
                speakerOn = audio.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
                outputIssue = "Could not switch the audio output."
                return
            }
            updateOutputName()
        }
        speakerOn = enabled
        outputIssue = ""
    }

    private func updateOutputName() {
        outputName = audio.currentRoute.outputs.map(\.portName).joined(separator: ", ")
    }

    func routeChanged(_ notification: Notification) {
        guard previous != nil else { return }
        updateOutputName()
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // An accessory change returns the session to automatic routing.
        if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
            speakerOn = false
        }
    }

    var canFlip: Bool {
        cameraOn && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
            position: position == .front ? .back : .front) != nil
    }

    func flip() async {
        guard !configuring, canFlip else { return }
        let attempt = generation
        configuring = true
        await openCamera(position == .front ? .back : .front, attempt: attempt)
        if generation == attempt { configuring = false }
    }

    private func openCamera(_ target: AVCaptureDevice.Position, attempt: Int) async {
        do {
            try await camera.start(position: target)
            guard attempt == generation else { return }
            position = target
            cameraOn = true
            cameraIssue = ""
        } catch {
            if attempt == generation { cameraIssue = error.localizedDescription }
        }
    }

    func stop() {
        generation += 1
        configuring = false
        stopMic()
        camera.stop()
        cameraOn = false
        ready = false
        requestingMic = false
        releaseAudio()
    }

    private func releaseAudio() {
        if let previous {
            try? audio.overrideOutputAudioPort(.none)
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            try? audio.setCategory(previous.0, mode: previous.1, options: previous.2)
            self.previous = nil
        }
        outputIssue = ""
        outputName = ""
    }
}

struct CallPreviewScreen: View {
    let mode: CallPreviewMode
    let person: InboxRow
    let verifyFriendship: () async -> Bool
    @StateObject private var media = CallPreviewMedia()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var sessionRevision = 0
    @State private var paused = false

    var body: some View {
        ZStack {
            if mode == .video {
                Color.black.ignoresSafeArea()
                if media.cameraOn {
                    CameraView(camera: media.camera, mirrored: media.position == .front).ignoresSafeArea()
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                        .ignoresSafeArea().allowsHitTesting(false)
                } else if !paused && !media.configuring && !media.cameraIssue.isEmpty {
                    let icon = Image(systemName: "video.slash").font(.largeTitle)
                        .foregroundStyle(.secondary).frame(width: 64, height: 64)
                    if media.cameraDenied {
                        Button(action: openSettings) { icon }.accessibilityLabel("Open camera settings")
                    } else if AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                              AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: media.position) != nil {
                        Button(action: retry) { icon }.accessibilityLabel("Retry camera")
                    } else {
                        icon.accessibilityLabel("Camera unavailable")
                    }
                }
            } else {
                LinearGradient(colors: [Color(red: 0.03, green: 0.17, blue: 0.24), Color(red: 0.04, green: 0.31, blue: 0.32)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                InboxAvatar(person: person, size: 100)
            }
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(person.string("name")).font(.title.bold())
                    Text(mode.rawValue).font(.subheadline)
                }.padding(.horizontal, 18).padding(.vertical, 9).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                if media.configuring { ProgressView().tint(.white).accessibilityLabel("Checking devices") }
                if paused {
                    Button(action: retry) {
                        Image(systemName: "play.fill").frame(width: 48, height: 48)
                    }.accessibilityLabel("Resume preview")
                } else if media.canFlip {
                    Button { Task { await media.flip() } } label: {
                        Image(systemName: "camera.rotate").frame(width: 48, height: 48)
                    }.accessibilityLabel("Switch camera").disabled(media.configuring)
                }
                if media.micOn {
                    ProgressView(value: media.level).frame(width: 120).tint(.mint).accessibilityLabel("Microphone level")
                }
                HStack(spacing: 18) {
                    Button {
                        media.route(toSpeaker: !media.speakerOn)
                    } label: {
                        NativeArt("call", media.speakerOn ? 6 : 7).scaledToFit().frame(width: 54, height: 54).contentShape(Rectangle())
                    }.accessibilityLabel("Speaker").accessibilityValue(media.speakerOn ? "On" : "Off")
                    .accessibilityHint(media.outputIssue.isEmpty ? media.outputName : media.outputIssue)
                    .disabled(!media.ready || paused)
                    Button { media.stop(); dismiss() } label: {
                        NativeArt("call", 5).scaledToFit().frame(width: 96, height: 54)
                    }.accessibilityLabel("End call")
                    Button {
                        if media.microphoneDenied { openSettings() }
                        else { Task { await media.toggleMic() } }
                    } label: {
                        NativeArt("call", media.micOn ? 8 : 9).scaledToFit().frame(width: 54, height: 54).contentShape(Rectangle())
                    }.accessibilityLabel("Microphone").accessibilityValue(media.micOn ? "On" : "Off").accessibilityHint(media.micIssue)
                    .disabled(!media.ready || paused || media.configuring || media.requestingMic)
                }.buttonStyle(.plain)
            }
            .foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task(id: sessionRevision) {
            guard !paused, phase != .background else { return }
            guard await verifyFriendship(), !Task.isCancelled else { return }
            await media.start(mode)
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                if !(await verifyFriendship()), !Task.isCancelled {
                    media.stop()
                    dismiss()
                    return
                }
            }
        }
        .onChange(of: phase) { next in
            if next == .background { pause() }
            else if next == .active && paused { paused = false; sessionRevision += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            if media.micOn, note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue { pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification, object: media.audio)) { media.routeChanged($0) }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: media.camera.session)) { _ in
            if media.cameraOn { pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: media.camera.session)) { _ in
            if media.cameraOn { pause() }
        }
        .onDisappear { media.stop() }
    }

    private func retry() {
        paused = false
        sessionRevision += 1
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func pause() {
        paused = true
        media.stop()
    }
}

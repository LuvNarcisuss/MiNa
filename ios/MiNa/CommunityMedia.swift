import SwiftUI
import AVKit
import Combine

@MainActor
final class CommunityPlayer: ObservableObject {
    private static weak var active: AVPlayer?
    @Published var player: AVPlayer?
    @Published var playing = false
    @Published var position = 0.0
    @Published var failure = ""
    private var subscriptions: Set<AnyCancellable> = []
    private var observer: Any?

    static func pauseActive() { active?.pause() }

    func open(_ url: URL) {
        close()
        let next = AVPlayer(url: url)
        player = next
        next.publisher(for: \.timeControlStatus).receive(on: RunLoop.main).sink { [weak self, weak next] status in
            guard let self, let next else { return }
            self.playing = status != .paused
            if status != .paused && Self.active !== next {
                Self.active?.pause()
                Self.active = next
            }
        }.store(in: &subscriptions)
        next.currentItem?.publisher(for: \.status).receive(on: RunLoop.main).sink { [weak self] status in
            if status == .failed { self?.failure = "This media could not be played." }
        }.store(in: &subscriptions)
        observer = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main) { [weak self] at in
            Task { @MainActor in self?.position = at.seconds.isFinite ? at.seconds : 0 }
        }
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: next.currentItem)
            .sink { [weak next] _ in next?.seek(to: .zero) }.store(in: &subscriptions)
    }
    func close() {
        subscriptions.removeAll()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil; player?.pause(); player = nil
        failure = ""; position = 0; playing = false
    }
}

struct CommunityMedia: View {
    @EnvironmentObject var app: MiNaAppModel
    let path: String
    let duration: Double
    let voice: Bool
    let remote: Bool
    var caption: String?
    var liked = false
    var onLike: (() -> Void)?
    var openPost: (() -> Void)?
    @State private var showingCaption = false
    @State private var nativeControls = false
    @State private var fullscreen = false
    @State private var openedRequest: String?
    @StateObject private var model = CommunityPlayer()
    @State private var attempt = 0
    private let bars = [9,17,13,25,32,14,21,11,19,29,37,16,22,10,26,34,20,14,25,12,18,30,19,10,24,33,21,15,26,13,31,18]
    var body: some View {
        Group {
            if !voice {
                video
            } else if !model.failure.isEmpty {
                VStack { Text(model.failure); Button("Try again") { attempt += 1 } }
            } else if let player = model.player {
                Button {
                    if model.playing { player.pause() } else { player.play() }
                } label: {
                    HStack {
                        NativeArt("dreams", model.playing ? 18 : 3).scaledToFit().frame(width: 30,height: 30)
                        HStack(spacing: 2) {
                            ForEach(bars.indices, id: \.self) { i in
                                Capsule().fill(Color.white.opacity(Double(i) / Double(bars.count) <= model.position / max(1,duration) ? 1 : 0.65)).frame(height: CGFloat(bars[i]))
                            }
                        }
                        Text(communityClock(model.position > 0.1 ? model.position : duration)).monospacedDigit()
                    }.foregroundStyle(.white).padding(.horizontal,14).frame(minHeight:60).background(Color(red:0.52,green:0.61,blue:0.62), in: RoundedRectangle(cornerRadius:12))
                }.accessibilityLabel(model.playing ? "Pause recording" : "Play recording")
            } else { ProgressView("Opening recording…") }
        }.task(id: mediaRequest) {
            if model.player != nil && openedRequest == mediaRequest { return }
            nativeControls = false
            model.close()
            do {
                let url: URL
                if remote { url = try await app.api.mediaURL(path) }
                else {
                    guard let location = try app.media.resolve(path)["url"] as? String, let file = URL(string: location) else { throw MiNaIssue("This media is unavailable.") }
                    url = file
                }
                try Task.checkCancellation()
                model.open(url)
                openedRequest = mediaRequest
            } catch { if !Task.isCancelled { model.failure = error.localizedDescription } }
        }.onDisappear { if !fullscreen { model.close() } }
    }
    private var mediaRequest: String { "\(path)|\(attempt)" }

    private var video: some View {
        Color.black.aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if !model.failure.isEmpty {
                    VStack {
                        Text(model.failure).font(.footnote).multilineTextAlignment(.center)
                        Button("Try again") { attempt += 1 }
                    }.foregroundStyle(.white).padding(.horizontal)
                } else if let player = model.player {
                    LandscapePlayer(player: player, controls: nativeControls, fullscreen: $fullscreen)
                    if !nativeControls {
                        if let openPost {
                            Button(action: openPost) { Color.clear.contentShape(Rectangle()) }
                                .accessibilityLabel("Open post details")
                        }
                        Button {
                            nativeControls = true
                            player.play()
                        } label: {
                            Image(systemName: "play.fill").foregroundStyle(.white)
                                .frame(width: 46, height: 46).background(.black.opacity(0.42), in: Circle())
                        }.accessibilityLabel("Play video")
                    }
                } else {
                    ProgressView("Opening video…").tint(.white).foregroundStyle(.white)
                }
            }
            .overlay(alignment: .bottom) {
                if !nativeControls, let caption {
                    HStack(alignment: .bottom, spacing: 8) {
                        Button { showingCaption = true } label: {
                            Text(caption).font(.subheadline).lineLimit(3)
                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        }.foregroundStyle(.white)
                        if let onLike {
                            Button(action: onLike) {
                                NativeArt("post", liked ? 5 : 4).scaledToFit()
                                    .frame(width: 37, height: 37).frame(width: 44, height: 44)
                            }.accessibilityLabel(liked ? "Remove like" : "Like")
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 8).padding(.top, 12)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                }
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .onChange(of: model.playing) { playing in
                if !playing && !fullscreen { nativeControls = false }
            }
            .sheet(isPresented: $showingCaption) {
                ScrollView { Text(caption ?? "").frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
    }
}

private struct LandscapePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let controls: Bool
    @Binding var fullscreen: Bool

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let fullscreen: Binding<Bool>
        init(_ fullscreen: Binding<Bool>) { self.fullscreen = fullscreen }

        func playerViewController(_ controller: AVPlayerViewController, willBeginFullScreenPresentationWithCoordinator transition: UIViewControllerTransitionCoordinator) {
            fullscreen.wrappedValue = true
            transition.animate(alongsideTransition: nil) { context in
                if context.isCancelled { self.fullscreen.wrappedValue = false }
            }
        }

        func playerViewController(_ controller: AVPlayerViewController, willEndFullScreenPresentationWithCoordinator transition: UIViewControllerTransitionCoordinator) {
            transition.animate(alongsideTransition: nil) { context in
                if !context.isCancelled { self.fullscreen.wrappedValue = false }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator($fullscreen) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.videoGravity = .resizeAspectFill
        controller.showsPlaybackControls = controls
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        if controller.showsPlaybackControls != controls { controller.showsPlaybackControls = controls }
    }
}

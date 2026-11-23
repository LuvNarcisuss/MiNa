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
    @StateObject private var model = CommunityPlayer()
    @State private var attempt = 0
    private let bars = [9,17,13,25,32,14,21,11,19,29,37,16,22,10,26,34,20,14,25,12,18,30,19,10,24,33,21,15,26,13,31,18]
    var body: some View {
        Group {
            if !model.failure.isEmpty {
                VStack { Text(model.failure); Button("Try again") { attempt += 1 } }
            } else if let player = model.player {
                if voice {
                    Button {
                        if model.playing { player.pause() } else { player.play() }
                    } label: {
                        HStack {
                            NativeArt("dreams", model.playing ? 18 : 3).scaledToFit().frame(width: 30,height: 30)
                            HStack(spacing: 2) {
                                ForEach(bars.indices, id: \.self) { i in
                                    Capsule().fill(Color.teal.opacity(Double(i) / Double(bars.count) <= model.position / max(1,duration) ? 1 : 0.5)).frame(height: CGFloat(bars[i]))
                                }
                            }
                            Text(communityClock(model.position > 0.1 ? model.position : duration)).monospacedDigit()
                        }.padding(8).background(Color.mint.opacity(0.14), in: Capsule())
                    }.accessibilityLabel(model.playing ? "Pause recording" : "Play recording")
                } else { VideoPlayer(player: player).frame(height: 220).cornerRadius(14) }
            } else { ProgressView(voice ? "Opening recording…" : "Opening video…") }
        }.task(id: path + String(attempt)) {
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
            } catch { if !Task.isCancelled { model.failure = error.localizedDescription } }
        }.onDisappear { model.close() }
    }
}

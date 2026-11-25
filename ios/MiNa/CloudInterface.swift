import CoreText
import CryptoKit
import SwiftUI

struct CloudPolicy: Decodable {
    let title: String
    let sections: [[String]]
}

struct JournalStory: Decodable {
    let id, title, summary, body, cover: String
}

struct EditorialLibrary: Decodable {
    let stories: [JournalStory]
    let sounds: [RoomSound]
}

struct InterfaceCatalog: Decodable {
    struct Sound: Decodable {
        let seconds: Double
        let sha256: String
    }
    let images: [String: Data]
    let font: Data
    let policies: [String: CloudPolicy]
    let sounds: [String: Sound]
}

enum CloudInterface {
    static private(set) var catalog: InterfaceCatalog?
    static private(set) var library: EditorialLibrary?
    static let transport: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    static func bytes(_ url: URL) async throws -> Data {
        let (data, response) = try await transport.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MiNaIssue("This media is unavailable. Please try again.")
        }
        return data
    }

    static func asset(_ name: String, digest: String) async throws -> Data {
        let url = await MiNaAPI.origin.appendingPathComponent("storage/v1/object/public/mina-art/v1").appendingPathComponent(name)
        let data = try await bytes(url)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest else {
            throw MiNaIssue("The download was incomplete. Please try again.")
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, file: String, digest: String) async throws -> T {
        let data = try await asset(file, digest: digest)
        return try JSONDecoder().decode(type, from: data)
    }

    @MainActor static func load() async throws {
        if catalog != nil, library != nil { return }
        async let art = decode(InterfaceCatalog.self, file: "interface.json", digest: "107c35e16b57a65be794a5cd5a87e09412973b956da07c6989d05f4ef9cf6d51")
        async let editorial = decode(EditorialLibrary.self, file: "library.json", digest: "c4947dc8fdfe2fbb180277701bb977d3b1665d2916319b9e6d3d5e4f9dcb3959")
        let (release, collection) = try await (art, editorial)
        try Task.checkCancellation()
        guard !collection.sounds.isEmpty, collection.sounds.allSatisfy({ release.sounds[$0.id] != nil }),
              let provider = CGDataProvider(data: release.font as CFData), let font = CGFont(provider) else {
            throw MiNaIssue("The media catalog could not be opened.")
        }
        CTFontManagerRegisterGraphicsFont(font, nil)
        catalog = release
        library = collection
    }
}

struct CloudLaunch: View {
    @State private var ready = false
    @State private var failure = false
    @State private var attempt = 0

    var body: some View {
        if ready {
            MiNaRoot()
        } else {
            ZStack {
                Color(red: 0.05, green: 0.24, blue: 0.42).ignoresSafeArea()
                VStack(spacing: 18) {
                    Text("MiNa").font(.largeTitle.bold())
                    if failure {
                        Button("Try again") { failure = false; attempt += 1 }.buttonStyle(.bordered)
                    } else {
                        ProgressView().tint(.white).accessibilityLabel("Loading MiNa")
                    }
                }.foregroundStyle(.white).multilineTextAlignment(.center).padding()
            }.minaAlert(failure ? "Unable to load MiNa. Check your connection and try again." : "").task(id: attempt) {
                do { try await CloudInterface.load(); ready = true }
                catch { if !Task.isCancelled { failure = true } }
            }.preferredColorScheme(.dark)
        }
    }
}

// Only the current view retains downloaded private portraits.
struct CloudPortraitImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @State private var phase = AsyncImagePhase.empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    init<Loaded: View, Placeholder: View>(url: URL?, @ViewBuilder content: @escaping (Image) -> Loaded,
                                         @ViewBuilder placeholder: @escaping () -> Placeholder) where Content == _ConditionalContent<Loaded, Placeholder> {
        self.init(url: url) { phase in
            if let image = phase.image { content(image) } else { placeholder() }
        }
    }

    var body: some View {
        content(phase).task(id: url) {
            phase = .empty
            guard let url else { return }
            do {
                let data = try await CloudInterface.bytes(url)
                try Task.checkCancellation()
                guard let image = UIImage(data: data) else { throw MiNaIssue("This photo could not be opened.") }
                phase = .success(Image(uiImage: image))
            } catch {
                if !Task.isCancelled { phase = .failure(error) }
            }
        }
    }
}

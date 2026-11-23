import SwiftUI
import UIKit

struct NativeRoute: Hashable {
    let name: String
    var id: String? = nil
}

@MainActor
final class MiNaAppModel: ObservableObject {
    let api = MiNaAPI()
    let media = DeviceMedia()
    @Published var signedIn = false
    @Published var busy = false
    @Published var accountError = ""
    @Published var tab = "rooms"
    @Published var path: [NativeRoute] = []
    @Published private var snapshot: [String: Any] = [:]
    private var restored = false
    private let unlocked = "mina.native.unlocked"
    private let deletionOwner = "mina.native.deletedOwner"

    var route: NativeRoute { path.last ?? NativeRoute(name: tab) }
    func go(_ name: String, _ id: String? = nil) {
        if ["rooms", "feed", "ai", "messages", "profile"].contains(name) {
            tab = name
            path = []
            return
        }
        let next = NativeRoute(name: name, id: id)
        if next != route { path.append(next) }
    }

    func back() { if !path.isEmpty { path.removeLast() } }
    func state(_ key: String) -> Any? { snapshot[key] }
    func save(_ key: String, _ value: Any?) throws {
        try saveChanges([key: value])
    }
    func saveChanges(_ values: [String: Any?]) throws {
        guard signedIn, AccountLibrary.owner != "Device" else { throw MiNaIssue("Sign in to save your changes.") }
        var updated = snapshot
        for (key, value) in values { updated[key] = value }
        try AccountLibrary.saveState(updated)
        snapshot = updated
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        // Pre-native releases exported temporary media links into this cache.
        // The account library and its original recordings live in Application Support.
        if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let oldCache = cache.appendingPathComponent("MiNaPages", isDirectory: true)
            if FileManager.default.fileExists(atPath: oldCache.path) { try? FileManager.default.removeItem(at: oldCache) }
        }
        do { try finishDeletion() } catch { accountError = error.localizedDescription; return }
        if UserDefaults.standard.bool(forKey: unlocked) { await enter(create: false) }
    }

    func enter(create: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try finishDeletion()
            try await api.signIn(allowCreation: create)
            AccountLibrary.owner = try SessionStore.owner(SessionStore.read())
            snapshot = try AccountLibrary.loadState()
            UserDefaults.standard.set(true, forKey: unlocked)
            accountError = ""
            path = []
            tab = "rooms"
            signedIn = true
        } catch { accountError = error.localizedDescription }
    }

    func leave(delete: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try media.prepareAccountChange()
            if delete {
                if UserDefaults.standard.string(forKey: deletionOwner) == nil {
                    try await api.deleteAccount()
                    UserDefaults.standard.set(AccountLibrary.owner, forKey: deletionOwner)
                }
                try finishDeletion()
            }
            api.close()
            signedIn = false
            UserDefaults.standard.set(false, forKey: unlocked)
            snapshot = [:]
            AccountLibrary.owner = "Device"
            tab = "rooms"
            path = []
            accountError = ""
        } catch { accountError = error.localizedDescription }
    }

    private func finishDeletion() throws {
        guard let value = UserDefaults.standard.string(forKey: deletionOwner), let owner = UUID(uuidString: value) else { return }
        AccountLibrary.owner = owner.uuidString
        try media.clear()
        try SessionStore.write(nil)
        UserDefaults.standard.removeObject(forKey: unlocked)
        UserDefaults.standard.removeObject(forKey: deletionOwner)
        AccountLibrary.owner = "Device"
    }

    func pick(_ kind: String) async throws -> [String: Any] {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var presenter = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = presenter?.presentedViewController { presenter = next }
        return try await withCheckedThrowingContinuation { continuation in
            media.pick(kind, presenter: presenter) { continuation.resume(with: $0) }
        }
    }
}

private let artworkCache = NSCache<NSString, UIImage>()

func nativeArtwork(_ group: String, _ name: String) -> Image {
    let key = "\(group)/\(name)" as NSString
    if let image = artworkCache.object(forKey: key) { return Image(uiImage: image).resizable() }
    if let url = Bundle.main.url(forResource: name, withExtension: "webp", subdirectory: "Artwork/" + group),
       let image = UIImage(contentsOfFile: url.path) {
        artworkCache.setObject(image, forKey: key)
        return Image(uiImage: image).resizable()
    }
    return Image(uiImage: UIImage()).resizable()
}

func NativeArt(_ group: String, _ number: Int) -> Image { nativeArtwork(group, String(number)) }

struct NativePortrait: View {
    @EnvironmentObject var app: MiNaAppModel
    let path: String
    var size: CGFloat = 62
    @State private var url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { NativeArt("edit", 4).scaledToFill() }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: path) {
            url = nil
            if !path.isEmpty {
                let result = try? await app.api.mediaURL(path)
                if !Task.isCancelled { url = result }
            }
        }
    }
}

struct MiNaRoot: View {
    @EnvironmentObject var app: MiNaAppModel
    private let tabs = [("rooms", "Rooms", 1), ("feed", "Feed", 2), ("ai", "AI Companion", 5),
                        ("messages", "Messages", 3), ("profile", "Profile", 4)]

    var body: some View {
        NavigationStack(path: $app.path) {
            Group {
                if app.signedIn { destination(NativeRoute(name: app.tab)) }
                else { WelcomeScreen() }
            }
            .navigationDestination(for: NativeRoute.self) { route in destination(route) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if app.signedIn && app.path.isEmpty {
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { index in
                        let item = tabs[index]
                        Button { app.tab = item.0 } label: {
                            NativeArt("tabs", item.2 == 5 || app.tab == item.0 ? item.2 : item.2 + 5)
                                .scaledToFit().frame(width: item.2 == 5 ? 46 : 26, height: 44)
                                .frame(maxWidth: .infinity).contentShape(Rectangle())
                        }
                        .accessibilityLabel(item.1)
                        .accessibilityAddTraits(app.tab == item.0 ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4).background(.regularMaterial)
            }
        }
        .overlay(alignment: .top) { if app.signedIn { IncomingCallBanner() } }
        .tint(Color(red: 0.04, green: 0.43, blue: 0.43))
        .task { await app.restore() }
    }

    @ViewBuilder private func destination(_ route: NativeRoute) -> some View {
        switch route.name.components(separatedBy: ".").first {
        case "rooms": RoomsScreen(route: route)
        case "feed", "dreams": CommunityScreen(route: route)
        case "messages": MessagesScreen(route: route)
        case "profile", "person": ProfileScreen(route: route)
        case "ai": CompanionScreen(route: route)
        case "wallet", "level", "store": EconomyScreen(route: route)
        case "legal", "support", "delete", "logout": AccountScreen(route: route)
        default: Text("This page is unavailable.")
        }
    }
}

private struct WelcomeScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    @State private var consent = false
    var body: some View {
        ZStack {
            nativeArtwork("signIn", "welcome").ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 14) {
                Spacer()
                Text("MiNa").font(.system(size: 42, weight: .heavy))
                Text("Sleep better.\nTalk deeper.").multilineTextAlignment(.center)
                Spacer().frame(height: 30)
                Button(app.busy ? "Connecting…" : "Continue") { Task { await app.enter(create: true) } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!consent || app.busy)
                Toggle("I agree to the terms and privacy policy", isOn: $consent).fixedSize(horizontal: false, vertical: true)
                HStack { Button("Terms") { app.go("legal.terms") }; Button("Privacy Policy") { app.go("legal.privacy") } }
                if !app.accountError.isEmpty { Text(app.accountError).font(.footnote) }
            }
            .foregroundStyle(.white).padding(28).shadow(color: .black.opacity(0.35), radius: 3)
        }.toolbar(.hidden, for: .navigationBar)
    }
}

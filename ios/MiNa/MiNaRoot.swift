import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NativeRoute: Hashable {
    let name: String
    var id: String? = nil
}

enum EntryMode {
    case signIn, signUp, link

    var title: String {
        switch self {
        case .signIn: return "Sign in"
        case .signUp: return "Create account"
        case .link: return "Link this account"
        }
    }
}

@MainActor
final class MiNaAppModel: ObservableObject {
    let api: MiNaAPI
    let gifts: GiftSpending
    let wallet: WalletStore

    init() {
        let api = MiNaAPI()
        self.api = api
        let wallet = WalletStore()
        self.wallet = wallet
        self.gifts = GiftSpending(wallet: wallet, api: api)
        api.sessionExpired = { [weak self] in
            guard let self, self.signedIn else { return false }
            try? self.media.prepareAccountChange()
            self.closeSession()
            self.accountError = "Your session has expired. Please sign in again."
            return true
        }
    }
    let media = DeviceMedia()
    private var draftTransfers: [String: Task<Void, Error>] = [:]
    @Published var signedIn = false
    @Published var busy = false
    @Published var accountError = ""
    @Published var entryMode: EntryMode = .signIn
    @Published var showingRegistrationSuccess = false
    @Published var entryNotice = ""
    @Published var companionTopic: Int?
    @Published var tab = "rooms"
    @Published var path: [NativeRoute] = []
    @Published private var snapshot: [String: Any] = [:]
    @Published private(set) var safetyRevision = 0
    @Published private(set) var rootRevision = 0
    @Published var safetyNotice: String?
    private var blockNotice: (tab: String, text: String)?
    private var restored = false

    func safetyChanged() { safetyRevision += 1 }

    func blockMember(_ id: String, name: String) async throws {
        let owner = api.userID
        let origin = tab
        guard signedIn, id != owner else { throw MiNaIssue("This listener cannot be blocked.") }
        try await api.rest("blocks", method: "POST", body: ["owner_id": owner, "blocked_id": id], prefer: "resolution=ignore-duplicates")
        guard signedIn, api.userID == owner else { return }
        CommunityPlayer.pauseActive()
        tab = origin
        blockNotice = (origin, (name.isEmpty ? "Listener" : name) + " has been blocked.")
        path.removeAll()
        rootRevision += 1
        safetyChanged()
    }

    func didRefreshRoot(_ name: String) {
        guard path.isEmpty, tab == name, let pending = blockNotice, pending.tab == name else { return }
        blockNotice = nil
        safetyNotice = pending.text
    }
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
        busy = true
        defer { busy = false }
        do {
            try finishDeletion()
            try SessionStore.write(nil, to: .password)
            UserDefaults.standard.removeObject(forKey: "mina.native.unlocked")
        } catch { accountError = error.localizedDescription }
    }

    func submit(email input: String, password: String, confirmation: String) async {
        guard restored, !busy, !signedIn, !showingRegistrationSuccess else { return }
        accountError = ""
        entryNotice = ""
        let email = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard MiNaAPI.validEmail(email) else {
            accountError = "Enter a valid email address."
            return
        }
        guard !password.isEmpty else { accountError = "Enter your password."; return }
        if entryMode == .signUp && !password.utf8.elementsEqual(confirmation.utf8) {
            accountError = "Passwords do not match."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try finishDeletion()
            switch entryMode {
            case .signIn:
                try await api.signIn(email: email, password: password)
            case .signUp:
                try await api.signUp(email: email, password: password)
                api.close()
                showingRegistrationSuccess = true
                return
            case .link:
                let legacy = MiNaAPI(slot: .legacy)
                guard try await legacy.linkLegacyAccount(email: email, password: password) else {
                    entryNotice = "Open the confirmation link in your email, then return here and finish linking with the same email and your chosen password."
                    return
                }
                try await api.signIn(email: email, password: password, expectedOwner: legacy.userID)
            }
            try await openAccount()
        } catch {
            api.close()
            accountError = error.localizedDescription
        }
    }

    private func openAccount() async throws {
        guard let owner = UUID(uuidString: api.userID) else { throw MiNaIssue("Sign in to continue.") }
        _ = try await api.rest("rpc/bootstrap", method: "POST", body: [:] as [String: String])
        AccountLibrary.owner = owner.uuidString
        do {
            snapshot = try AccountLibrary.loadState()
            try removeLegacySession(for: owner)
        } catch {
            AccountLibrary.owner = "Device"
            throw error
        }
        accountError = ""
        entryNotice = ""
        path = []
        tab = "rooms"
        signedIn = true
        wallet.setOwner(api.userID)
        let account = api.userID
        Task {
            for key in ["postDraft", "dreamDraft"] {
                for field in ["media", "candidate"] {
                    // The editor offers a retry for an interrupted capture.
                    try? await uploadDraft(key, field: field, owner: account)
                }
            }
        }
    }

    /// Commit the cloud reference before releasing the capture. Re-read the journal after
    /// the upload so a changed caption, replaced draft or account switch is preserved.
    func uploadDraft(_ key: String, field: String, owner: String) async throws {
        guard api.userID == owner, signedIn else { throw MiNaIssue("Sign in to continue.") }
        let journalKey = "community.drafts." + owner
        guard let journal = state(journalKey) as? CommunityRow, let draft = journal[key] as? CommunityRow,
              let item = draft[field] as? CommunityRow, item.communityString("path").isEmpty,
              let id = item["id"] as? String else { return }
        let transferID = [owner, key, field, id].joined(separator: ":")
        if let pending = draftTransfers[transferID] { return try await pending.value }
        let task = Task { try await commitCapture(id, owner: owner, key: key, field: field) }
        draftTransfers[transferID] = task
        defer { draftTransfers[transferID] = nil }
        try await task.value
    }

    private func commitCapture(_ id: String, owner: String, key: String, field: String) async throws {
        let journalKey = "community.drafts." + owner
        guard owner == api.userID else { throw CancellationError() }
        guard let file = try media.storedAsset(id) else { throw MiNaIssue("The unfinished capture is unavailable. Choose or record it again.") }
        let data = try await Task.detached { try Data(contentsOf: file, options: .mappedIfSafe) }.value
        guard !data.isEmpty, data.count <= 50 * 1024 * 1024 else { throw MiNaIssue("Choose a file of 50 MB or less.") }
        guard owner == api.userID else { throw CancellationError() }
        let ext = file.pathExtension.lowercased()
        let path = try await api.upload(data, type: UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream",
                                        extension: ext, id: id)
        guard owner == api.userID, signedIn else { throw CancellationError() }
        guard var latest = state(journalKey) as? CommunityRow, var current = latest[key] as? CommunityRow,
              var ref = current[field] as? CommunityRow, ref["id"] as? String == id else {
            try await discardUnusedCapture(path)
            return
        }
        ref["path"] = path
        current[field] = ref
        latest[key] = current
        try save(journalKey, latest)
        try media.remove(id)
    }

    func discardUnusedCapture(_ path: String) async throws {
        let owner = api.userID
        guard !owner.isEmpty, path.hasPrefix(owner + "/") else { return }
        let drafts = state("community.drafts." + owner) as? CommunityRow ?? [:]
        for case let draft as CommunityRow in drafts.values {
            for field in ["media", "candidate"] {
                if (draft[field] as? CommunityRow)?["path"] as? String == path { return }
            }
        }
        try await api.removeUnusedCapture(path, owner: owner)
    }

    private func removeLegacySession(for owner: UUID) throws {
        if try SessionStore.owner(SessionStore.read(.legacy)) == owner.uuidString {
            try SessionStore.write(nil, to: .legacy)
        }
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
            } else {
                api.signOut()
            }
            closeSession()
        } catch { accountError = error.localizedDescription }
    }

    private func closeSession() {
        wallet.setOwner("")
        api.close()
        blockNotice = nil
        safetyNotice = nil
        signedIn = false
        companionTopic = nil
        entryMode = .signIn
        entryNotice = ""
        snapshot = [:]
        AccountLibrary.owner = "Device"
        tab = "rooms"
        path = []
        accountError = ""
    }

    private func finishDeletion() throws {
        guard let value = UserDefaults.standard.string(forKey: deletionOwner), let owner = UUID(uuidString: value) else { return }
        AccountLibrary.owner = owner.uuidString
        try DeviceWallet.erase(owner: owner.uuidString)
        try media.clear()
        try removeLegacySession(for: owner)
        try SessionStore.write(nil, to: .password)
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
    if let data = CloudInterface.catalog?.images[key as String],
       let image = UIImage(data: data) {
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
        CloudPortraitImage(url: url) { phase in
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

    private var statusBarScheme: ColorScheme {
        let nightHeaders = ["rooms", "feed", "ai", "ai.chat", "messages", "profile",
                            "rooms.search", "rooms.create", "rooms.stage", "rooms.live"]
        if !app.signedIn && app.path.isEmpty { return .dark }
        return nightHeaders.contains(app.route.name) ? .dark : .light
    }

    var body: some View {
        NavigationStack(path: $app.path) {
            Group {
                if app.signedIn { destination(NativeRoute(name: app.tab)).id(app.rootRevision) }
                else { WelcomeScreen() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if app.signedIn && app.tab == "rooms" && app.path.isEmpty {
                    Button { app.go("rooms.create") } label: {
                        NativeArt("home", 21).scaledToFit().frame(width: 60, height: 62)
                    }
                    .buttonStyle(.plain).padding(.trailing, 17).padding(.bottom, 13)
                    .accessibilityLabel("Create a room")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if app.signedIn && app.path.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(tabs.indices, id: \.self) { index in
                            let item = tabs[index]
                            let highlighted = item.2 == 5 || app.tab == item.0
                            Button { app.tab = item.0 } label: {
                                NativeArt("tabs", highlighted ? item.2 : item.2 + 5)
                                    .renderingMode(highlighted ? .original : .template)
                                    .foregroundStyle(Color(red: 0.34, green: 0.41, blue: 0.48))
                                    .scaledToFit().frame(width: item.2 == 5 ? 41 : 24, height: 44)
                                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                            }
                            .accessibilityLabel(item.1)
                            .accessibilityAddTraits(app.tab == item.0 ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 20).fill(.white).shadow(color: .black.opacity(0.07), radius: 2, y: -1)
                            .padding(.bottom, -24).ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .navigationDestination(for: NativeRoute.self) { route in destination(route) }
        }
        .id(app.signedIn)
        .accessibilityHidden(app.companionTopic != nil)
        .overlay { if app.signedIn, let topic = app.companionTopic { CompanionTopicOverlay(topic: topic) } }
        .overlay(alignment: .top) { if app.signedIn { IncomingCallBanner() } }
        .tint(Color(red: 0.04, green: 0.43, blue: 0.43))
        .environment(\.colorScheme, .light)
        .preferredColorScheme(statusBarScheme)
        .alert("Community safety", isPresented: Binding(get: { app.safetyNotice != nil }, set: { if !$0 { app.safetyNotice = nil } })) {
            Button("OK") { app.safetyNotice = nil }
        } message: { Text(app.safetyNotice ?? "") }
        .task { await app.restore() }
    }

    @ViewBuilder private func destination(_ route: NativeRoute) -> some View {
        switch route.name.components(separatedBy: ".").first {
        case "rooms": RoomsScreen(route: route)
        case "feed", "dreams": CommunityScreen(route: route)
        case "messages": MessagesScreen(route: route)
        case "profile", "person": ProfileScreen(route: route)
        case "ai": CompanionScreen(route: route)
        case "wallet": WalletScreen(store: app.wallet)
        case "level", "store": EconomyScreen(route: route)
        case "legal", "support", "delete", "logout": AccountScreen(route: route)
        default: Color.clear.minaAlert("This page is unavailable.")
        }
    }
}

private struct WelcomeScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    private enum Field { case email, password, confirmation }
    @FocusState private var focused: Field?
    @State private var lastField: Field?
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var consent = false

    private var emailIsValid: Bool {
        MiNaAPI.validEmail(email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var passwordsMatch: Bool {
        password.utf8.elementsEqual(confirmation.utf8)
    }

    private func validate(_ field: Field?) {
        if field == .email && !email.isEmpty && !emailIsValid {
            AppAlerts.shared.show("Enter a valid email address.")
        } else if field == .confirmation && !confirmation.isEmpty && !passwordsMatch {
            AppAlerts.shared.show("Passwords do not match.")
        }
    }

    private var canSubmit: Bool {
        consent && !app.busy && emailIsValid && !password.isEmpty &&
            (app.entryMode != .signUp || passwordsMatch)
    }

    private let mint = Color(red: 0.68, green: 1, blue: 0.87)
    private let midnight = Color(red: 0.025, green: 0.085, blue: 0.19)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 16)
                    Text("MiNa")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: midnight.opacity(0.55), radius: 8, y: 3)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 12) {
                        VStack(spacing: 0) {
                            credentialRow("Email", fieldID: .email) {
                                TextField("", text: $email, prompt: fieldPrompt("you@example.com"))
                                    .keyboardType(.emailAddress).textContentType(.username)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($focused, equals: .email).submitLabel(.next)
                                    .onSubmit { focused = .password }
                                    .accessibilityLabel("Email address")
                            }
                            credentialDivider
                            credentialRow("Password", fieldID: .password) {
                                SecureField("", text: $password, prompt: fieldPrompt("Password"))
                                    .textContentType(app.entryMode == .signIn ? .password : .newPassword)
                                    .focused($focused, equals: .password)
                                    .submitLabel(app.entryMode == .signUp ? .next : .go)
                                    .onSubmit {
                                        if app.entryMode == .signUp { focused = .confirmation }
                                        else { submit() }
                                    }.accessibilityLabel("Password")
                            }
                            if app.entryMode == .signUp {
                                credentialDivider
                                credentialRow("Confirm password", fieldID: .confirmation) {
                                    SecureField("", text: $confirmation, prompt: fieldPrompt("Confirm password"))
                                        .textContentType(.newPassword)
                                        .focused($focused, equals: .confirmation).submitLabel(.go)
                                        .onSubmit { submit() }.accessibilityLabel("Confirm password")
                                }
                            }
                        }
                        .background(midnight.opacity(0.64), in: RoundedRectangle(cornerRadius: 22))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(focused == nil ? .white.opacity(0.28) : mint.opacity(0.75), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        consentRow
                        if !app.entryNotice.isEmpty { Text(app.entryNotice).font(.footnote) }
                        Button(action: submit) {
                            Group {
                                if app.busy { ProgressView().tint(midnight) }
                                else { Text(app.entryMode.title).font(.headline.weight(.bold)) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(midnight)
                            .background(
                                LinearGradient(colors: [mint, Color(red: 0.50, green: 0.85, blue: 1)],
                                               startPoint: .leading, endPoint: .trailing), in: Capsule()
                            )
                        }
                        .disabled(!canSubmit).opacity(canSubmit || app.busy ? 1 : 0.72)
                        if app.entryMode == .signIn {
                            modeButton("Create account", .signUp)
                        } else {
                            modeButton("Back to sign in", .signIn)
                        }
                    }
                    .padding(.top, 22)
                    .disabled(app.busy)
                }
                .foregroundStyle(.white).tint(mint).buttonStyle(.plain)
                .padding(.horizontal, 26).padding(.bottom, 12)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .bottom)
            }.scrollDismissesKeyboard(.interactively)
        }
        .background {
            GeometryReader { sky in
                nativeArtwork("signIn", "welcome").scaledToFill()
                    .frame(width: sky.size.width, height: sky.size.height).clipped()
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.26),
                            .init(color: midnight.opacity(0.25), location: 0.45),
                            .init(color: midnight.opacity(0.83), location: 0.68),
                            .init(color: midnight.opacity(0.95), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(focused == nil ? Color.clear : midnight.opacity(0.33))
            }.ignoresSafeArea().accessibilityHidden(true)
        }
        .toolbar(.hidden, for: .navigationBar)
        .minaAlert(app.accountError)
        .onChange(of: focused) { next in
            let previous = lastField
            lastField = next
            if previous != next { validate(previous) }
        }
        .alert("Account created", isPresented: $app.showingRegistrationSuccess) {
            Button("OK") { app.entryMode = .signIn }
        } message: {
            Text("You can now sign in with your email and password.")
        }
        .onChange(of: app.entryMode) { _ in
            focused = nil
            password = ""
            confirmation = ""
        }
    }

    private var credentialDivider: some View {
        Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            .padding(.horizontal, 18).accessibilityHidden(true)
    }

    private func fieldPrompt(_ text: String) -> Text {
        Text(text).foregroundColor(.white.opacity(0.65))
    }

    private func credentialRow<Content: View>(_ title: String, fieldID: Field, @ViewBuilder field: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
                .foregroundStyle(focused == fieldID ? mint : .white.opacity(0.85)).accessibilityHidden(true)
            field().font(.body).textFieldStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focused = fieldID }
    }

    private var consentRow: some View {
        HStack(alignment: .center, spacing: 2) {
            Button {
                consent.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: consent ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(consent ? mint : .white.opacity(0.85))
                    Text("I agree to the")
                }.frame(minHeight: 44)
            }
            .accessibilityLabel("I agree to the Terms and Privacy Policy")
            .accessibilityValue(consent ? "Agreed" : "Not agreed")
            Button { app.go("legal.terms") } label: { Text("Terms").underline().padding(.horizontal, 2).frame(minHeight: 44) }.foregroundStyle(mint)
            Text("and")
            Button { app.go("legal.privacy") } label: { Text("Privacy Policy").underline().padding(.horizontal, 2).frame(minHeight: 44) }.foregroundStyle(mint)
        }
        .font(.footnote.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeButton(_ title: String, _ mode: EntryMode) -> some View {
        Button(title) {
            app.entryMode = mode
            app.accountError = ""
            app.entryNotice = ""
        }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
    }

    private func submit() {
        guard canSubmit else {
            validate(!emailIsValid ? .email : .confirmation)
            return
        }
        focused = nil
        Task { await app.submit(email: email, password: password, confirmation: confirmation) }
    }
}

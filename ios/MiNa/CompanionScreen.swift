import SwiftUI

struct CompanionScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    private let topics = ["Sleep Tips", "Emotion", "Life Advice"]

    var body: some View {
        if route.name == "ai.chat" { CompanionConversation() }
        else {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack {
                    Color.clear.background(alignment: .top) {
                        NativeArt("ai", 1)
                            .frame(width: width, height: height + geometry.safeAreaInsets.top + 86)
                            .offset(y: -geometry.safeAreaInsets.top)
                    }.accessibilityHidden(true)
                    Button { app.go("ai.chat") } label: {
                        NativeArt("ai", 7).scaledToFit().frame(width: width * 0.78)
                    }
                    .accessibilityLabel("Start chat")
                    .position(x: width / 2, y: height * 0.665)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Popular topics").font(.subheadline.weight(.medium))
                        HStack(spacing: 10) {
                            ForEach(topics.indices, id: \.self) { index in
                                Button { app.companionTopic = index } label: {
                                    NativeArt("ai", [11, 8, 9][index]).scaledToFit()
                                }.accessibilityLabel(topics[index])
                            }
                        }
                    }.padding(.horizontal, 18)
                        .position(x: width / 2, y: height * 0.875)
                }.buttonStyle(.plain)
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct CompanionTopicOverlay: View {
    @EnvironmentObject var app: MiNaAppModel
    let topic: Int
    private let descriptions = [
        "Sleep Tips. Keep a regular sleep schedule, reduce screen time, relax before bed, and make your bedroom comfortable.",
        "Emotion. Allow your emotions, relax, share your feelings, notice positive moments, and get enough rest.",
        "Life Advice. Be kind to yourself, take breaks, stay hydrated, move regularly, and make time for what you enjoy."
    ]

    var body: some View {
        let group = ["sleepTips", "emotion", "life"][topic]
        GeometryReader { geometry in
            VStack(spacing: 5) {
                Spacer(minLength: 0)
                NativeArt(group, topic == 2 ? 2 : 1).scaledToFit()
                    .accessibilityLabel(descriptions[topic])
                Button { app.companionTopic = nil } label: {
                    NativeArt(group, topic == 2 ? 3 : 2).scaledToFit().frame(width: geometry.size.width * 0.55)
                }.accessibilityLabel("Done")
                Button { app.companionTopic = nil } label: {
                    NativeArt(group, topic == 2 ? 1 : 3).frame(width: 21, height: 21)
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("Close topic")
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity).buttonStyle(.plain)
        }
        .background { Color.black.opacity(0.58).ignoresSafeArea().onTapGesture { app.companionTopic = nil } }
        .accessibilityAddTraits(.isModal)
    }
}

private struct CompanionConversation: View {
    @EnvironmentObject var app: MiNaAppModel
    @State private var lines: [[String: String]] = []
    @State private var prompt = ""
    @State private var failure = ""
    @State private var busy = false
    @State private var help = false
    @State private var reminder = true
    @State private var expiry: Date?
    @State private var sharingAccepted = false
    private let prompts = ["Help me wind down", "Give me a gentle writing prompt", "Tell me a short bedtime story"]

    @State private var showEmoji = false
    @State private var confirmSession = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { clock in
            let remaining = max(0, Int(ceil(expiry?.timeIntervalSince(clock.date) ?? 0)))
            VStack(spacing: 8) {
                HStack {
                    Button { app.back() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Back")
                    Spacer()
                    Button { help = true } label: {
                        NativeArt("aiChat", 3).frame(width: 22, height: 22).frame(width: 44, height: 44)
                    }.accessibilityLabel("About")
                }.foregroundStyle(.white)
                NativeArt("aiChat", 2).scaledToFit().frame(maxHeight: 138).accessibilityLabel("AI companionship")
                if remaining == 0 || !sharingAccepted {
                    Button(remaining == 0 ? "Begin a free 60-minute session" : "Resume free session") { confirmSession = true }
                        .buttonStyle(.borderedProminent).disabled(busy)
                } else {
                    HStack {
                        NativeArt("aiChat", 4).frame(width: 16, height: 16)
                        Text(String(format: "%d:%02d remaining", remaining / 60, remaining % 60)).monospacedDigit()
                    }.font(.caption.weight(.semibold))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            if lines.isEmpty {
                                CompanionBubble(text: "What’s on your mind tonight?", own: false, timestamp: nil, isGreeting: true)
                            }
                            ForEach(lines.indices, id: \.self) { index in
                                let line = lines[index]
                                CompanionBubble(text: line["text"] ?? "", own: line["role"] == "user",
                                                timestamp: line["created_at"]).equatable().id(index)
                            }
                        }.padding(.vertical, 8)
                    }.onChange(of: lines.count) { _ in if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) } }
                }
                if !failure.isEmpty { Text(failure).font(.footnote).foregroundStyle(.red) }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prompts, id: \.self) { idea in
                        Button(idea) { update(idea) }.font(.footnote)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).disabled(busy)
                if showEmoji {
                    ReactionPicker(includesHeartHands: false) { update(prompt + $0) }
                }
                HStack(spacing: 6) {
                    Button { showEmoji.toggle() } label: { NativeArt("aiChat", 5).frame(width: 32, height: 32) }
                        .accessibilityLabel("Choose an emoji")
                    TextField("Share a thought…", text: Binding(get: { prompt }, set: update)).font(ReactionPicker.textFont(for: prompt))
                    if busy { ProgressView() }
                    Button { Task { await send() } } label: { NativeArt("aiChat", 6).scaledToFit().frame(width: 64) }
                        .disabled(busy || !sharingAccepted || remaining == 0 || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send")
                }.padding(.horizontal, 8).background(.white, in: Capsule())
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 6)
            .overlay {
                if help || confirmSession || (remaining > 0 && remaining < 600 && reminder) {
                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 18) {
                            Text(help ? "About this conversation" : confirmSession ? "Start your session?" : "Session reminder").font(.title3.bold())
                            Text(help ? Companion.disclosure : confirmSession ? "Sessions last 60 minutes and are free. " + Companion.disclosure : "Less than 10 minutes remain in your session.")
                                .font(.subheadline).multilineTextAlignment(.center)
                            Button(confirmSession ? "Agree and continue" : "Got it") {
                                if confirmSession { confirmSession = false; Task { await activate() } }
                                else if help { help = false } else { reminder = false }
                            }.frame(maxWidth: .infinity).padding(12).background(LinearGradient(colors: [.mint, .cyan], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            if confirmSession { Button("Later") { confirmSession = false } }
                        }.padding(24).frame(maxWidth: .infinity).background {
                            LinearGradient(colors: [Color(red: 0.83, green: 0.96, blue: 0.86), Color(red: 0.87, green: 0.98, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(RoundedRectangle(cornerRadius: 22)).ignoresSafeArea(edges: .bottom)
                        }
                    }
                }
            }
        }
        .background { NativeArt("aiChat", 1).ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            lines = app.state("companion.history") as? [[String: String]] ?? []
            prompt = app.state("companion.draft") as? String ?? ""
        }
        .task {
            do {
                let rows = try await app.api.rows("companion_sessions?select=expires_at&owner_id=eq." + app.api.userID)
                if expiry == nil { expiry = expiration(rows.first?["expires_at"]) }
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }

    private func expiration(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return date.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func update(_ value: String) {
        let next = String(value.prefix(1600))
        do { try app.save("companion.draft", next); prompt = next }
        catch { failure = error.localizedDescription }
    }

    private func activate() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await app.api.rest("rpc/open_companion_session", method: "POST", body: [String: String]())
            guard let end = expiration(result) else {
                throw MiNaIssue("The session expiration could not be read.")
            }
            sharingAccepted = true
            expiry = end
            reminder = true
            failure = ""
        } catch { failure = error.localizedDescription }
    }

    private func send() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sharingAccepted, !busy, !text.isEmpty, let expiry, expiry > Date() else { return }
        let owner = app.api.userID
        let sentAt = Date().ISO8601Format()
        busy = true
        defer { busy = false }
        do {
            let reply = try await app.api.companionReply(prompt: text, history: lines)
            guard app.signedIn, app.api.userID == owner else { return }
            let updated = lines + [["role": "user", "text": text, "created_at": sentAt],
                                   ["role": "assistant", "text": reply, "created_at": Date().ISO8601Format()]]
            let draft = prompt == text ? "" : prompt
            try app.saveChanges(["companion.history": updated, "companion.draft": draft])
            lines = updated
            prompt = draft
            failure = ""
        } catch { failure = error.localizedDescription }
    }
}

private struct CompanionBubble: View, Equatable {
    let text: String
    let own: Bool
    let timestamp: String?
    var isGreeting = false

    var body: some View {
        VStack(alignment: own ? .trailing : .leading, spacing: 5) {
            Companion.messageText(text).accessibilityLabel(Text(verbatim: text))
            if !isGreeting {
                Group {
                    if let timestamp, let date = try? Date(timestamp, strategy: .iso8601) {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("Time unavailable")
                    }
                }.font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("companion.message.timestamp")
            }
        }.padding(12)
            .background(own ? Color(red: 0.41, green: 0.88, blue: 0.8) : .white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            .padding(own ? .leading : .trailing, 40)
            .frame(maxWidth: .infinity, alignment: own ? .trailing : .leading)
    }
}

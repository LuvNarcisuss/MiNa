import SwiftUI

struct CompanionScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var topic: Int?
    private let topics = ["Sleep Tips", "Emotion", "Life Advice"]

    var body: some View {
        if route.name == "ai.chat" { CompanionConversation() }
        else {
            ZStack(alignment: .bottom) {
                NativeArt("ai", 1).ignoresSafeArea().accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Button { app.go("ai.chat") } label: {
                        NativeArt("ai", 7).scaledToFit().frame(maxHeight: 78)
                    }.accessibilityLabel("Start chat")
                    Text("Popular topics").font(.headline)
                    HStack {
                        ForEach(topics.indices, id: \.self) { index in
                            Button { topic = index } label: { NativeArt("ai", [11, 8, 9][index]).scaledToFit() }
                                .accessibilityLabel(topics[index])
                        }
                    }
                }.padding()
            }.toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: Binding(get: { topic != nil }, set: { if !$0 { topic = nil } })) {
                if let topic {
                    let group = ["sleepTips", "emotion", "life"][topic]
                    VStack {
                        NativeArt(group, topic == 2 ? 2 : 1).scaledToFit()
                            .accessibilityLabel([
                                "Keep a regular sleep schedule, reduce screen time, relax before bed, and make your bedroom comfortable.",
                                "Allow your emotions, relax, share your feelings, notice positive moments, and get enough rest.",
                                "Be kind to yourself, take breaks, stay hydrated, move regularly, and make time for what you enjoy."
                            ][topic])
                        Button("Done") { self.topic = nil }.buttonStyle(.borderedProminent)
                    }.padding().presentationDragIndicator(.visible)
                }
            }
        }
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
    @State private var availability = Companion.status()
    private let prompts = ["Help me wind down", "Give me a gentle writing prompt", "Tell me a short bedtime story"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { clock in
            let remaining = max(0, Int(ceil(expiry?.timeIntervalSince(clock.date) ?? 0)))
            VStack(spacing: 10) {
                NativeArt("aiChat", 2).scaledToFit().frame(maxHeight: 65).accessibilityLabel("AI companionship")
                if availability["available"] as? Bool == true {
                    if remaining == 0 {
                        Button("Begin a free 60-minute session") { Task { await activate() } }.disabled(busy)
                    } else {
                        Text(String(format: "Time remaining · %d:%02d", remaining / 60, remaining % 60)).monospacedDigit()
                        if remaining < 600 && reminder {
                            Button("Less than 10 minutes remain. Got it") { reminder = false }
                        }
                    }
                } else { Text(availability["message"] as? String ?? "On-device AI is unavailable.").font(.footnote) }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if lines.isEmpty { Text("What’s on your mind tonight?").foregroundStyle(.secondary) }
                            ForEach(lines.indices, id: \.self) { index in
                                let own = lines[index]["role"] == "user"
                                VStack(alignment: .leading) {
                                    Text(own ? "You" : "MiNa AI").font(.caption.bold())
                                    Text(lines[index]["text"] ?? "")
                                }.padding(12).background(own ? Color.mint.opacity(0.3) : Color.white)
                                    .cornerRadius(15).frame(maxWidth: .infinity, alignment: own ? .trailing : .leading).id(index)
                            }
                        }.padding(.vertical)
                    }.onChange(of: lines.count) { _ in if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) } }
                }
                if !failure.isEmpty { Text(failure).font(.footnote).foregroundStyle(.red) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(prompts, id: \.self) { idea in Button(idea) { update(idea) }.buttonStyle(.bordered) } }
                }.disabled(busy || remaining == 0)
                HStack {
                    TextField("Share a thought…", text: Binding(get: { prompt }, set: update)).textFieldStyle(.roundedBorder)
                    Button("Send") { Task { await send() } }.disabled(busy || remaining == 0 || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if busy { ProgressView() }
            }.padding().background(Color.mint.opacity(0.09))
        }
        .navigationTitle("MiNa Companion").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("About") { help = true } }
        .alert("About this conversation", isPresented: $help) { Button("Done") {} } message: {
            Text("Apple Intelligence generates replies on this iPhone. Your conversation stays on this device.")
        }
        .onAppear {
            availability = Companion.status()
            lines = app.state("companion.history") as? [[String: String]] ?? []
            prompt = app.state("companion.draft") as? String ?? ""
        }
        .task {
            guard availability["available"] as? Bool == true else { return }
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
            expiry = end
            reminder = true
            failure = ""
        } catch { failure = error.localizedDescription }
    }

    private func send() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty, let expiry, expiry > Date() else { return }
        let owner = app.api.userID
        busy = true
        defer { busy = false }
        do {
            let answer = try await Companion.reply(["prompt": text, "history": Array(lines.suffix(8))])
            guard app.signedIn, app.api.userID == owner else { return }
            guard let reply = answer["text"], !reply.isEmpty else { throw MiNaIssue("No reply arrived. Try again.") }
            let updated = lines + [["role": "user", "text": text], ["role": "assistant", "text": reply]]
            let draft = prompt == text ? "" : prompt
            try app.saveChanges(["companion.history": updated, "companion.draft": draft])
            lines = updated
            prompt = draft
            failure = ""
        } catch { failure = error.localizedDescription }
    }
}

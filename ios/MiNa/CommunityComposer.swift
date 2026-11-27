import SwiftUI

struct CommunityComposer: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var account = ""
    @State private var draft: CommunityRow = [:]
    @State private var busy = false
    @State private var status = ""
    @State private var message = ""
    @State private var recording = false
    @State private var started = Date()
    @State private var seconds = 0.0
    @State private var recoveryNeeded = false
    @State private var visible = false
    @State private var published = false
    private var isRecorder: Bool { route.name == "dreams.record" }
    private var dream: Bool { route.name.hasPrefix("dreams") }
    private var key: String { dream ? "dreamDraft" : "postDraft" }
    private var journalKey: String { "community.drafts." + account }
    private var journal: CommunityRow { app.state(journalKey) as? CommunityRow ?? [:] }
    private var media: CommunityRow? { draft["media"] as? CommunityRow }
    private var candidate: CommunityRow? { draft["candidate"] as? CommunityRow }
    private var pending: CommunityRow? { draft["pending"] as? CommunityRow }
    private var title: String { isRecorder ? "Recording" : dream ? "Post a dream" : "New post" }

    var body: some View {
        GeometryReader { bounds in
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isRecorder { recorderControls } else { editor }
                if !status.isEmpty { ProgressView(status) }
            }.padding(.horizontal,18).padding(.vertical,6).frame(minHeight: bounds.size.height, alignment: .top)
          }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .minaAlert(message)
        .minaAlert(recoveryNeeded && message.isEmpty ? "The recording was interrupted." : "")
        .onAppear {
            visible = true
            account = app.api.userID
            draft = journal[key] as? CommunityRow ?? ["id":UUID().uuidString.lowercased(),"text":""]
            published = false
            if isRecorder { recover() }

        }
        .task(id: transferKey) {
            guard !account.isEmpty else { return }
            await transferDraft()
        }
        .onDisappear {
            visible = false
            if isRecorder { app.media.cancelPendingRecording() }
            if recording { perform { try finish() } }
        }
        .task(id: recording) {
            guard recording else { return }
            while !Task.isCancelled && recording {
                do { try await Task.sleep(nanoseconds: 400_000_000); try Task.checkCancellation() } catch { return }
                seconds = min(60, Date().timeIntervalSince(started))
                recover()
                if recording && seconds >= 60 { perform { try finish() } }
            }
        }
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dream {
                caption
                VStack(spacing: 14) {
                    NativeArt("dreamCompose",3).scaledToFit().frame(width:222,height:135).accessibilityHidden(true)
                    if let media { preview(media) }
                    Button {
                        perform { try save(draft); app.go("dreams.record") }
                    } label: {
                        Text(candidate != nil || pending != nil ? "Review your take" : media == nil ? "Record a dream" : "Record again")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal,28).frame(minHeight:44)
                            .overlay { Capsule().stroke(.teal.opacity(0.55),lineWidth:1) }
                    }
                }.padding(18).frame(maxWidth:.infinity).frame(minHeight:290).background(.white,in: RoundedRectangle(cornerRadius:14))
            } else {
                ZStack(alignment: .topTrailing) {
                    if let media {
                        preview(media)
                        Button { perform {
                            var next = draft; next.removeValue(forKey:"media"); next["id"] = UUID().uuidString.lowercased()
                            try save(next); clean(media)
                        } } label: { NativeArt("compose",4).scaledToFit().frame(width:22,height:22).frame(width:44,height:44) }.accessibilityLabel("Remove video")
                    } else {
                        MediaSourceMenu(title: "Choose a video", choose: { source in work { try await pick(from: source) } }) {
                            VStack(spacing:6) {
                                NativeArt("compose",3).scaledToFit().frame(width:152,height:112)
                                Text("Choose a video").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity,maxHeight:.infinity)
                        }
                    }
                }.aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                caption
            }
            Button { work { try await publish() } } label: {
                Text(dream ? "Publish dream" : "Publish post").communityPrimary()
            }.disabled(media?["path"] == nil).opacity(media == nil ? 0.72 : 1).padding(.horizontal,4).padding(.top,32)
        }.disabled(busy)
    }
    private var caption: some View {
        VStack(alignment: .leading,spacing:8) {
            if !dream { Text("Tonight’s mood").font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
            TextField(dream ? "What do you remember from your dream?" : "What would you like to remember?", text: Binding(get: { draft.communityString("text") }, set: { value in
                guard visible, !published, !busy, value != draft.communityString("text") else { return }
                perform { var next = draft; next["text"] = String(value.prefix(2000)); try save(next) }
            }), axis: .vertical).font(.body).lineLimit(3...8)
                .padding(14).frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:dream ? 164 : 214,alignment:.top)
                .background(.white,in: RoundedRectangle(cornerRadius:14))
        }
    }
    private var transferKey: String {
        [account, media?.communityString("id") ?? "", candidate?.communityString("id") ?? ""].joined(separator: "|")
    }
    private func transferDraft() async {
        do {
            for field in ["media", "candidate"] {
                try Task.checkCancellation()
                try await app.uploadDraft(key, field: field, owner: account)
            }
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
        if account == app.api.userID, let latest = journal[key] as? CommunityRow { draft = latest }
    }
    @ViewBuilder private func preview(_ item: CommunityRow) -> some View {
        if let path = item["path"] as? String {
            CommunityMedia(path: path, duration: item.communitySeconds("duration"), voice: dream)
        } else {
            VStack(spacing: 8) {
                if message.isEmpty { ProgressView("Uploading…") }
                else { Button("Retry upload") { work { message = ""; await transferDraft() } } }
            }.frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private var recorderControls: some View {
        VStack(spacing: 18) {
            NativeArt(recording ? "recording" : "recorder",2).scaledToFit().frame(width:recording ? 276 : 222,height:250).accessibilityHidden(true).padding(.top,48)
            Text(communityClock(recording ? seconds : candidate?.communitySeconds("duration") ?? 0)).font(.title2.weight(.medium).monospacedDigit())
            Text("Record up to 60 seconds.").font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength:90)
            if !recording, let candidate { preview(candidate) }
            if recoveryNeeded {
                Button("Recover take") { recover() }
                Button("Finish recovery") { perform {
                    let last = try app.media.recover()
                    if last["recording"] as? Bool == true { try finish() }
                    else if let id = last["id"] as? String, id != pending?["baseline"] as? String { try adopt(last) }
                    else { var next = draft; next.removeValue(forKey: "pending"); try save(next); recoveryNeeded = false }
                } }
            } else {
                Button {
                    if recording { perform { try finish() } } else { work { try await start() } }
                } label: {
                    VStack { NativeArt(recording ? "recording" : "recorder",3).scaledToFit().frame(height: 84); Text(recording ? "Stop recording" : candidate == nil ? "Tap to record" : "Record again") }
                }
            }
            if let candidate {
                Button("Save take") { perform {
                    let previous = media
                    var next = draft; next["media"] = candidate; next.removeValue(forKey: "candidate"); next["id"] = UUID().uuidString.lowercased()
                    try save(next); clean(previous); app.back()
                } }.buttonStyle(CommunitySaveStyle()).disabled(pending != nil || recording || candidate["path"] == nil)
            }
        }.frame(maxWidth: .infinity).padding(.bottom,24).disabled(busy)
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { message = error.localizedDescription }
    }
    private func work(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = ""
        Task { @MainActor in
            defer { busy = false; status = "" }
            do { try await action() } catch { message = error.localizedDescription }
        }
    }
    private func verifyAccount() throws {
        guard !account.isEmpty, account == app.api.userID else { throw MiNaIssue("Sign in to the same account to continue.") }
    }
    private func save(_ next: CommunityRow) throws {
        try verifyAccount()
        var updated = next
        var latest = journal
        let current = latest[key] as? CommunityRow
        for field in ["media", "candidate"] {
            if var item = updated[field] as? CommunityRow, item["path"] == nil,
               let committed = current?[field] as? CommunityRow,
               committed["id"] as? String == item["id"] as? String, let path = committed["path"] as? String {
                item["path"] = path
                updated[field] = item
            }
        }
        latest[key] = updated
        try app.save(journalKey, latest)
        draft = updated
    }
    private func clean(_ item: CommunityRow?, discarded: Bool = true) {
        guard account == app.api.userID, let id = item?["id"] as? String else { return }
        for case let entry as CommunityRow in journal.values {
            for field in ["media","candidate","pending"] {
                let ref = entry[field] as? CommunityRow
                if ref?["id"] as? String == id || ref?["baseline"] as? String == id { return }
            }
        }
        try? app.media.remove(id)
        if discarded, let path = item?["path"] as? String {
            Task { try? await app.discardUnusedCapture(path) }
        }
    }
    private func pick(from source: DeviceMedia.Source) async throws {
        status = "Importing video…"
        let result = try await app.pick("video", from: source)
        if result["cancelled"] as? Bool == true { return }
        guard let id = result["id"] as? String, result.communitySeconds("duration") > 0 else { throw MiNaIssue("Choose a playable video.") }
        let previous = media
        var next = draft; next["id"] = UUID().uuidString.lowercased(); next["media"] = ["id":id,"duration":result.communitySeconds("duration")] as CommunityRow
        do { try save(next) } catch { clean(result); throw error }
        clean(previous)
    }
    private func publish() async throws {
        try verifyAccount()
        guard let take = media, let id = draft["id"] as? String else { throw MiNaIssue("Choose media for your draft.") }
        status = "Checking draft…"
        let existing = try await app.api.rows("entries?select=id&id=eq." + id + "&owner_id=eq." + account)
        if existing.isEmpty {
            guard let path = take["path"] as? String, path.hasPrefix(account + "/") else {
                throw MiNaIssue("Wait for the media upload before publishing.")
            }
            status = "Publishing…"
            let entry: CommunityRow = ["id":id,"owner_id":account,"kind":dream ? "dream" : "post","caption":draft.communityString("text").trimmingCharacters(in: .whitespacesAndNewlines),"media_path":path,"duration":take.communitySeconds("duration")]
            _ = try await app.api.rest("entries",method: "POST",body: entry,prefer: "resolution=ignore-duplicates")
        }
        try verifyAccount()
        guard let confirmed = try await app.api.rows("entries?select=id,media_path&id=eq." + id + "&owner_id=eq." + account).first,
              confirmed["id"] as? String == id, !(confirmed.communityString("media_path")).isEmpty else {
            throw MiNaIssue("The publication could not be confirmed. Please try again.")
        }
        try verifyAccount()
        var latest = journal
        if (latest[key] as? CommunityRow)?.communityString("id") == id {
            latest.removeValue(forKey: key); try app.save(journalKey,latest); clean(take, discarded: false); clean(candidate)
        }
        published = true
        draft = [:]
        if visible, app.route == route {
            let destination = NativeRoute(name: dream ? "dreams.mine" : "feed.mine")
            var path = app.path
            if path.last == route { path.removeLast() }
            if path.last != destination { path.append(destination) }
            app.path = path
        }
    }
    private func start() async throws {
        guard pending == nil else { throw MiNaIssue("Finish recovering the previous recording first.") }
        CommunityPlayer.pauseActive()
        let last = try app.media.recover()
        guard last["recording"] as? Bool != true else { throw MiNaIssue("A recording is already in progress.") }
        var next = draft
        next["pending"] = ["token":UUID().uuidString,"baseline":last["id"] ?? NSNull()] as CommunityRow
        try save(next)
        do {
            status = "Opening microphone…"
            let _: CommunityRow = try await withCheckedThrowingContinuation { continuation in app.media.beginRecording { continuation.resume(with: $0) } }
        } catch {
            next.removeValue(forKey: "pending"); try save(next); throw error
        }
        seconds = 0; started = Date(); recording = true
        if !visible { try finish() }
    }
    private func adopt(_ sample: CommunityRow) throws {
        try verifyAccount()
        guard let token = pending?["token"] as? String,
              let current = journal[key] as? CommunityRow, let marker = current["pending"] as? CommunityRow, marker["token"] as? String == token,
              let id = sample["id"] as? String, id != marker["baseline"] as? String, sample.communitySeconds("duration") > 0 else { throw MiNaIssue("The recording could not be recovered.") }
        let previous = candidate
        var next = current; next.removeValue(forKey: "pending")
        next["candidate"] = ["id":id,"duration":min(60,sample.communitySeconds("duration"))] as CommunityRow
        try save(next); clean(previous); recording = false; recoveryNeeded = false
    }
    private func finish() throws {
        do { try adopt(app.media.finishRecording()) }
        catch { recording = false; recoveryNeeded = true; throw error }
    }
    private func recover() {
        guard pending != nil else { return }
        do {
            let last = try app.media.recover()
            if last["recording"] as? Bool == true {
                if !recording { started = Date() }; recording = true; recoveryNeeded = false
            } else if let id = last["id"] as? String, id != pending?["baseline"] as? String {
                try adopt(last)
            } else { recording = false; recoveryNeeded = true }
        } catch { message = error.localizedDescription; recoveryNeeded = true; recording = false }
    }
}

private struct CommunitySaveStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.communityPrimary().opacity(configuration.isPressed ? 0.75 : 1) }
}

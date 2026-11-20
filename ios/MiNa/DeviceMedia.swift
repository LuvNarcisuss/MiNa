import Accelerate
import AVFoundation
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class DeviceMedia: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate,
                         AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    typealias Payload = [String: Any]
    typealias Completion = (Result<Payload, Error>) -> Void
    private let fs = FileManager.default
    private let audio = AVAudioSession.sharedInstance()
    private let imports = DispatchQueue(label: "com.mina.media-import")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var playerID: String?
    private var previousCallCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var pendingPermission = false
    private var kind = ""
    private var pickerReply: Completion?
    private var mediaDirectory: URL { LocalPages.library.appendingPathComponent("Media", isDirectory: true) }
    private var exportDirectory: URL { LocalPages.pages.appendingPathComponent("private-media", isDirectory: true) }
    private var recentTake: URL { LocalPages.library.appendingPathComponent("last-recording.txt") }
    private var pendingTake: URL { LocalPages.library.appendingPathComponent("pending-recording.txt") }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
            name: AVAudioSession.interruptionNotification, object: audio)
        NotificationCenter.default.addObserver(self, selector: #selector(background),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        DispatchQueue.main.async { self.background() }
    }

    @objc private func background() {
        if recorder != nil { _ = try? finishRecording() }
        stopPlayback()
    }

    private func directory(_ id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id), uuid.uuidString == id else { throw MiNaIssue("This media item is unavailable.") }
        return mediaDirectory.appendingPathComponent(id, isDirectory: true)
    }

    private func asset(_ id: String) throws -> URL {
        let choices = try fs.contentsOfDirectory(at: directory(id), includingPropertiesForKeys: nil)
        guard let url = choices.first(where: { $0.deletingPathExtension().lastPathComponent == "asset" })
        else { throw MiNaIssue("This media item is no longer on this device.") }
        return url
    }

    private func export(_ url: URL, id: String) throws -> URL {
        let targetDirectory = exportDirectory.appendingPathComponent(id, isDirectory: true)
        try fs.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let target = targetDirectory.appendingPathComponent(url.lastPathComponent)
        if !fs.fileExists(atPath: target.path) { try fs.linkItem(at: url, to: target) }
        return target
    }

    func resolve(_ id: String) throws -> Payload {
        let file = try asset(id)
        var value: Payload = ["id": id, "url": try export(file, id: id).absoluteString]
        let type = UTType(filenameExtension: file.pathExtension)
        if type?.conforms(to: .audiovisualContent) == true {
            let seconds = AVURLAsset(url: file).duration.seconds
            if seconds.isFinite { value["duration"] = seconds }
        }
        let cover = file.deletingLastPathComponent().appendingPathComponent("cover.jpg")
        if fs.fileExists(atPath: cover.path) { value["cover"] = try export(cover, id: id).absoluteString }
        return value
    }

    func bytes(_ params: Payload) throws -> Payload {
        let url = try asset(params["id"] as? String ?? "")
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        let offset = params["offset"] as? Int ?? 0
        let length = params["length"] as? Int
        guard offset >= 0, offset <= size else { throw MiNaIssue("The requested media position is invalid.") }
        if let length {
            guard (1...524288).contains(length) else { throw MiNaIssue("Choose a smaller media segment.") }
        } else if size - offset > 8 * 1024 * 1024 {
            throw MiNaIssue("Read this media in smaller segments.")
        }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: min(length ?? (size - offset), size - offset)) ?? Data()
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return ["base64": data.base64EncodedString(), "mimeType": type, "total": size, "nextOffset": offset + data.count]
    }

    func remove(_ id: String) throws {
        let url = try directory(id)
        if playerID == id { stopPlayback() }
        if recorder?.url.deletingLastPathComponent() == url { throw MiNaIssue("Finish this recording before removing it.") }
        let view = exportDirectory.appendingPathComponent(id)
        if fs.fileExists(atPath: view.path) { try fs.removeItem(at: view) }
        if fs.fileExists(atPath: url.path) { try fs.removeItem(at: url) }
    }

    func prepareAccountChange() throws {
        guard pickerReply == nil, !pendingPermission else { throw MiNaIssue("Finish the media selection first.") }
        background()
        if fs.fileExists(atPath: exportDirectory.path) { try fs.removeItem(at: exportDirectory) }
    }

    func clear() throws {
        guard pickerReply == nil, !pendingPermission else { throw MiNaIssue("Finish the media selection first.") }
        background()
        for url in [exportDirectory, LocalPages.library] where fs.fileExists(atPath: url.path) {
            try fs.removeItem(at: url)
        }
    }

    func pick(_ value: String, presenter: UIViewController?, completion: @escaping Completion) {
        guard ["image", "video"].contains(value), pickerReply == nil,
              let presenter, presenter.viewIfLoaded?.window != nil else {
            completion(.failure(MiNaIssue("The media picker is unavailable."))); return
        }
        kind = value
        pickerReply = completion
        let sheet = UIAlertController(title: value == "video" ? "Choose a video" : "Choose an image",
                                      message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
            var config = PHPickerConfiguration()
            config.filter = value == "video" ? .videos : .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            presenter.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Files", style: .default) { _ in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [value == "video" ? .movie : .image], asCopy: false)
            picker.delegate = self
            presenter.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in self.complete(.success(["cancelled": true])) })
        presenter.present(sheet, animated: true)
    }

    private func complete(_ result: Result<Payload, Error>) {
        let completion = pickerReply
        pickerReply = nil
        completion?(result)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { complete(.success(["cancelled": true])) }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { complete(.success(["cancelled": true])); return }
        let selectedKind = kind
        imports.async {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            var issue: NSError?
            var result: Result<Payload, Error> = .failure(MiNaIssue("This file could not be opened."))
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &issue) { file in
                result = Result { try self.importFile(file, kind: selectedKind) }
            }
            let selection = issue.map { Result<Payload, Error>.failure($0) } ?? result
            DispatchQueue.main.async { self.complete(selection) }
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking selected: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = selected.first?.itemProvider else { complete(.success(["cancelled": true])); return }
        let selectedKind = kind
        let type: UTType = selectedKind == "video" ? .movie : .image
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
            let result = Result { () throws -> Payload in
                if let error { throw error }
                guard let url else { throw MiNaIssue("This file could not be opened.") }
                // The provider removes this URL when this callback returns.
                return try self.importFile(url, kind: selectedKind)
            }
            DispatchQueue.main.async { self.complete(result) }
        }
    }

    private func importFile(_ source: URL, kind: String) throws -> Payload {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 50 * 1024 * 1024 else { throw MiNaIssue("Choose a file of 50 MB or less.") }
        let id = UUID().uuidString
        let folder = try directory(id)
        try fs.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            if kind == "image" {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                guard let sourceImage = CGImageSourceCreateWithURL(source as CFURL, nil),
                      let preview = CGImageSourceCreateThumbnailAtIndex(sourceImage, 0, options as CFDictionary),
                      let data = UIImage(cgImage: preview).jpegData(compressionQuality: 0.86)
                else { throw MiNaIssue("Choose a readable image.") }
                try data.write(to: folder.appendingPathComponent("asset.jpg"), options: .atomic)
            } else {
                let video = AVURLAsset(url: source)
                guard video.isPlayable, !video.tracks(withMediaType: .video).isEmpty,
                      video.duration.seconds.isFinite, video.duration.seconds > 0,
                      let type = UTType(filenameExtension: source.pathExtension),
                      [UTType.mpeg4Movie, UTType.quickTimeMovie].contains(type),
                      let ext = type.preferredFilenameExtension else { throw MiNaIssue("Choose a playable MP4 or MOV video.") }
                try fs.copyItem(at: source, to: folder.appendingPathComponent("asset.\(ext)"))
                let generator = AVAssetImageGenerator(asset: video)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 960, height: 960)
                if let image = try? generator.copyCGImage(at: .zero, actualTime: nil),
                   let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) {
                    try data.write(to: folder.appendingPathComponent("cover.jpg"), options: .atomic)
                }
            }
            return try resolve(id)
        } catch {
            try? fs.removeItem(at: folder)
            try? fs.removeItem(at: exportDirectory.appendingPathComponent(id))
            throw error
        }
    }

    func beginRecording(_ completion: @escaping Completion) {
        guard recorder == nil, !pendingPermission else {
            completion(.failure(MiNaIssue("A recording is already in progress."))); return
        }
        pendingPermission = true
        audio.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.pendingPermission = false
                guard granted, UIApplication.shared.applicationState == .active else {
                    completion(.failure(MiNaIssue("Allow microphone access in Settings to record a dream."))); return
                }
                completion(Result { try self.startTake() })
            }
        }
    }

    private func startTake() throws -> Payload {
        stopPlayback()
        let folder = try directory(UUID().uuidString)
        try fs.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audio.setActive(true)
            let take = try AVAudioRecorder(url: folder.appendingPathComponent("asset.m4a"), settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            take.delegate = self
            try folder.lastPathComponent.write(to: pendingTake, atomically: true, encoding: .utf8)
            guard take.record(forDuration: 60) else { throw MiNaIssue("The microphone could not start recording.") }
            recorder = take
            return ["recording": true]
        } catch {
            try? fs.removeItem(at: folder)
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func finishRecording() throws -> Payload {
        guard let take = recorder else {
            let last = try recover()
            guard last["id"] is String else { throw MiNaIssue("There is no recorded take to save.") }
            return last
        }
        recorder = nil
        take.delegate = nil
        take.stop()
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
        let id = take.url.deletingLastPathComponent().lastPathComponent
        let seconds = AVURLAsset(url: take.url).duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            try? remove(id)
            throw MiNaIssue("The recording was too short. Please record again.")
        }
        guard try containsAudio(take.url) else {
            try? remove(id)
            try? fs.removeItem(at: pendingTake)
            throw MiNaIssue("No sound was captured. Check the microphone and record again.")
        }
        try id.write(to: recentTake, atomically: true, encoding: .utf8)
        try? fs.removeItem(at: pendingTake)
        return ["id": id, "duration": min(60, seconds), "recording": false]
    }

    private func containsAudio(_ url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else {
            throw MiNaIssue("This take could not be read.")
        }
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            var peak: Float = 0
            vDSP_maxmgv(channel, 1, &peak, vDSP_Length(buffer.frameLength))
            if peak > 0.0001 { return true }
        }
        return false
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if self.recorder === recorder { _ = try? finishRecording() }
    }

    func recover() throws -> Payload {
        if recorder == nil, let id = try? String(contentsOf: pendingTake, encoding: .utf8),
           let file = try? asset(id) {
            let duration = AVURLAsset(url: file).duration.seconds
            if duration.isFinite, duration > 0, (try? containsAudio(file)) == true {
                try id.write(to: recentTake, atomically: true, encoding: .utf8)
                try? fs.removeItem(at: pendingTake)
            }
        }
        guard let id = try? String(contentsOf: recentTake, encoding: .utf8), let url = try? asset(id) else {
            return ["id": NSNull(), "duration": 0, "recording": recorder?.isRecording ?? false]
        }
        let seconds = AVURLAsset(url: url).duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw MiNaIssue("The last recording could not be read.") }
        return ["id": id, "duration": min(seconds, 60), "recording": recorder?.isRecording ?? false]
    }

    func play(_ id: String) throws -> Payload {
        guard recorder == nil else { throw MiNaIssue("Stop the recording before listening.") }
        stopPlayback()
        let url = try asset(id)
        guard url.pathExtension == "m4a" else { throw MiNaIssue("This item is not a voice recording.") }
        do {
            try audio.setCategory(.playback)
            try audio.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            guard next.play() else { throw MiNaIssue("This recording could not be played.") }
            player = next
            playerID = id
            return playbackStatus()
        } catch {
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func setCallSpeaker(enabled: Bool, ending: Bool) throws -> Payload {
        guard recorder == nil else { throw MiNaIssue("Finish recording before changing the call output.") }
        if enabled, audio.category != .playAndRecord {
            previousCallCategory = (audio.category, audio.mode, audio.categoryOptions)
            try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            try audio.setActive(true)
        }
        if audio.category == .playAndRecord {
            try audio.overrideOutputAudioPort(enabled && !ending ? .speaker : .none)
        }
        if ending, let previous = previousCallCategory {
            try audio.setActive(false, options: .notifyOthersOnDeactivation)
            try audio.setCategory(previous.0, mode: previous.1, options: previous.2)
            previousCallCategory = nil
        }
        let speaker = audio.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        return ["speaker": speaker]
    }

    func playbackStatus() -> Payload {
        ["playing": player?.isPlaying ?? false, "id": playerID as Any? ?? NSNull(), "position": player?.currentTime ?? 0,
         "duration": player?.duration ?? 0]
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player { stopPlayback() }
    }

    func stopPlayback() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        playerID = nil
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

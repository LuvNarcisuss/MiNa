import Foundation
import React
import StoreKit
import SafariServices
import UIKit

@objc(MiNaNative)
final class MiNaNative: NSObject {
    private let media = DeviceMedia()
    private let extraction = DispatchQueue(label: "com.mina.pages")
    private var replying = false

    @objc static func requiresMainQueueSetup() -> Bool { true }

    @objc(prepare:rejecter:)
    func prepare(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        extraction.async {
            do {
                let owner = try SessionStore.owner(SessionStore.read())
                let entry = try LocalPages.prepare()
                DispatchQueue.main.async {
                    LocalPages.owner = owner
                    resolve(entry)
                }
            } catch { reject("startup_failed", error.localizedDescription, error) }
        }
    }

    @objc(invoke:params:resolver:rejecter:)
    func invoke(_ method: String, params: [String: Any], resolver resolve: @escaping RCTPromiseResolveBlock,
                rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            let reply: DeviceMedia.Completion = { result in
                switch result {
                case .success(let value): resolve(value)
                case .failure(let error): reject("operation_failed", error.localizedDescription, error)
                }
            }
            let id = params["id"] as? String ?? ""
            do {
                switch method {
                case "getSession":
                    let session = try SessionStore.read()
                    resolve(["session": session as Any? ?? NSNull()])
                case "setSession":
                    guard params["session"] is NSNull || params["session"] is [String: Any] else {
                        throw MiNaIssue("The sign-in details could not be read.")
                    }
                    let session = params["session"] as? [String: Any]
                    let next = try SessionStore.owner(session)
                    if next != LocalPages.owner { try self.media.prepareAccountChange() }
                    try SessionStore.write(session)
                    LocalPages.owner = next
                    resolve([:])
                case "loadState": resolve(try LocalPages.loadState())
                case "saveState": try LocalPages.saveState(params["state"]); resolve([:])
                case "clearLocalData": try self.media.clear(); resolve([:])
                case "startRecording": self.media.beginRecording(reply)
                case "stopRecording": resolve(try self.media.finishRecording())
                case "recoverRecording": resolve(try self.media.recover())
                case "playRecording": resolve(try self.media.play(id))
                case "stopPlayback": self.media.stopPlayback(); resolve([:])
                case "playbackStatus": resolve(self.media.playbackStatus())
                case "setCallSpeaker":
                    guard let enabled = params["enabled"] as? Bool else { throw MiNaIssue("Choose a call output.") }
                    resolve(try self.media.setCallSpeaker(enabled: enabled, ending: params["ending"] as? Bool ?? false))
                case "pickMedia":
                    self.media.pick(params["kind"] as? String ?? "", presenter: RCTPresentedViewController(), completion: reply)
                case "resolveMedia": resolve(try self.media.resolve(id))
                case "mediaBytes": resolve(try self.media.bytes(params))
                case "deleteMedia": try self.media.remove(id); resolve([:])
                case "showPolicy":
                    guard let document = params["document"] as? String, ["terms", "privacy"].contains(document),
                          let url = URL(string: "https://nojpfyqctfwdshqnzudp.supabase.co/functions/v1/policies/\(document).pdf"),
                          let presenter = RCTPresentedViewController(), presenter.viewIfLoaded?.window != nil else {
                        throw MiNaIssue("This document could not be opened.")
                    }
                    presenter.present(SFSafariViewController(url: url), animated: true) { resolve(["opened": true]) }
                case "getCatalog":
                    let message = SKPaymentQueue.canMakePayments() ? "Coin packages are not available yet." : "Purchases are disabled on this iPhone."
                    resolve(["status": "unavailable", "products": [], "message": message] as [String: Any])
                case "purchase": throw MiNaIssue("A verified coin package is required before checkout.")
                case "companionStatus": resolve(Companion.status())
                case "companionReply":
                    guard !self.replying else { throw MiNaIssue("Please wait for the current reply.") }
                    self.replying = true
                    let owner = LocalPages.owner
                    Task { @MainActor in
                        defer { self.replying = false }
                        do {
                            let result = try await Companion.reply(params)
                            guard LocalPages.owner == owner else { throw MiNaIssue("The active account changed.") }
                            resolve(result)
                        } catch { reject("companion_failed", error.localizedDescription, error) }
                    }
                default: throw MiNaIssue("This action is unavailable.")
                }
            } catch { reject("operation_failed", error.localizedDescription, error) }
        }
    }
}

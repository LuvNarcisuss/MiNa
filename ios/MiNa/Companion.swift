import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum Companion {
    static func status() -> [String: Any] {
        let message: String
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ["available": true]
            case .unavailable(.deviceNotEligible): message = "This iPhone does not support the on-device companion."
            case .unavailable(.appleIntelligenceNotEnabled): message = "Turn on Apple Intelligence in Settings to chat."
            case .unavailable(.modelNotReady): message = "Apple Intelligence is getting ready. Try again later."
            default: message = "The on-device companion is currently unavailable."
            }
        } else {
            message = "On-device chat requires iOS 26 or later on a compatible iPhone."
        }
        #else
        message = "This version of MiNa does not include on-device chat."
        #endif
        return ["available": false, "message": message, "topics": ["Sleep Tips", "Emotion", "Life Advice"]]
    }

    static func reply(_ params: [String: Any]) async throws -> [String: String] {
        let availability = status()
        guard availability["available"] as? Bool == true else {
            throw MiNaIssue(availability["message"] as? String ?? "The companion is unavailable.")
        }
        guard let prompt = (params["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty, prompt.count <= 1600 else { throw MiNaIssue("Write a message of up to 1,600 characters.") }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let history = (params["history"] as? [[String: String]] ?? []).suffix(6).compactMap { item -> String? in
                guard let text = item["text"], let role = item["role"],
                      ["assistant", "ai", "user"].contains(role) else { return nil }
                let speaker = role == "user" ? "Person" : "MiNa"
                return "\(speaker): \(text.prefix(320))"
            }
            let session = LanguageModelSession(instructions: """
                You are MiNa, a gentle AI bedtime companion. Write a brief, warm response in English.
                Offer simple wind-down ideas and listen to everyday concerns. Be clear that you are an AI.
                Do not diagnose or prescribe. Encourage appropriate real-world support when needed.
                """)
            let context = history.isEmpty ? "" : "Recent conversation:\n" + history.joined(separator: "\n") + "\n\n"
            let response = try await session.respond(to: context + "Current message:\n" + prompt)
            return ["text": response.content]
        }
        #endif
        throw MiNaIssue("The on-device companion is unavailable.")
    }
}

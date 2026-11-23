import SwiftUI

struct AccountScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var message = ""
    @State private var notice = ""
    @State private var sending = false
    private struct Policy: Decodable { let title: String; let sections: [[String]] }
    private static let policies: [String: Policy] = {
        guard let url = Bundle.main.url(forResource: "policies", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Policy].self, from: data)) ?? [:]
    }()

    var body: some View {
        if route.name.hasPrefix("legal.") {
            let key = String(route.name.dropFirst(6))
            if let policy = Self.policies[key] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Effective November 20, 2026").font(.caption)
                        ForEach(policy.sections.indices, id: \.self) { i in
                            let part = policy.sections[i]
                            if part.count == 2 { Text(part[0]).font(.headline); Text(part[1]) }
                        }
                        if key != "guidelines" {
                            Link("Open PDF", destination: MiNaAPI.origin.appendingPathComponent("functions/v1/policies/\(key).pdf"))
                        }
                    }.padding()
                }.navigationTitle(policy.title)
            } else { Text("This document is unavailable.") }
        } else if route.name == "support" {
            Form {
                Section("How can we help?") {
                    TextField("Describe your question or concern", text: $message, axis: .vertical).lineLimit(3...10)
                    Button(sending ? "Sending…" : "Send request") { Task { await sendSupport() } }
                        .disabled(sending || !(5...2000).contains(message.trimmingCharacters(in: .whitespacesAndNewlines).count))
                }
                if !notice.isEmpty { Text(notice) }
            }.navigationTitle("Contact us")
        } else {
            let removing = route.name == "delete"
            Form {
                Section(removing ? "Delete your MiNa account?" : "Leave MiNa on this iPhone?") {
                    Text(removing ? "Your cloud account, uploaded media, messages and associated records will be permanently removed." : "Your account key stays in Keychain. Use Continue on this iPhone to reopen your account.")
                    Button(removing ? "Permanently delete" : "Sign out", role: .destructive) { Task { await app.leave(delete: removing) } }
                    Button("Cancel") { app.back() }
                }.disabled(app.busy)
                if !app.accountError.isEmpty { Text(app.accountError) }
            }.navigationTitle(removing ? "Delete account" : "Sign out")
        }
    }

    private func sendSupport() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await app.api.rest("support_requests", method: "POST", body: ["body": message.trimmingCharacters(in: .whitespacesAndNewlines)])
            message = ""
            notice = "Your request has been received."
        } catch { notice = error.localizedDescription }
    }
}

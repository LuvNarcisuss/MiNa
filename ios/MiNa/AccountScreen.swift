import SwiftUI

struct AccountScreen: View {
    @EnvironmentObject var app: MiNaAppModel
    let route: NativeRoute
    @State private var message = ""
    @State private var notice = ""
    @State private var sending = false
    var body: some View {
        content
            .minaAlert(app.accountError)
    }

    @ViewBuilder private var content: some View {
        if route.name.hasPrefix("legal.") {
            let key = String(route.name.dropFirst(6))
            if let policy = CloudInterface.catalog?.policies[key] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(key == "guidelines" ? "Effective November 20, 2026" : "Effective November 24, 2026").font(.caption)
                        ForEach(policy.sections.indices, id: \.self) { i in
                            let part = policy.sections[i]
                            if part.count == 2 { Text(part[0]).font(.headline); Text(part[1]) }
                        }
                        if key != "guidelines" {
                            Link("Open PDF", destination: MiNaAPI.origin.appendingPathComponent("functions/v1/policies/\(key).pdf"))
                        }
                    }.padding()
                }.background { AccountBackdrop(group: "privacy") }.navigationTitle(policy.title).navigationBarTitleDisplayMode(.inline)
            } else { Color.clear.minaAlert("This document is unavailable.") }
        } else if route.name == "support" {
            Form {
                Section("How can we help?") {
                    TextField("Describe your question or concern", text: $message, axis: .vertical).lineLimit(3...10)
                    Button(sending ? "Sending…" : "Send request") { Task { await sendSupport() } }
                        .disabled(sending || !(5...2000).contains(message.trimmingCharacters(in: .whitespacesAndNewlines).count))
                }
                if !notice.isEmpty { Text(notice) }
            }.scrollContentBackground(.hidden).background { AccountBackdrop(group: "privacy") }.navigationTitle("Contact us").navigationBarTitleDisplayMode(.inline)
        } else {
            let removing = route.name == "delete"
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Text(removing ? "Delete your MiNa account?" : "Sign out of MiNa?").font(.title3.bold())
                    Text(removing ? "Your cloud account, uploaded media, messages and associated records will be permanently removed." : "Sign in again with your email and password to return to your account.")
                        .font(.callout).multilineTextAlignment(.center)
                    Button(role: .destructive) { Task { await app.leave(delete: removing) } } label: {
                        Text(removing ? "Permanently delete" : "Sign out").font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity,minHeight: 46).background(LinearGradient(colors:[.mint,.cyan],startPoint:.leading,endPoint:.trailing),in: Capsule())
                    }
                    Button("Cancel") { app.back() }
                }.padding(24).disabled(app.busy).background { NativeArt("spend",1) }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }.frame(maxWidth: .infinity).background { AccountBackdrop(group: "privacy") }
                .navigationTitle(removing ? "Delete account" : "Sign out").navigationBarTitleDisplayMode(.inline)
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
        } catch { AppAlerts.shared.show(error.localizedDescription) }
    }
}

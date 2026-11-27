import SwiftUI

struct ReportForm: View {
    @EnvironmentObject private var app: MiNaAppModel
    @Environment(\.dismiss) private var dismiss
    let targetID: String
    let kind: String
    var targetName: String? = nil
    let acknowledged: () -> Void

    @State private var reason = "Harassment"
    @State private var details = ""
    @State private var operation = UUID()
    @State private var submitting = false
    @State private var receipt: String?
    @State private var failure = ""

    var body: some View {
        ScrollView {
            PopupPanel(title: "Report " + kind, message: targetName, close: { dismiss() }) {
                PopupMenu("Reason") {
                    ForEach(["Harassment", "Sexual content", "Harmful content", "Privacy concern", "Spam", "Other"], id: \.self) { value in
                        PopupAction(value, "flag", selected: reason == value) { reason = value }
                    }
                } label: {
                    HStack {
                        Text("Reason").foregroundStyle(PopupTheme.ink)
                        Spacer()
                        Text(reason)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }.padding(14).frame(minHeight: 48).background(.white, in: RoundedRectangle(cornerRadius: 15))
                }.accessibilityLabel("Reason").accessibilityValue(reason)
                TextField("Additional details (optional)", text: $details, axis: .vertical)
                    .lineLimit(2...5).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
                    .onChange(of: details) { if $0.count > 950 { details = String($0.prefix(950)) } }
                PopupAction("Submit report", "paperplane") { Task { await submit() } }
            }
            .disabled(submitting || receipt != nil)
        }
        .popupSurface().presentationDetents([.medium, .large])
        .interactiveDismissDisabled(submitting || receipt != nil)
        .minaAlert(failure)
        .popupDialog("Report submitted", isPresented: Binding(get: { receipt != nil }, set: { if !$0 { receipt = nil } }),
                     message: receipt.map { "You can withdraw this report in Report history.\nReceipt " + String($0.prefix(8)) },
                     closeLabel: nil) {
            PopupAction("OK", "checkmark") { acknowledged(); dismiss() }
        }
    }

    @MainActor private func submit() async {
        guard !submitting, receipt == nil else { return }
        submitting = true
        failure = ""
        defer { submitting = false }
        do {
            receipt = try await app.api.report(targetID, kind: kind, reason: reason, details: details, operation: operation)
        } catch { failure = error.localizedDescription }
    }
}

import SwiftUI
import UIKit

/// Serializes messages from pages, sheets and background refreshes in the active iPhone window.
@MainActor
final class AppAlerts {
    static let shared = AppAlerts()
    private var waiting: [String] = []
    private weak var visible: UIAlertController?
    private var scheduled = false

    func show(_ text: String) {
        guard !text.isEmpty, text != CancellationError().localizedDescription,
              text != URLError(.cancelled).localizedDescription else { return }
        let message = Self.displayText(text)
        guard visible?.message != message, !waiting.contains(message) else { return }
        waiting.append(message)
        presentNext()
    }

    private func presentNext() {
        guard !waiting.isEmpty, !scheduled else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var host = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            schedulePresentation()
            return
        }
        while let next = host.presentedViewController { host = next }
        guard !(host is UIAlertController), !host.isBeingDismissed, !host.isBeingPresented,
              host.viewIfLoaded?.window != nil else {
            schedulePresentation()
            return
        }
        let popup = UIAlertController(title: "MiNa", message: waiting.removeFirst(), preferredStyle: .alert)
        popup.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.schedulePresentation() })
        popup.view.tintColor = UIColor(PopupTheme.accent)
        visible = popup
        host.present(popup, animated: true)
    }

    private func schedulePresentation() {
        guard !scheduled, !waiting.isEmpty else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.scheduled = false
            self?.presentNext()
        }
    }

    static func displayText(_ message: String) -> String {
        let technical = ["foreign key", "violates", "constraint", "row-level security", "permission denied for",
                         "duplicate key", "postgres", "pgrst", "sqlstate", "jwt", "nsurlerrordomain",
                         "couldn’t be completed. (", "relation \"", "column \"", "schema cache"]
        if technical.contains(where: { message.localizedCaseInsensitiveContains($0) }) {
            return "MiNa couldn’t complete the request. Please try again."
        }
        return message
    }
}

extension View {
    func minaAlert(_ message: String) -> some View {
        onAppear { AppAlerts.shared.show(message) }
            .onChange(of: message) { AppAlerts.shared.show($0) }
    }
}

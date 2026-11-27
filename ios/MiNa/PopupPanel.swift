import SwiftUI

enum PopupTheme {
    static let ink = Color(red: 0.07, green: 0.18, blue: 0.23)
    static let accent = Color(red: 0.02, green: 0.39, blue: 0.39)
    static let danger = Color(red: 0.70, green: 0.13, blue: 0.21)
    static let surface = LinearGradient(colors: [
        Color(red: 0.91, green: 0.98, blue: 0.95), Color(red: 0.96, green: 0.99, blue: 1), .white
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let radius: CGFloat = 28
}

struct PopupHeading: View {
    let title: String
    var closeLabel = "Cancel"
    var close: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(PopupTheme.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PopupTheme.accent).frame(width: 31, height: 31)
                        .background(PopupTheme.accent.opacity(0.09), in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(closeLabel)
            }
        }.frame(minHeight: 44)
    }
}

private struct PopupSelectionKey: EnvironmentKey {
    static let defaultValue: (@escaping () -> Void) -> Void = { action in action() }
}

private extension EnvironmentValues {
    var selectPopupAction: (@escaping () -> Void) -> Void {
        get { self[PopupSelectionKey.self] }
        set { self[PopupSelectionKey.self] = newValue }
    }
}

struct PopupAction: View {
    let title: String
    let symbol: String
    let role: ButtonRole?
    let selected: Bool
    let action: () -> Void
    @Environment(\.selectPopupAction) private var select

    init(_ title: String, _ symbol: String, role: ButtonRole? = nil, selected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.selected = selected
        self.action = action
    }

    var body: some View {
        let tint = role == .destructive ? PopupTheme.danger : PopupTheme.accent
        Button(role: role) { select(action) } label: {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                Text(title).font(.body.weight(.medium))
                    .foregroundStyle(role == .destructive ? PopupTheme.danger : PopupTheme.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").foregroundStyle(tint).accessibilityHidden(true) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 54)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(PopupTheme.accent.opacity(0.10)) }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PopupPanel<Content: View>: View {
    let title: String
    var message: String? = nil
    var closeLabel = "Cancel"
    var close: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PopupHeading(title: title, closeLabel: closeLabel, close: close)
            if let message, !message.isEmpty {
                Text(message).font(.subheadline).foregroundStyle(PopupTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 7, content: content)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }
}

private struct PopupDialog<Actions: View>: ViewModifier {
    let title: String
    @Binding var presented: Bool
    let message: String?
    let closeLabel: String?
    @ViewBuilder let actions: () -> Actions
    @State private var afterDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $presented, onDismiss: {
            let action = afterDismiss
            afterDismiss = nil
            action?()
        }) {
            PopupPanel(title: title, message: message, closeLabel: closeLabel ?? "Cancel",
                       close: closeLabel == nil ? nil : { presented = false }, content: actions)
            .environment(\.selectPopupAction, { action in
                guard afterDismiss == nil else { return }
                afterDismiss = action
                presented = false
            })
            .modifier(FittedPopup(allowsDrag: closeLabel != nil))
            .interactiveDismissDisabled(closeLabel == nil)
        }
    }
}

struct FittedPopup: ViewModifier {
    var allowsDrag = true
    @State private var height: CGFloat = 260
    func body(content: Content) -> some View {
        ScrollView {
            content.background {
                GeometryReader { box in
                    Color.clear.onAppear { height = ceil(box.size.height) }
                        .onChange(of: box.size.height) { height = ceil($0) }
                }
            }
        }.popupSurface().presentationDetents([.height(max(100, height))])
            .presentationDragIndicator(allowsDrag ? .visible : .hidden)
    }
}

extension View {
    @ViewBuilder func popupSurface() -> some View {
        let surface = self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { PopupTheme.surface.ignoresSafeArea() }
            .tint(PopupTheme.accent).environment(\.colorScheme, .light)
            .presentationDragIndicator(.visible)
        if #available(iOS 16.4, *) {
            surface.presentationCornerRadius(PopupTheme.radius).presentationBackground(PopupTheme.surface)
        } else {
            surface
        }
    }

    func popupDialog<Actions: View>(_ title: String, isPresented: Binding<Bool>, message: String? = nil,
                                    closeLabel: String? = "Cancel", @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(PopupDialog(title: title, presented: isPresented, message: message, closeLabel: closeLabel, actions: actions))
    }
}

struct PopupMenu<Actions: View, Label: View>: View {
    let title: String
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let label: () -> Label
    @State private var presented = false

    init(_ title: String, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder label: @escaping () -> Label) {
        self.title = title
        self.actions = actions
        self.label = label
    }

    var body: some View {
        Button { presented = true } label: { label() }
            .popupDialog(title, isPresented: $presented, actions: actions)
    }
}

struct MediaSourceMenu<Label: View>: View {
    let title: String
    let choose: (DeviceMedia.Source) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        PopupMenu(title) {
            PopupAction("Photo Library", "photo.on.rectangle") { choose(.library) }
            PopupAction("Files", "folder") { choose(.files) }
        } label: { label() }
    }
}

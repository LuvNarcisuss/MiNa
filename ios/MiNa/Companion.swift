import CoreText
import SwiftUI

enum Companion {
    static let disclosure = "When you send a message, MiNa shares it and up to six recent messages with Groq to generate an AI reply."

    static func messageText(_ text: String) -> Text {
        var result = Text(verbatim: "")
        var plain = ""
        for character in text {
            let scalars = character.unicodeScalars
            guard scalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) else {
                plain.append(character)
                continue
            }
            result = result + Text(verbatim: plain) + emoji(character)
            plain = ""
        }
        return result + Text(verbatim: plain)
    }

    private static func emoji(_ character: Character) -> Text {
        let value = String(character)
        if ReactionPicker.supports(character) { return Text(verbatim: value).font(.custom(ReactionPicker.fontName, size: 17, relativeTo: .body)) }
        // The simulator can report valid color glyphs while drawing replacement boxes.
        #if !targetEnvironment(simulator)
        if let font = UIFont(name: "AppleColorEmoji", size: UIFont.preferredFont(forTextStyle: .body).pointSize) {
            let attributed = NSAttributedString(string: value, attributes: [.font: font])
            let runs = CTLineGetGlyphRuns(CTLineCreateWithAttributedString(attributed)) as! [CTRun]
            if !runs.isEmpty && runs.allSatisfy({ run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let runFont = attributes[kCTFontAttributeName] else { return false }
                guard CTFontCopyPostScriptName(runFont as! CTFont) as String == font.fontName else { return false }
                var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
                guard !glyphs.isEmpty else { return false }
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                return !glyphs.contains(0)
            }) {
                return Text(verbatim: value).font(Font(font))
            }
        }
        #endif
        let names = character.unicodeScalars.filter { $0.properties.isEmoji && $0.value != 0xFE0F }
            .compactMap { $0.properties.name?.lowercased() }
        return Text(verbatim: "[" + (names.isEmpty ? "emoji" : names.joined(separator: " ")) + "]")
    }
}

struct ReactionPicker: View {
    static let fontName = "MiNaReactions"
    private static let options = [
        ("🌙", "Crescent moon"), ("✨", "Sparkles"), ("💚", "Green heart"),
        ("😴", "Sleeping face"), ("🌟", "Glowing star"), ("🫶", "Heart hands")
    ]
    private static let glyphs = Set("🌙✨💚😴🌟🫶🌿🍃🌱")

    var includesHeartHands = true
    let select: (String) -> Void

    static func supports(_ character: Character) -> Bool { glyphs.contains(character) }

    static func textFont(for value: String, style: UIFont.TextStyle = .body) -> Font {
        let system = UIFont.preferredFont(forTextStyle: style)
        guard value.contains(where: supports),
              let font = UIFont(name: fontName, size: system.pointSize) else { return Font(system) }
        let descriptor = font.fontDescriptor.addingAttributes([.cascadeList: [system.fontDescriptor]])
        return Font(UIFont(descriptor: descriptor, size: system.pointSize))
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.options.prefix(includesHeartHands ? 6 : 5), id: \.0) { item in
                Button { select(item.0) } label: {
                    Text(verbatim: item.0).font(.custom(Self.fontName, size: 26, relativeTo: .title2))
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.1)
            }
        }
    }
}

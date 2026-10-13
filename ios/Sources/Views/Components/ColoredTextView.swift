import SwiftUI

public struct ColoredTextView: View {
    public let tokens: [PhoneticToken]
    public let fallbackColor: Color
    public let isRTL: Bool
    public var onInspectCharacter: ((String) -> Void)? = nil

    @State private var inspectedGlyph: GlyphDecomposition? = nil
    @State private var isFetchingGlyph: Bool = false

    public init(
        tokens: [PhoneticToken],
        fallbackColor: Color = .primary,
        isRTL: Bool = false,
        onInspectCharacter: ((String) -> Void)? = nil
    ) {
        self.tokens = tokens
        self.fallbackColor = fallbackColor
        self.isRTL = isRTL
        self.onInspectCharacter = onInspectCharacter
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: isRTL ? 4 : 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                if isRTL {
                    // Whole-word ligature preservation for Arabic
                    Button {
                        handleTap(text: token.text)
                    } label: {
                        Text(token.text)
                            .foregroundStyle(token.color ?? fallbackColor)
                    }
                    .buttonStyle(GlyphTokenButtonStyle())
                } else {
                    // CJK character-by-character segmentation for tone analysis
                    HStack(spacing: 0) {
                        ForEach(Array(token.text.enumerated()), id: \.offset) { _, ch in
                            Button {
                                handleTap(text: String(ch))
                            } label: {
                                Text(String(ch))
                                    .foregroundStyle(token.color ?? fallbackColor)
                            }
                            .buttonStyle(GlyphTokenButtonStyle())
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .sheet(item: $inspectedGlyph) { glyph in
            GlyphHologramView(
                data: glyph,
                lang: ActiveLanguageContext.shared.code,
                onDismiss: { inspectedGlyph = nil }
            )
        }
    }

    private func handleTap(text: String) {
        guard !text.isEmpty else { return }
        if let onInspectCharacter {
            onInspectCharacter(text)
        } else {
            Task {
                let data = await GlyphLexiconService.shared.fetchGlyph(
                    lang: ActiveLanguageContext.shared.code,
                    character: text
                )
                if let data {
                    self.inspectedGlyph = data
                }
            }
        }
    }
}

extension GlyphDecomposition: Identifiable {
    public var id: String { character }
}

private struct GlyphTokenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
import SwiftUI

public struct GlyphMiniCardView: View {
    public let char: String
    public let role: String
    public let accentColor: Color
    public let lang: String
    public let isFocused: Bool
    public var onSelect: (() -> Void)? = nil

    @State private var details: GlyphDecomposition? = nil
    @State private var isLoading: Bool = false

    private var activeLang: ActiveLanguageContext {
        ActiveLanguageContext.shared
    }

    private var isRTL: Bool {
        activeLang.isRTL || lang.hasPrefix("ar")
    }

    private var hasStrokeData: Bool {
        if let medians = details?.medians, !medians.isEmpty {
            return true
        }
        return false
    }

    public init(
        char: String,
        role: String,
        accentColor: Color,
        lang: String,
        isFocused: Bool = false,
        onSelect: (() -> Void)? = nil
    ) {
        self.char = char
        self.role = role
        self.accentColor = accentColor
        self.lang = lang
        self.isFocused = isFocused
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Card Header: Role & Transliteration
                HStack {
                    Text(role.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)

                    Spacer()

                    if let phon = details?.phonetic ?? details?.pinyin ?? details?.transliteration {
                        Text(phon)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.3))
                        .frame(height: 1)
                }

                // Body: Preview Tile + Meaning
                HStack(spacing: 12) {
                    // Visual Preview Tile
                    previewTile

                    // Character & Definition
                    VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                        Text(char)
                            .font(.system(size: 20, weight: .black, design: isRTL ? .default : .serif))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(details?.definition ?? (isRTL ? "جذر / وزن صرفي" : "Component glyph"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(isRTL ? .trailing : .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                }
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isFocused ? accentColor : Color.primary.opacity(0.08), lineWidth: isFocused ? 1.5 : 1)
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isFocused)
        }
        .buttonStyle(MiniCardButtonStyle())
        .hoverEffect(.lift)
        .task(id: char) {
            guard !char.isEmpty else { return }
            isLoading = true
            details = await GlyphLexiconService.shared.fetchGlyph(lang: lang, character: char)
            isLoading = false
        }
    }

    // MARK: - Visual Preview Tile

    private var previewTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )

            if let medians = details?.medians, !medians.isEmpty {
                // CoreGraphics Path Vector Representation
                GeometryReader { proxy in
                    let scale = min(proxy.size.width, proxy.size.height) / 1024.0

                    ZStack {
                        ForEach(0..<medians.count, id: \.self) { i in
                            StrokeVectorEngine.path(for: medians[i])
                                .stroke(accentColor, style: StrokeStyle(lineWidth: 120 * scale, lineCap: .round, lineJoin: .round))
                                .scaleEffect(y: -1)
                                .offset(y: proxy.size.height)
                        }
                    }
                }
                .padding(8)
            } else {
                // Typographic Root Presentation
                Text(char)
                    .font(.system(size: 24, weight: .bold, design: isRTL ? .default : .serif))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 56, height: 56)
    }
}

private struct MiniCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
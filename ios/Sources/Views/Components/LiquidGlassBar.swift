import SwiftUI
import UIKit

public struct LiquidGlassBar<Item: Identifiable & Equatable>: View {
    public let items: [Item]
    @Binding public var selection: Item
    public let accentColor: Color
    public let iconProvider: (Item) -> String
    public let labelProvider: (Item) -> String

    @Namespace private var liquidBarNamespace

    public init(
        items: [Item],
        selection: Binding<Item>,
        accentColor: Color,
        iconProvider: @escaping (Item) -> String,
        labelProvider: @escaping (Item) -> String
    ) {
        self.items = items
        self._selection = selection
        self.accentColor = accentColor
        self.iconProvider = iconProvider
        self.labelProvider = labelProvider
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item == selection

                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        selection = item
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: iconProvider(item))
                            .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .symbolEffect(.bounce.byLayer, value: isSelected)

                        Text(labelProvider(item))
                            .font(.system(size: 9.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NativeGlassTapButtonStyle())
                .background {
                    if isSelected {
                        // MARK: - Native Refractive Sliding Lens Pill
                        ZStack {
                            // Hardware-accelerated dynamic blur
                            NativeBlurView(style: .systemThinMaterial)
                                .clipShape(Capsule(style: .continuous))

                            // Liquid color wash
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            accentColor.opacity(0.85),
                                            accentColor.opacity(0.65)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            // Specular optical bevel rim
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.85),
                                            Color.white.opacity(0.20),
                                            accentColor.opacity(0.40),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.2
                                )

                            // Top light reflection highlight
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.45))
                                .frame(height: 2)
                                .padding(.horizontal, 14)
                                .offset(y: -14)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .shadow(color: accentColor.opacity(0.35), radius: 10, y: 3)
                        .matchedGeometryEffect(id: "ActiveLiquidDroplet", in: liquidBarNamespace)
                    }
                }
            }
        }
        .frame(height: 58)
        .padding(4)
        .background {
            // MARK: - Native Glass Basin
            ZStack {
                NativeBlurView(style: .systemUltraThinMaterial)
                    .clipShape(Capsule(style: .continuous))

                Capsule(style: .continuous)
                    .fill(Color(uiColor: .systemBackground).opacity(0.18))

                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.65), location: 0.0),
                                .init(color: Color.white.opacity(0.15), location: 0.35),
                                .init(color: accentColor.opacity(0.25), location: 0.70),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
            .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Native Spring Press Button Style

private struct NativeGlassTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.snappy(duration: 0.22, extraBounce: 0.08), value: configuration.isPressed)
    }
}

// MARK: - UIKit Hardware Blur View Bridge

private struct NativeBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        let blur = UIBlurEffect(style: style)
        let view = UIVisualEffectView(effect: blur)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        if context.coordinator.lastStyle != style {
            context.coordinator.lastStyle = style
            uiView.effect = UIBlurEffect(style: style)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(style: style)
    }

    final class Coordinator {
        var lastStyle: UIBlurEffect.Style

        init(style: UIBlurEffect.Style) {
            self.lastStyle = style
        }
    }
}
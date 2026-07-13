import SwiftUI

enum RepVisualSystem {
    static let tint = Color(red: 0.12, green: 0.43, blue: 0.96)
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let pageSpacing: CGFloat = 20
}

struct RepScreenBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)

            LinearGradient(
                colors: [
                    RepVisualSystem.tint.opacity(0.11),
                    RepVisualSystem.tint.opacity(0.035),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 340)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

struct RepGlassEffectGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

private struct RepSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5)
            }
    }
}

private struct RepGlassControlModifier: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(
                    .regular.tint(tint).interactive(interactive),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(
                    .regular.interactive(interactive),
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else {
            content
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

private struct RepPrimaryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private struct RepSecondaryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct RepTabBarBehaviorModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

private struct RepSoftScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            content
        }
    }
}

extension View {
    func repSurface(cornerRadius: CGFloat = RepVisualSystem.cardRadius) -> some View {
        modifier(RepSurfaceModifier(cornerRadius: cornerRadius))
    }

    func repGlassControl(
        tint: Color? = nil,
        cornerRadius: CGFloat = RepVisualSystem.controlRadius,
        interactive: Bool = true
    ) -> some View {
        modifier(RepGlassControlModifier(tint: tint, cornerRadius: cornerRadius, interactive: interactive))
    }

    func repPrimaryButton() -> some View {
        modifier(RepPrimaryButtonModifier())
    }

    func repSecondaryButton() -> some View {
        modifier(RepSecondaryButtonModifier())
    }

    func repTabBarBehavior() -> some View {
        modifier(RepTabBarBehaviorModifier())
    }

    func repSoftScrollEdges() -> some View {
        modifier(RepSoftScrollEdgeModifier())
    }
}

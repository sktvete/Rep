import SwiftUI

enum RepVisualSystem {
    static let tint = Color.accentColor
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let pageSpacing: CGFloat = 20
}

private struct RepMainNavigationTitleModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .largeTitle) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                    }
                }
        } else {
            content.navigationTitle(title)
        }
    }
}

struct RepScreenBackground: View {
    @Environment(\.repThemeSettings) private var themeSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: RepTheme {
        themeSettings.resolved(for: colorScheme)
    }

    var body: some View {
        theme.canvasColor
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
    @Environment(\.repThemeSettings) private var themeSettings
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    private var theme: RepTheme {
        themeSettings.resolved(for: colorScheme)
    }

    func body(content: Content) -> some View {
        content
            .background {
                theme.surfaceColor
                    .clipShape(.rect(cornerRadius: cornerRadius))
                    .shadow(color: theme.backdropShadow, radius: shadowRadius, x: 0, y: shadowY)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

private struct RepSecondaryTextModifier: ViewModifier {
    @Environment(\.repThemeSettings) private var themeSettings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(themeSettings.resolved(for: colorScheme).secondaryText)
    }
}

private struct RepGlassControlModifier: ViewModifier {
    @Environment(\.repThemeSettings) private var themeSettings
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color?
    let cornerRadius: CGFloat
    let interactive: Bool

    private var theme: RepTheme {
        themeSettings.resolved(for: colorScheme)
    }

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
                    .regular
                        .tint(colorScheme == .dark ? theme.neutralControlTint : .clear)
                        .interactive(interactive),
                    in: .rect(cornerRadius: cornerRadius)
                )
            }
        } else {
            content
                .background {
                    if colorScheme == .dark {
                        theme.neutralControlTint
                            .clipShape(.rect(cornerRadius: cornerRadius))
                    }
                }
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

private struct RepPrimaryButtonModifier: ViewModifier {
    @Environment(\.repThemeSettings) private var themeSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: RepTheme {
        themeSettings.resolved(for: colorScheme)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .foregroundStyle(theme.accentContent)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .foregroundStyle(theme.accentContent)
        }
    }
}

private struct RepSecondaryButtonModifier: ViewModifier {
    @Environment(\.repThemeSettings) private var themeSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: RepTheme {
        themeSettings.resolved(for: colorScheme)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if colorScheme == .dark {
                content
                    .buttonStyle(.glass)
                    .tint(theme.neutralControlTint)
                    .foregroundStyle(.primary)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if colorScheme == .dark {
                content
                    .buttonStyle(.bordered)
                    .tint(theme.neutralControlTint)
                    .foregroundStyle(.primary)
            } else {
                content.buttonStyle(.bordered)
            }
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

enum RepThemedList {
    static let rowInsets = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
    static let sectionInsets = EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16)
}

struct RepSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .repSecondaryText()
            .textCase(nil)
    }
}

extension View {
    func repMainNavigationTitle(_ title: String) -> some View {
        modifier(RepMainNavigationTitleModifier(title: title))
    }

    func repSecondaryText() -> some View {
        modifier(RepSecondaryTextModifier())
    }

    func repSurface(
        cornerRadius: CGFloat = RepVisualSystem.cardRadius,
        shadowRadius: CGFloat = 10,
        shadowY: CGFloat = 4
    ) -> some View {
        modifier(
            RepSurfaceModifier(
                cornerRadius: cornerRadius,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func repThemedListRow(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = RepVisualSystem.controlRadius,
        insets: EdgeInsets = RepThemedList.rowInsets
    ) -> some View {
        self
            .padding(padding)
            .repSurface(cornerRadius: cornerRadius)
            .listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    func repThemedListSection(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = RepVisualSystem.controlRadius,
        insets: EdgeInsets = RepThemedList.sectionInsets
    ) -> some View {
        self
            .padding(padding)
            .repSurface(cornerRadius: cornerRadius)
            .listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    func repThemedList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, RepVisualSystem.pageSpacing, for: .scrollContent)
            .repSoftScrollEdges()
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

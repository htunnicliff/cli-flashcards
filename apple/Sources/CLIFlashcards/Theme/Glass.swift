// The backdrop and frosted panes from `theme.dart` (`FrostBackdrop`, `Glass`).

import SwiftUI

/// The soft colour wash behind every page: warm from the top left, cool from
/// the bottom right. Solid mode drops it for the plain background.
struct FrostBackdrop: View {
    @Environment(\.frost) var frost

    var body: some View {
        ZStack {
            frost.bg
            if !frost.solid {
                RadialGradient(
                    colors: [frost.washWarm, frost.washWarm.opacity(0)],
                    center: .topLeading, startRadius: 0, endRadius: 700
                )
                RadialGradient(
                    colors: [frost.washCool, frost.washCool.opacity(0)],
                    center: .bottomTrailing, startRadius: 0, endRadius: 650
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A frosted pane: a card (nearly opaque, light blur) or chrome (clearer,
/// stronger blur). Solid mode gives a plain surface with a border.
struct GlassPane: ViewModifier {
    @Environment(\.frost) var frost
    var radius: CGFloat = Radii.card
    var chrome = false
    var shadow = true
    var padding: CGFloat? = Space.s6

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding ?? 0)
            .background { fill(shape) }
            .overlay { shape.stroke(frost.rim, lineWidth: 1) }
            .shadow(color: shadow ? frost.shadow : .clear, radius: shadow ? 15 : 0, x: 0, y: shadow ? 10 : 0)
    }

    @ViewBuilder private func fill(_ shape: RoundedRectangle) -> some View {
        let tint = chrome ? frost.chrome : frost.card
        if frost.solid {
            shape.fill(frost.surface)
        } else {
            #if os(Android)
            // No backdrop blur on Android. Cards keep their tint, which is
            // nearly opaque; chrome gets the opaque surface so text scrolling
            // under it stays readable.
            shape.fill(chrome ? frost.surface : tint)
            #else
            ZStack {
                shape.fill(chrome ? .thinMaterial : .ultraThinMaterial)
                shape.fill(tint)
                // The sheen along the top edge.
                shape.fill(LinearGradient(
                    colors: [Color.white.opacity(frost.isDark ? 0.05 : 0.5), Color.white.opacity(0)],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)
                ))
            }
            #endif
        }
    }
}

extension View {
    /// Wraps the view in a frosted pane.
    func glass(radius: CGFloat = Radii.card, chrome: Bool = false, shadow: Bool = true, padding: CGFloat? = Space.s6) -> some View {
        modifier(GlassPane(radius: radius, chrome: chrome, shadow: shadow, padding: padding))
    }
}

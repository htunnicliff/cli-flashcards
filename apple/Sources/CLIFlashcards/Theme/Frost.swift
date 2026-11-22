// The "Frost" look, ported from `app/lib/app/theme.dart` (itself from
// `src/app/styles/tokens.css`): frosted glass panes over a soft colour wash.
// Reduce Transparency, Increase Contrast or the in-app setting give the same
// shapes with solid fills.

import SwiftUI

/// Spacing on a 4pt grid.
enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
}

enum Radii {
    static let card: CGFloat = 24
    static let button: CGFloat = 16
    static let code: CGFloat = 10
    static let small: CGFloat = 8
    static let kbd: CGFloat = 5
    static let pill: CGFloat = 999
}

/// The widest a page's content column grows.
let contentWidth: CGFloat = 680

extension Color {
    /// A colour from `0xAARRGGBB`, as the Flutter tokens spell them.
    init(argb: UInt32) {
        self.init(
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}

/// Every colour the screens use. Read it with `@Environment(\.frost)`.
struct Frost: Equatable {
    var isDark: Bool
    var bg: Color
    var surface: Color
    var sunken: Color
    var border: Color
    var text: Color
    var muted: Color
    var accent: Color
    var arg: Color
    var again: Color
    var againTint: Color
    var againBorder: Color
    var onPrimary: Color
    var kbd: Color
    var glassCard: Color
    var glassChrome: Color
    var glassRim: Color
    var glassEdge: Color
    var washWarm: Color
    var washCool: Color
    var primaryTop: Color
    var primaryBottom: Color
    var shadow: Color
    var primaryShadow: Color

    /// Solid surfaces: no blur and no colour wash.
    var solid = false

    /// The app's tint for system controls. Dark mode uses a deeper blue than
    /// `accent` so white labels on filled buttons stay readable.
    var tint: Color { isDark ? Color(argb: 0xFF3F68DE) : accent }

    var card: Color { solid ? surface : glassCard }
    var chrome: Color { solid ? surface : glassChrome }
    var rim: Color { solid ? border : glassRim }

    static let light = Frost(
        isDark: false,
        bg: Color(argb: 0xFFF6F5F2),
        surface: Color(argb: 0xFFFFFFFF),
        sunken: Color(argb: 0xFFEFEDE8),
        border: Color(argb: 0xFFDEDBD3),
        text: Color(argb: 0xFF1D1C1A),
        muted: Color(argb: 0xFF5F5C55),
        accent: Color(argb: 0xFF2B54C9),
        arg: Color(argb: 0xFF9A4A05),
        again: Color(argb: 0xFFA3203A),
        againTint: Color(argb: 0xFFFBE8EB),
        againBorder: Color(argb: 0xFFF2C9D0),
        onPrimary: Color(argb: 0xFFFFFFFF),
        kbd: Color(argb: 0xFFEFEDE8),
        glassCard: Color(argb: 0xD1FFFFFF),
        glassChrome: Color(argb: 0xA8FAF9F6),
        glassRim: Color(argb: 0xE6FFFFFF),
        glassEdge: Color(argb: 0x141D1C1A),
        washWarm: Color(argb: 0x66FFD7AA),
        washCool: Color(argb: 0x59AAC3FF),
        primaryTop: Color(argb: 0xFF3560D4),
        primaryBottom: Color(argb: 0xFF2B54C9),
        shadow: Color(argb: 0x141D1C1A),
        primaryShadow: Color(argb: 0x4D2B54C9)
    )

    static let dark = Frost(
        isDark: true,
        bg: Color(argb: 0xFF121315),
        surface: Color(argb: 0xFF1A1B1E),
        sunken: Color(argb: 0xFF232428),
        border: Color(argb: 0xFF303237),
        text: Color(argb: 0xFFECEAE5),
        muted: Color(argb: 0xFFA19E96),
        accent: Color(argb: 0xFF94B2FF),
        arg: Color(argb: 0xFFF2A65E),
        again: Color(argb: 0xFFFF94A6),
        againTint: Color(argb: 0xFF3A1C23),
        againBorder: Color(argb: 0xFF55283A),
        onPrimary: Color(argb: 0xFF0F1730),
        kbd: Color(argb: 0xFF26272B),
        glassCard: Color(argb: 0xD11E1F23),
        glassChrome: Color(argb: 0xA816171A),
        glassRim: Color(argb: 0x17FFFFFF),
        glassEdge: Color(argb: 0x66000000),
        washWarm: Color(argb: 0x47785028),
        washCool: Color(argb: 0x4D32468C),
        primaryTop: Color(argb: 0xFFA2BCFF),
        primaryBottom: Color(argb: 0xFF94B2FF),
        shadow: Color(argb: 0x59000000),
        primaryShadow: Color(argb: 0x2E94B2FF)
    )

    /// The palette for a colour scheme. `solid` comes from Reduce
    /// Transparency, Increase Contrast or the app's own setting.
    static func resolve(dark: Bool, solid: Bool) -> Frost {
        var frost = dark ? Frost.dark : Frost.light
        frost.solid = solid
        return frost
    }
}

struct FrostKey: EnvironmentKey {
    static let defaultValue = Frost.light
}

extension EnvironmentValues {
    var frost: Frost {
        get { self[FrostKey.self] }
        set { self[FrostKey.self] = newValue }
    }
}

/// Monospaced text for flags and commands, scaling with Dynamic Type.
extension Font {
    static func mono(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .monospaced)
    }
}

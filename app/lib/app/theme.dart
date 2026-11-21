/// The "Frost" look from `src/app/styles/tokens.css`: frosted glass panes over
/// a soft colour wash, set in Recursive. Reduce transparency (the setting, or
/// high contrast on the device) gives the same shapes with solid fills.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const fontFamily = 'RecursiveSans';
const monoFamily = 'RecursiveMono';
const casualFamily = 'RecursiveCasual';
const monoCasualFamily = 'RecursiveMonoCasual';

/// Type scale in logical pixels (tokens.css `--text-*`).
abstract final class TextSizes {
  static const xs = 13.0;
  static const sm = 15.0;
  static const md = 17.0;
  static const lg = 19.0;
  static const xl = 22.0;
  static const x2l = 28.0;
  static const x3l = 40.0;
}

/// Spacing on a 4px grid.
abstract final class Space {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s12 = 48.0;
}

abstract final class Radii {
  static const card = 24.0;
  static const button = 16.0;
  static const code = 10.0;
  static const small = 8.0;
  static const kbd = 5.0;
  static const pill = 999.0;
}

const contentWidth = 680.0;

@immutable
class Frost extends ThemeExtension<Frost> {
  const Frost({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.arg,
    required this.again,
    required this.againTint,
    required this.againBorder,
    required this.onPrimary,
    required this.kbd,
    required this.glassCard,
    required this.glassChrome,
    required this.glassRim,
    required this.glassEdge,
    required this.washWarm,
    required this.washCool,
    required this.primaryTop,
    required this.primaryBottom,
    required this.shadow,
    required this.primaryShadow,
    this.solid = false,
  });

  static const light = Frost(
    brightness: Brightness.light,
    bg: Color(0xFFF6F5F2),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEFEDE8),
    border: Color(0xFFDEDBD3),
    text: Color(0xFF1D1C1A),
    muted: Color(0xFF5F5C55),
    accent: Color(0xFF2B54C9),
    arg: Color(0xFF9A4A05),
    again: Color(0xFFA3203A),
    againTint: Color(0xFFFBE8EB),
    againBorder: Color(0xFFF2C9D0),
    onPrimary: Color(0xFFFFFFFF),
    kbd: Color(0xFFEFEDE8),
    glassCard: Color(0xD1FFFFFF),
    glassChrome: Color(0xA8FAF9F6),
    glassRim: Color(0xE6FFFFFF),
    glassEdge: Color(0x141D1C1A),
    washWarm: Color(0x66FFD7AA),
    washCool: Color(0x59AAC3FF),
    primaryTop: Color(0xFF3560D4),
    primaryBottom: Color(0xFF2B54C9),
    shadow: Color(0x141D1C1A),
    primaryShadow: Color(0x4D2B54C9),
  );

  static const dark = Frost(
    brightness: Brightness.dark,
    bg: Color(0xFF121315),
    surface: Color(0xFF1A1B1E),
    sunken: Color(0xFF232428),
    border: Color(0xFF303237),
    text: Color(0xFFECEAE5),
    muted: Color(0xFFA19E96),
    accent: Color(0xFF94B2FF),
    arg: Color(0xFFF2A65E),
    again: Color(0xFFFF94A6),
    againTint: Color(0xFF3A1C23),
    againBorder: Color(0xFF55283A),
    onPrimary: Color(0xFF0F1730),
    kbd: Color(0xFF26272B),
    glassCard: Color(0xD11E1F23),
    glassChrome: Color(0xA816171A),
    glassRim: Color(0x17FFFFFF),
    glassEdge: Color(0x66000000),
    washWarm: Color(0x47785028),
    washCool: Color(0x4D32468C),
    primaryTop: Color(0xFFA2BCFF),
    primaryBottom: Color(0xFF94B2FF),
    shadow: Color(0x59000000),
    primaryShadow: Color(0x2E94B2FF),
  );

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color sunken;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color arg;
  final Color again;
  final Color againTint;
  final Color againBorder;
  final Color onPrimary;
  final Color kbd;
  final Color glassCard;
  final Color glassChrome;
  final Color glassRim;
  final Color glassEdge;
  final Color washWarm;
  final Color washCool;
  final Color primaryTop;
  final Color primaryBottom;
  final Color shadow;
  final Color primaryShadow;

  /// Solid surfaces, no blur and no colour wash.
  final bool solid;

  Color get card => solid ? surface : glassCard;
  Color get chrome => solid ? surface : glassChrome;
  Color get rim => solid ? border : glassRim;

  static Frost of(BuildContext context) =>
      Theme.of(context).extension<Frost>() ?? light;

  Frost withSolid(bool value) => value == solid ? this : copyWith(solid: value);

  @override
  Frost copyWith({bool? solid}) => Frost(
    brightness: brightness,
    bg: bg,
    surface: surface,
    sunken: sunken,
    border: border,
    text: text,
    muted: muted,
    accent: accent,
    arg: arg,
    again: again,
    againTint: againTint,
    againBorder: againBorder,
    onPrimary: onPrimary,
    kbd: kbd,
    glassCard: glassCard,
    glassChrome: glassChrome,
    glassRim: glassRim,
    glassEdge: glassEdge,
    washWarm: washWarm,
    washCool: washCool,
    primaryTop: primaryTop,
    primaryBottom: primaryBottom,
    shadow: shadow,
    primaryShadow: primaryShadow,
    solid: solid ?? this.solid,
  );

  @override
  Frost lerp(Frost? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return Frost(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      sunken: c(sunken, other.sunken),
      border: c(border, other.border),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      accent: c(accent, other.accent),
      arg: c(arg, other.arg),
      again: c(again, other.again),
      againTint: c(againTint, other.againTint),
      againBorder: c(againBorder, other.againBorder),
      onPrimary: c(onPrimary, other.onPrimary),
      kbd: c(kbd, other.kbd),
      glassCard: c(glassCard, other.glassCard),
      glassChrome: c(glassChrome, other.glassChrome),
      glassRim: c(glassRim, other.glassRim),
      glassEdge: c(glassEdge, other.glassEdge),
      washWarm: c(washWarm, other.washWarm),
      washCool: c(washCool, other.washCool),
      primaryTop: c(primaryTop, other.primaryTop),
      primaryBottom: c(primaryBottom, other.primaryBottom),
      shadow: c(shadow, other.shadow),
      primaryShadow: c(primaryShadow, other.primaryShadow),
      solid: t < 0.5 ? solid : other.solid,
    );
  }
}

ThemeData buildTheme(Frost frost) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: frost.accent,
        brightness: frost.brightness,
      ).copyWith(
        primary: frost.accent,
        onPrimary: frost.onPrimary,
        surface: frost.surface,
        onSurface: frost.text,
        onSurfaceVariant: frost.muted,
        error: frost.again,
        outline: frost.border,
      );
  TextStyle t(double size, [FontWeight weight = FontWeight.w400]) => TextStyle(
    fontFamily: fontFamily,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    fontSize: size,
    fontWeight: weight,
    height: 1.5,
    letterSpacing: 0,
    color: frost.text,
  );
  return ThemeData(
    colorScheme: scheme,
    brightness: frost.brightness,
    scaffoldBackgroundColor: frost.bg,
    fontFamily: fontFamily,
    extensions: [frost],
    textTheme: TextTheme(
      displaySmall: t(TextSizes.x3l, FontWeight.w700).copyWith(height: 1.15),
      headlineMedium: t(TextSizes.x2l, FontWeight.w700).copyWith(height: 1.15),
      headlineSmall: t(TextSizes.xl, FontWeight.w700),
      titleLarge: t(TextSizes.xl, FontWeight.w600),
      titleMedium: t(TextSizes.lg, FontWeight.w600),
      titleSmall: t(TextSizes.md, FontWeight.w600),
      bodyLarge: t(TextSizes.md),
      bodyMedium: t(TextSizes.md),
      bodySmall: t(TextSizes.sm).copyWith(color: frost.muted),
      labelLarge: t(TextSizes.sm, FontWeight.w600),
      labelMedium: t(TextSizes.sm),
      labelSmall: t(TextSizes.xs),
    ),
    dividerTheme: DividerThemeData(color: frost.border, thickness: 1),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: frost.text,
      contentTextStyle: t(TextSizes.sm).copyWith(color: frost.bg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.button),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: frost.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.small),
        borderSide: BorderSide(color: frost.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.small),
        borderSide: BorderSide(color: frost.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.small),
        borderSide: BorderSide(color: frost.accent, width: 2),
      ),
    ),
  );
}

/// Text styles that Material's text theme doesn't cover.
extension FrostText on BuildContext {
  TextStyle get mono => TextStyle(
    fontFamily: monoFamily,
    fontVariations: const [FontVariation('wght', 400)],
    color: Frost.of(this).text,
    fontSize: TextSizes.md,
    height: 1.4,
  );

  TextStyle get casual => TextStyle(
    fontFamily: casualFamily,
    fontVariations: const [FontVariation('wght', 400)],
    color: Frost.of(this).muted,
    fontSize: TextSizes.sm,
    height: 1.5,
  );

  TextStyle get monoCasual => TextStyle(
    fontFamily: monoCasualFamily,
    fontVariations: const [FontVariation('wght', 400)],
    color: Frost.of(this).arg,
    fontSize: TextSizes.md,
  );

  TextStyle get hint =>
      Theme.of(this).textTheme.bodySmall!.copyWith(color: Frost.of(this).muted);
}

/// Bold for variable fonts: weight lives on the `wght` axis.
TextStyle weight(TextStyle style, FontWeight w) => style.copyWith(
  fontWeight: w,
  fontVariations: [FontVariation('wght', w.value.toDouble())],
);

/// The soft colour wash behind everything.
class FrostBackdrop extends StatelessWidget {
  const FrostBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: f.bg),
      child: f.solid
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topLeft,
                        radius: 0.9,
                        colors: [f.washWarm, f.washWarm.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.bottomRight,
                        radius: 0.85,
                        colors: [f.washCool, f.washCool.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
    );
  }
}

/// A frosted pane: card (light blur, nearly opaque) or chrome (strong blur).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s6),
    this.radius = Radii.card,
    this.chrome = false,
    this.shadow = true,
    this.blur = true,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// The header and tab bar: clearer glass, stronger blur.
  final bool chrome;
  final bool shadow;

  /// Off for panes that move, such as a card being swiped: re-blurring the
  /// backdrop on every frame is costly, and over the plain page wash the
  /// blur isn't visible anyway.
  final bool blur;
  final Color? color;

  /// No backdrop blur on the web. The web renderer redraws a blurred layer
  /// whenever anything beneath it moves, which made scrolling and swiping
  /// stutter in Safari on iPhone. Without the blur, the header and tab bar
  /// get an opaque fill so text scrolling under them stays readable.
  static const _blurs = !kIsWeb;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final shape = BorderRadius.circular(radius);
    final fill = chrome
        ? (_blurs || f.solid ? f.chrome : Color.alphaBlend(f.chrome, f.surface))
        : f.card;
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        color: color ?? fill,
        border: Border.all(color: f.rim),
        gradient: f.solid || color != null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.3],
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(
                      alpha: f.brightness == Brightness.light ? 0.5 : 0.05,
                    ),
                    fill,
                  ),
                  fill,
                ],
              ),
      ),
      // Ink and list tiles inside the pane paint on this, above the fill.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    final blurred = f.solid || !blur || !_blurs
        ? pane
        : ClipRRect(
            borderRadius: shape,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: chrome ? 20 : 8,
                sigmaY: chrome ? 20 : 8,
              ),
              child: pane,
            ),
          );
    if (!shadow) return blurred;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(color: f.glassEdge, spreadRadius: 0.5),
          BoxShadow(
            color: f.shadow,
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: blurred,
    );
  }
}

/// Light status bar icons on dark themes, dark on light.
SystemUiOverlayStyle overlayStyle(Frost f) => f.brightness == Brightness.dark
    ? SystemUiOverlayStyle.light
    : SystemUiOverlayStyle.dark;

// Visual language from the reference design: cream paper, near-black ink,
// brick-red accent, serif English (Literata), Mukta for Hindi with Noto Sans
// Devanagari as fallback. Hindi styles carry height >= 1.6 so matras don't clip.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ArthColors extends ThemeExtension<ArthColors> {
  const ArthColors({
    required this.paper,
    required this.card,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.rule,
    required this.highlight,
  });

  final Color paper;
  final Color card;
  final Color ink;
  final Color inkMuted;
  final Color accent;
  final Color rule;

  /// Word highlight under the tooltip.
  final Color highlight;

  static const light = ArthColors(
    paper: Color(0xFFF5F0E8),
    card: Color(0xFFFCFAF6),
    ink: Color(0xFF1F1B17),
    inkMuted: Color(0xFF7C746A),
    accent: Color(0xFF9B3A31),
    rule: Color(0xFFDDD5C8),
    highlight: Color(0x339B3A31),
  );

  static const dark = ArthColors(
    paper: Color(0xFF17140F),
    card: Color(0xFF221D17),
    ink: Color(0xFFECE5D8),
    inkMuted: Color(0xFF9A9187),
    accent: Color(0xFFD26A5E),
    rule: Color(0xFF332C24),
    highlight: Color(0x40D26A5E),
  );

  @override
  ArthColors copyWith({
    Color? paper,
    Color? card,
    Color? ink,
    Color? inkMuted,
    Color? accent,
    Color? rule,
    Color? highlight,
  }) =>
      ArthColors(
        paper: paper ?? this.paper,
        card: card ?? this.card,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        accent: accent ?? this.accent,
        rule: rule ?? this.rule,
        highlight: highlight ?? this.highlight,
      );

  @override
  ArthColors lerp(ArthColors? other, double t) {
    if (other == null) return this;
    return ArthColors(
      paper: Color.lerp(paper, other.paper, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
    );
  }
}

/// Hindi text styles. `scale` comes from settings (S/M/L).
class HindiText {
  const HindiText(this.scale);

  final double scale;

  static const _fallback = ['Noto Sans Devanagari', 'Devanagari Sangam MN'];

  TextStyle _base(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.mukta(
        fontSize: size * scale,
        fontWeight: weight,
        height: 1.6,
        color: color,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Tooltip headline meaning.
  TextStyle headline(Color color) => _base(20, weight: FontWeight.w600, color: color);

  /// Sense meanings in lists.
  TextStyle meaning(Color color) => _base(17, weight: FontWeight.w500, color: color);

  /// Definitions, notes, translations.
  TextStyle body(Color color) => _base(15.5, color: color);

  /// Labels like इस वाक्य में, भावार्थ.
  TextStyle label(Color color) => _base(12.5, weight: FontWeight.w600, color: color);

  TextStyle small(Color color) => _base(13, color: color);
}

/// English (book/dictionary) text styles.
class EnglishText {
  static TextStyle word(Color color, {double size = 22}) => GoogleFonts.literata(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.25,
      );

  static TextStyle body(Color color, {double size = 15}) => GoogleFonts.literata(
        fontSize: size,
        color: color,
        height: 1.45,
      );

  static TextStyle italic(Color color, {double size = 14.5}) => GoogleFonts.literata(
        fontSize: size,
        fontStyle: FontStyle.italic,
        color: color,
        height: 1.45,
      );

  /// Small tracked caps: section labels, tab labels, IPA.
  static TextStyle caps(Color color, {double size = 11}) => GoogleFonts.literata(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
        color: color,
      );

  static TextStyle ipa(Color color) => GoogleFonts.notoSans(
        fontSize: 14,
        color: color,
      );
}

/// The design is a single committed look per brightness.
ThemeData arthTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? ArthColors.dark : ArthColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      surface: c.paper,
      primary: c.accent,
      onSurface: c.ink,
    ),
    scaffoldBackgroundColor: c.paper,
  );
  return base.copyWith(
    extensions: [c],
    textTheme: GoogleFonts.literataTextTheme(base.textTheme).apply(
      bodyColor: c.ink,
      displayColor: c.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: EnglishText.word(c.ink, size: 20),
    ),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: const HindiText(1).small(c.paper),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: UnderlineInputBorder(borderSide: BorderSide(color: c.rule)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.rule)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.accent)),
      hintStyle: EnglishText.body(c.inkMuted, size: 18),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.paper,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => const HindiText(1)
            .label(states.contains(WidgetState.selected) ? c.accent : c.inkMuted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? c.accent : c.inkMuted,
          size: 22,
        ),
      ),
    ),
  );
}

extension ArthThemeContext on BuildContext {
  ArthColors get colors => Theme.of(this).extension<ArthColors>()!;
}

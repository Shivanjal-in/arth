// Visual language from the reference design: cream paper, near-black ink,
// brick-red accent, serif English (Literata), Mukta for Hindi with Noto Sans
// Devanagari as fallback. Hindi styles carry height >= 1.6 so matras don't clip.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette: a corrected schoolbook. Indigo ink for text, lac red (रोली) for
/// the app's own voice, marigold for what's being pointed at, on warm paper;
/// at night the page itself turns indigo.
class ArthColors extends ThemeExtension<ArthColors> {
  const ArthColors({
    required this.paper,
    required this.card,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.marigold,
    required this.rule,
    required this.highlight,
    required this.onAccent,
  });

  final Color paper;
  final Color card;
  final Color ink;
  final Color inkMuted;

  /// Lac red: selection, primary actions, the tab you're on.
  final Color accent;

  /// Marigold: the tapped word, progress, "on" states.
  final Color marigold;
  final Color rule;

  /// Word highlight under the tooltip.
  final Color highlight;

  /// Text on an accent-filled surface.
  final Color onAccent;

  static const light = ArthColors(
    paper: Color(0xFFF4EEE3),
    card: Color(0xFFFCF9F2),
    ink: Color(0xFF1B2233),
    inkMuted: Color(0xFF6B7180),
    accent: Color(0xFFA3271F),
    marigold: Color(0xFFE39A2E),
    rule: Color(0xFFDCD2C1),
    highlight: Color(0x66E39A2E),
    onAccent: Color(0xFFFBF6EC),
  );

  static const dark = ArthColors(
    paper: Color(0xFF151A27),
    card: Color(0xFF1E2536),
    ink: Color(0xFFEDE6D6),
    inkMuted: Color(0xFF9AA0AE),
    accent: Color(0xFFE2705F),
    marigold: Color(0xFFF0B348),
    rule: Color(0xFF2E3648),
    highlight: Color(0x59F0B348),
    onAccent: Color(0xFF151A27),
  );

  @override
  ArthColors copyWith({
    Color? paper,
    Color? card,
    Color? ink,
    Color? inkMuted,
    Color? accent,
    Color? marigold,
    Color? rule,
    Color? highlight,
    Color? onAccent,
  }) =>
      ArthColors(
        paper: paper ?? this.paper,
        card: card ?? this.card,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        accent: accent ?? this.accent,
        marigold: marigold ?? this.marigold,
        rule: rule ?? this.rule,
        highlight: highlight ?? this.highlight,
        onAccent: onAccent ?? this.onAccent,
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
      marigold: Color.lerp(marigold, other.marigold, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
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

/// English interface text: Montserrat, everywhere but a book's own pages.
/// Montserrat sets larger than the serif these sizes were chosen for, so
/// sizes are scaled by [_k] to keep the same visual weight in the layouts.
class EnglishText {
  static const _k = 0.93;

  static TextStyle _m(double size, Color color, {FontWeight weight = FontWeight.w400, FontStyle? style, double height = 1.4, double spacing = 0}) =>
      GoogleFonts.montserrat(fontSize: size * _k, fontWeight: weight, fontStyle: style, color: color, height: height, letterSpacing: spacing);

  static TextStyle word(Color color, {double size = 22}) => _m(size, color, weight: FontWeight.w600, height: 1.25);

  static TextStyle body(Color color, {double size = 15}) => _m(size, color, height: 1.5);

  static TextStyle italic(Color color, {double size = 14.5}) => _m(size, color, style: FontStyle.italic, height: 1.5);

  /// Small labels: sentence case, a touch of tracking, never all-caps.
  static TextStyle label(Color color, {double size = 13}) => _m(size, color, weight: FontWeight.w600, height: 1.3, spacing: 0.1);

  /// Section headings and screen titles.
  static TextStyle heading(Color color, {double size = 20}) => _m(size, color, weight: FontWeight.w600, height: 1.25);

  /// Screen titles: the biggest type on the page.
  static TextStyle title(Color color, {double size = 32}) => _m(size, color, weight: FontWeight.w700, height: 1.1, spacing: -0.3);

  /// Kept for the IPA line and page counters.
  static TextStyle caps(Color color, {double size = 11}) => label(color, size: size);

  static TextStyle ipa(Color color) => GoogleFonts.notoSans(
        fontSize: 14,
        color: color,
      );
}

/// A book's own text (the EPUB reader's pages): a reading serif, not the
/// interface font.
class BookText {
  static TextStyle body(Color color, {double size = 17.5}) => GoogleFonts.literata(fontSize: size, color: color, height: 1.55);

  static TextStyle heading(Color color, {double size = 22}) =>
      GoogleFonts.literata(fontSize: size, fontWeight: FontWeight.w600, color: color, height: 1.2);
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
    // Android: pages fade in while rising a few pixels, a quieter arrival
    // than the default zoom. iOS keeps its own slide and swipe-back.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _RisePageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    textTheme: GoogleFonts.montserratTextTheme(base.textTheme).apply(
      bodyColor: c.ink,
      displayColor: c.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: EnglishText.heading(c.ink, size: 22),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.card,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.rule,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
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

/// Small label style: Montserrat in English, Mukta in Hindi.
TextStyle uiLabel({required bool hindi, required Color color, double scale = 1}) =>
    hindi ? HindiText(scale).label(color) : EnglishText.label(color);

/// Section heading in the interface language.
TextStyle uiHeading({required bool hindi, required Color color, double scale = 1}) =>
    hindi ? HindiText(scale).headline(color) : EnglishText.heading(color);

/// Screen title in the interface language.
TextStyle uiTitle({required bool hindi, required Color color, double scale = 1}) =>
    hindi ? HindiText(scale).headline(color).copyWith(fontSize: 30 * scale) : EnglishText.title(color);

/// Body-ish UI copy (empty states, helper text) in the interface language.
TextStyle uiBody({required bool hindi, required Color color, double scale = 1, double size = 15.5}) =>
    hindi ? HindiText(scale).body(color) : EnglishText.body(color, size: size);

TextStyle uiHeadline({required bool hindi, required Color color, double scale = 1}) =>
    hindi ? HindiText(scale).headline(color) : EnglishText.word(color);

/// Five muted inks for generated book covers, picked by title hash.
const List<Color> kCoverInks = [
  Color(0xFF2F4858),
  Color(0xFF7A3E2C),
  Color(0xFF3F5D3A),
  Color(0xFF5B4A7A),
  Color(0xFF8A6A1F),
];

class _RisePageTransitionsBuilder extends PageTransitionsBuilder {
  const _RisePageTransitionsBuilder();

  static const Curve _arrive = Cubic(0.05, 0.7, 0.1, 1);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(parent: animation, curve: _arrive, reverseCurve: Curves.easeInCubic);
    // The page underneath dims slightly as the new one arrives over it.
    final outgoing = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.92).animate(outgoing),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(incoming),
          child: child,
        ),
      ),
    );
  }
}

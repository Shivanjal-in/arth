// Visual language: neo-brutalist print. Square corners, 2px ink outlines and
// hard, unblurred shadows that controls sink into when pressed. English is
// Barlow Semi Condensed (headings), Inter (body) and Martian Mono (labels);
// Hindi stays on Mukta with Noto Sans Devanagari as fallback, and Hindi styles
// carry height >= 1.6 so matras don't clip.

import 'package:arth/app/feel.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette: deep green-black ink on sage-grey paper, a red for the app's own
/// voice, coral for the thing to press, marigold for what's being pointed at,
/// and maroon for the hard shadows; at night the page turns to ink.
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
    required this.button,
    required this.onButton,
    required this.shadow,
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

  /// Fill of primary buttons and the add button.
  final Color button;
  final Color onButton;

  /// The hard shadow under outlined cards and buttons.
  final Color shadow;

  // The accent is a deeper red than a headline red would be so small labels
  // keep 4.5:1 contrast on paper.
  static const light = ArthColors(
    paper: Color(0xFFE4E5DA),
    card: Color(0xFFF7F7F2),
    ink: Color(0xFF10201D),
    inkMuted: Color(0xFF52635F),
    accent: Color(0xFFB3281C),
    marigold: Color(0xFFF5B726),
    rule: Color(0xFF8CA59E),
    highlight: Color(0x66F5B726),
    onAccent: Color(0xFFF7F7F2),
    button: Color(0xFFE97B77),
    onButton: Color(0xFF10201D),
    shadow: Color(0xFF671912),
  );

  static const dark = ArthColors(
    paper: Color(0xFF10201D),
    card: Color(0xFF1A2E2A),
    ink: Color(0xFFF7F7F2),
    inkMuted: Color(0xFF8CA59E),
    accent: Color(0xFFE97B77),
    marigold: Color(0xFFF5B726),
    rule: Color(0xFF3D5F58),
    highlight: Color(0x59F5B726),
    onAccent: Color(0xFF10201D),
    button: Color(0xFFE97B77),
    onButton: Color(0xFF10201D),
    shadow: Color(0xFF8E2A20),
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
    Color? button,
    Color? onButton,
    Color? shadow,
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
        button: button ?? this.button,
        onButton: onButton ?? this.onButton,
        shadow: shadow ?? this.shadow,
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
      button: Color.lerp(button, other.button, t)!,
      onButton: Color.lerp(onButton, other.onButton, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
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

/// English interface text, everywhere but a book's own pages, in three
/// voices: Barlow Semi Condensed for headings, Inter for reading, Martian
/// Mono for labels. Callers pass sizes tuned for the old interface font, so
/// each voice scales them to keep the same footprint: the condensed face up,
/// the wide mono down.
class EnglishText {
  static const _display = 1.12;
  static const _mono = 0.82;

  static TextStyle _inter(double size, Color color, {FontWeight weight = FontWeight.w400, FontStyle? style, double height = 1.5}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, fontStyle: style, color: color, height: height);

  /// Letter spacing is in ems, as a fraction of the final size.
  static TextStyle _barlow(double size, Color color, {FontWeight weight = FontWeight.w800, double height = 1.1, double em = -0.02}) =>
      GoogleFonts.barlowSemiCondensed(fontSize: size * _display, fontWeight: weight, color: color, height: height, letterSpacing: size * _display * em);

  static TextStyle _martian(double size, Color color, {FontWeight weight = FontWeight.w500, double height = 1.35, double em = 0.02}) =>
      GoogleFonts.martianMono(fontSize: size * _mono, fontWeight: weight, color: color, height: height, letterSpacing: size * _mono * em);

  static TextStyle word(Color color, {double size = 22}) => _barlow(size, color, weight: FontWeight.w700, height: 1.15, em: 0);

  static TextStyle body(Color color, {double size = 15}) => _inter(size, color);

  static TextStyle italic(Color color, {double size = 14.5}) => _inter(size, color, style: FontStyle.italic);

  /// Small labels: mono, a touch of tracking. Mixed case, because a text
  /// style can't uppercase; callers that want the caps look pass caps.
  static TextStyle label(Color color, {double size = 13}) => _martian(size, color);

  /// Section headings and screen titles.
  static TextStyle heading(Color color, {double size = 20}) => _barlow(size, color);

  /// Screen titles: the biggest type on the page.
  static TextStyle title(Color color, {double size = 32}) => _barlow(size, color, height: 1, em: -0.04);

  /// Button text: bold mono.
  static TextStyle button(Color color, {double size = 15}) => _martian(size, color, weight: FontWeight.w700, height: 1.2);

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
  final outline = BorderSide(color: c.ink, width: 2);
  const square = RoundedRectangleBorder();
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
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
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
    cardTheme: CardThemeData(
      color: c.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(side: outline),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(side: outline),
      titleTextStyle: EnglishText.heading(c.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(side: outline),
    ),
    chipTheme: ChipThemeData(
      shape: square,
      side: BorderSide(color: c.ink, width: 1.5),
      color: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.card),
      labelStyle: EnglishText.label(c.ink),
      secondaryLabelStyle: EnglishText.label(c.paper),
      checkmarkColor: c.paper,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.button,
      foregroundColor: c.onButton,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(side: outline),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _inkButton(c, fill: c.card, text: c.ink),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        shape: square,
        textStyle: EnglishText.button(c.accent, size: 14),
      ),
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
      style: _inkButton(c, fill: c.button, text: c.onButton),
    ),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: Border(top: outline),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: const HindiText(1).small(c.paper),
      behavior: SnackBarBehavior.floating,
      shape: square,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: outline),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: outline),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: c.accent, width: 2.5)),
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

/// A button drawn as an outlined face on a hard shadow, pushed into the
/// shadow while pressed. Buttons clip to their bounds once a background
/// builder is set, so the shadow lives inside them.
ButtonStyle _inkButton(ArthColors c, {required Color fill, required Color text}) => ButtonStyle(
  foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.inkMuted : text),
  textStyle: WidgetStatePropertyAll(EnglishText.button(text)),
  shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
  // The outline and fill are drawn by the HardShadow behind the label; the
  // button's own would show in the shadow's two empty corners.
  side: const WidgetStatePropertyAll(BorderSide.none),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
  elevation: const WidgetStatePropertyAll(0),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  splashFactory: NoSplash.splashFactory,
  backgroundBuilder: (context, states, child) {
    final disabled = states.contains(WidgetState.disabled);
    return HardShadow(
      pressed: states.contains(WidgetState.pressed),
      depth: disabled ? 0 : 4,
      color: disabled ? c.paper : fill,
      border: disabled ? c.rule : c.ink,
      child: child!,
    );
  },
);

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

/// Five deep inks for generated book covers, picked by title hash.
const List<Color> kCoverInks = [
  Color(0xFF2E4742),
  Color(0xFF671912),
  Color(0xFF1F4E6B),
  Color(0xFF8A5D13),
  Color(0xFF3D5F58),
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

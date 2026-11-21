// Identité visuelle « enfance » : couleurs pastel vives, formes très arrondies,
// police ronde, bulles décoratives.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

/// Animations décoratives en boucle (désactivées pendant les tests automatisés,
/// sinon `pumpAndSettle` n'aboutit jamais).
const kLoopAnimations = !bool.fromEnvironment('USE_EMULATOR');

/// Répète une animation décorative seulement si les boucles sont actives.
void loopIfEnabled(AnimationController c, {bool reverse = false}) {
  if (kLoopAnimations) c.repeat(reverse: reverse);
}

class Kid {
  static const coral = Color(0xFFFF7A6B);
  static const sun = Color(0xFFFFC24B);
  static const mint = Color(0xFF4CC9A6);
  static const sky = Color(0xFF5DB7F0);
  static const lavender = Color(0xFF9C7CF0);
  static const pink = Color(0xFFFF8FB8);
  static const cream = Color(0xFFFFF8EE);
  static const ink = Color(0xFF2E2A4F);
  static const palette = [coral, sky, mint, sun, lavender, pink];

  static const radius = 24.0;

  static const skyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8FD3FE), Color(0xFFB9A6FF), Color(0xFFFFB3C7)],
  );
  static const sunGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD36E), Color(0xFFFF9A8B)],
  );
}

ThemeData buildKidTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Kid.lavender,
    primary: const Color(0xFF7B5CE6),
    secondary: Kid.coral,
    tertiary: Kid.mint,
    surface: Colors.white,
    brightness: Brightness.light,
  ).copyWith(tertiaryContainer: const Color(0xFFFFF1D6), onTertiaryContainer: Kid.ink);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: GoogleFonts.nunito().fontFamily);
  final fredoka = GoogleFonts.fredoka().fontFamily;
  final body = base.textTheme.apply(bodyColor: Kid.ink, displayColor: Kid.ink);
  TextStyle? f(TextStyle? t) => t?.copyWith(fontFamily: fredoka, fontWeight: FontWeight.w600);
  TextStyle? b8(TextStyle? t) => t?.copyWith(fontWeight: FontWeight.w800);
  final text = body.copyWith(
    headlineLarge: f(body.headlineLarge),
    headlineMedium: f(body.headlineMedium),
    headlineSmall: f(body.headlineSmall),
    titleLarge: f(body.titleLarge),
    titleMedium: b8(body.titleMedium),
    titleSmall: b8(body.titleSmall),
  );
  final round = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Kid.radius));
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(40));
  return base.copyWith(
    scaffoldBackgroundColor: Kid.cream,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 24),
      foregroundColor: Kid.ink,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shadowColor: Kid.lavender.withValues(alpha: .25),
      shape: round,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Kid.lavender.withValues(alpha: .25))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF7B5CE6), width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: const BorderSide(color: Color(0xFF7B5CE6), width: 1.5),
        textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Kid.coral,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: pill,
      side: BorderSide(color: Kid.lavender.withValues(alpha: .3)),
      labelStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: Kid.ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Kid.sun.withValues(alpha: .45),
      elevation: 3,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: const ListTileThemeData(shape: StadiumBorder()),
    dividerTheme: DividerThemeData(color: Kid.lavender.withValues(alpha: .15)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(selectedBackgroundColor: Kid.sun.withValues(alpha: .5)),
    ),
  );
}

/// Fond crème parsemé de bulles colorées qui flottent doucement.
class BubbleBackground extends StatelessWidget {
  final Widget child;
  final bool animate;
  const BubbleBackground({super.key, required this.child, this.animate = true});

  @override
  Widget build(BuildContext context) {
    final bubbles = <(Alignment, double, Color)>[
      (const Alignment(-1.15, -0.95), 150, Kid.sun),
      (const Alignment(1.2, -0.55), 120, Kid.sky),
      (const Alignment(-1.25, 0.35), 100, Kid.mint),
      (const Alignment(1.15, 0.95), 170, Kid.pink),
      (const Alignment(0.3, 1.25), 90, Kid.lavender),
    ];
    return Stack(children: [
      for (final (i, b) in bubbles.indexed)
        Align(
          alignment: b.$1,
          child: _bubble(b.$2, b.$3, i),
        ),
      child,
    ]);
  }

  Widget _bubble(double size, Color c, int i) {
    final w = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: .18)),
    );
    if (!animate || !kLoopAnimations) return w;
    return w
        .animate(onPlay: (ctl) => ctl.repeat(reverse: true))
        .moveY(begin: -8, end: 8, duration: (2600 + i * 500).ms, curve: Curves.easeInOut)
        .scaleXY(begin: .96, end: 1.04, duration: (3000 + i * 400).ms, curve: Curves.easeInOut);
  }
}

/// Avatar rond d'enfant : initiale sur pastille colorée, petit liseré blanc.
class ChildAvatar extends StatelessWidget {
  final String name;
  final int color;
  final double size;
  const ChildAvatar({super.key, required this.name, required this.color, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(c, Colors.white, .25)!, c],
        ),
        border: Border.all(color: Colors.white, width: size / 16),
        boxShadow: [BoxShadow(color: c.withValues(alpha: .35), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: GoogleFonts.fredoka(fontSize: size * .45, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

/// Logo officiel (A arc-en-ciel) dans une pastille blanche qui respire.
class KidLogo extends StatelessWidget {
  final double size;
  const KidLogo({super.key, this.size = 110});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .07),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Kid.lavender.withValues(alpha: .35), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Image.asset('assets/logo_a8.png', fit: BoxFit.contain),
      )
          .animate(onPlay: (c) => loopIfEnabled(c, reverse: true))
          .scaleXY(begin: .97, end: 1.03, duration: 1800.ms, curve: Curves.easeInOut);
}

/// Carte d'indicateur colorée (accueil).
class StatBubble extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const StatBubble({super.key, required this.icon, required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: GoogleFonts.fredoka(fontSize: 20, fontWeight: FontWeight.w600, color: Kid.ink)),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
}

/// Animation d'entrée standard pour les éléments de liste.
extension KidEntrance on Widget {
  Widget entrance(int index) => animate()
      .fadeIn(duration: 350.ms, delay: (math.min(index, 8) * 60).ms)
      .slideY(begin: .12, end: 0, duration: 350.ms, delay: (math.min(index, 8) * 60).ms, curve: Curves.easeOutCubic);
}

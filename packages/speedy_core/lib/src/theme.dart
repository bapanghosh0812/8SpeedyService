import 'dart:math' as math;
import 'package:flutter/material.dart';

class SpeedyPalette {
  static const Color primary = Color(0xFF2C5E80);
  static const Color primarySteel = Color(0xFF537E9B);
  static const Color primaryDark = Color(0xFF1B3E56);
  static const Color logoTileBg = Color(0xFFD5D9DC);

  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color successTeal = Color(0xFF0D9488);
  static const Color dangerRed = Color(0xFFDC2626);

  static const Color lightCanvas = Color(0xFFF5F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color darkCanvas = Color(0xFF0B111B);
  static const Color darkSurface = Color(0xFF131C2B);
}

class SpeedyTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: SpeedyPalette.primary,
      brightness: Brightness.light,
      primary: SpeedyPalette.primary,
      secondary: SpeedyPalette.primarySteel,
      surface: SpeedyPalette.lightSurface,
      error: SpeedyPalette.dangerRed,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: SpeedyPalette.lightCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: SpeedyPalette.lightSurface,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: SpeedyPalette.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SpeedyPalette.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SpeedyPalette.primary, width: 1.8),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: SpeedyPalette.primarySteel,
      brightness: Brightness.dark,
      primary: const Color(0xFF6AA0C2),
      secondary: SpeedyPalette.primarySteel,
      surface: SpeedyPalette.darkSurface,
      error: const Color(0xFFEF4444),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: SpeedyPalette.darkCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: SpeedyPalette.darkSurface,
        foregroundColor: Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: SpeedyPalette.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SpeedyPalette.primarySteel,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F172A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6AA0C2), width: 1.8),
        ),
      ),
    );
  }
}

/// Renders the exact 8SpeedyService interlocking steel-blue double-gear emblem
/// as a crisp vector CustomPainter so it never blurs or pixelates at any screen DPI.
class SpeedyLogoMark extends StatelessWidget {
  final double size;
  final Color gearColor;
  final Color backgroundColor;
  final double borderRadius;

  const SpeedyLogoMark({
    super.key,
    this.size = 40,
    this.gearColor = SpeedyPalette.primarySteel,
    this.backgroundColor = SpeedyPalette.logoTileBg,
    this.borderRadius = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: gearColor.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: CustomPaint(
        painter: _InterlockingGearsPainter(color: gearColor),
      ),
    );
  }
}

class _InterlockingGearsPainter extends CustomPainter {
  final Color color;
  const _InterlockingGearsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.058
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Upper-right larger 8-tooth gear
    _drawGear(
      canvas: canvas,
      paint: stroke,
      center: Offset(size.width * 0.58, size.height * 0.42),
      innerR: size.width * 0.125,
      rootR: size.width * 0.21,
      tipR: size.width * 0.285,
      teeth: 8,
      rotationRad: 0.15,
    );

    // Lower-left interlocking 8-tooth gear
    _drawGear(
      canvas: canvas,
      paint: stroke,
      center: Offset(size.width * 0.36, size.height * 0.64),
      innerR: size.width * 0.095,
      rootR: size.width * 0.16,
      tipR: size.width * 0.22,
      teeth: 8,
      rotationRad: 0.54,
    );
  }

  void _drawGear({
    required Canvas canvas,
    required Paint paint,
    required Offset center,
    required double innerR,
    required double rootR,
    required double tipR,
    required int teeth,
    required double rotationRad,
  }) {
    final path = Path();
    final step = (2 * math.pi) / teeth;
    for (int i = 0; i < teeth; i++) {
      final base = rotationRad + i * step;
      final a1 = base - step * 0.22;
      final a2 = base - step * 0.13;
      final a3 = base + step * 0.13;
      final a4 = base + step * 0.22;

      final p1 = Offset(center.dx + rootR * math.cos(a1), center.dy + rootR * math.sin(a1));
      final p2 = Offset(center.dx + tipR * math.cos(a2), center.dy + tipR * math.sin(a2));
      final p3 = Offset(center.dx + tipR * math.cos(a3), center.dy + tipR * math.sin(a3));
      final p4 = Offset(center.dx + rootR * math.cos(a4), center.dy + rootR * math.sin(a4));

      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(p3.dx, p3.dy);
      path.lineTo(p4.dx, p4.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(center, innerR, paint);
  }

  @override
  bool shouldRepaint(covariant _InterlockingGearsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Brand header lockup used in both Customer and Partner apps.
class SpeedyBrandHeader extends StatelessWidget {
  final String? badgeText;
  final String? subtitle;

  const SpeedyBrandHeader({
    super.key,
    this.badgeText,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SpeedyLogoMark(size: 38),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '8SpeedyService',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (badgeText != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: SpeedyPalette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        badgeText!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: SpeedyPalette.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String formatRupeesFromPaise(int paise) {
  final rupees = paise ~/ 100;
  return '₹$rupees';
}

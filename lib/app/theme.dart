import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Flaxxa Pulse theme — mirrors the Pulse web app's design tokens
/// (`resources/css/tokens/colors.css`: `[data-product="pulse"]` + night mode).

// Brand — Pulse orange → amber.
const Color _brand = Color(0xFFF97316); // orange-500 (primary)
const Color _brandAccent = Color(0xFFF59E0B); // amber-500 (accent)

// Dark "night mode" — navy-slate (NOT the brown a raw orange seed produces).
const Color _dBg = Color(0xFF0F1626); // page background
const Color _dSurface = Color(0xFF141C2E); // cards / app bar / rails
const Color _dSurface2 = Color(0xFF1B2438); // wells / inputs / hovers
const Color _dInk = Color(0xFFEDF1F8); // primary text
const Color _dMuted = Color(0xFF9BA7BF); // secondary text
const Color _dLine = Color(0xFF28324B); // borders
const Color _dBrandSoft = Color(0xFF3A2A17); // dark orange wash

// Light.
const Color _lBg = Color(0xFFF7F9FC);
const Color _lSurface = Color(0xFFFFFFFF);
const Color _lSurface2 = Color(0xFFF1F4F9);
const Color _lInk = Color(0xFF090E1F);
const Color _lMuted = Color(0xFF5A6684);
const Color _lLine = Color(0xFFE2E8F0);
const Color _lBrandSoft = Color(0xFFFFEDD5); // orange-100

ThemeData pulseTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? _dBg : _lBg;
  final surface = isDark ? _dSurface : _lSurface;
  final surface2 = isDark ? _dSurface2 : _lSurface2;
  final ink = isDark ? _dInk : _lInk;
  final muted = isDark ? _dMuted : _lMuted;
  final line = isDark ? _dLine : _lLine;
  final brandSoft = isDark ? _dBrandSoft : _lBrandSoft;

  final scheme = ColorScheme.fromSeed(
    seedColor: _brand,
    brightness: brightness,
  ).copyWith(
    primary: _brand,
    onPrimary: Colors.white,
    secondary: _brandAccent,
    surface: surface,
    onSurface: ink,
    outline: muted,
    outlineVariant: line,
    surfaceContainerHighest: surface2,
    primaryContainer: brandSoft,
    onPrimaryContainer:
        isDark ? const Color(0xFFFFB873) : const Color(0xFF7C2D12),
  );

  final textTheme = GoogleFonts.interTextTheme(
    (isDark ? ThemeData.dark() : ThemeData.light()).textTheme,
  ).apply(bodyColor: ink, displayColor: ink);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w600, color: ink),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      indicatorColor: _brand.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w500, color: muted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? _brand : muted),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: muted),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface2,
      isDense: true,
      hintStyle: TextStyle(color: muted),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _brand, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: _brand, foregroundColor: Colors.white),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

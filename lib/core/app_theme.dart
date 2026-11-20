// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// Design tokens and the Material 3 theme shared by every screen.
///
/// The palette is deliberately small: deep navy for structure, turquoise for
/// actions and highlights, white surfaces and a light grey canvas. It is only
/// used by the application UI — the printed daily journal keeps its own
/// approved paper colours.
class AppTheme {
  const AppTheme._();

  // ---------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------
  static const Color navy = Color(0xFF0B2447);
  static const Color navyDeep = Color(0xFF071A33);
  static const Color navySoft = Color(0xFF1B3A66);
  static const Color turquoise = Color(0xFF14B8A6);
  static const Color turquoiseDeep = Color(0xFF0E8F82);
  static const Color turquoiseWash = Color(0xFFE6FAF7);
  static const Color canvas = Color(0xFFF4F6F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);
  static const Color textStrong = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color success = Color(0xFF0F8F6F);
  static const Color successWash = Color(0xFFE7F7F1);
  static const Color warning = Color(0xFFB45309);
  static const Color warningWash = Color(0xFFFFFBEB);
  static const Color danger = Color(0xFFB3261E);
  static const Color dangerWash = Color(0xFFFDECEA);

  // ---------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------
  static const double radiusSmall = 10;
  static const double radius = 16;
  static const double radiusLarge = 22;
  static const double gutter = 16;
  static const double minTouchTarget = 52;

  /// Legacy aliases kept so existing screens keep compiling while they migrate
  /// to the new tokens.
  static const Color brandPrimary = navy;
  static const Color brandSecondary = turquoise;
  static const Color surfaceCanvas = canvas;
  static const Color borderSubtle = border;
  static const Color positiveGreen = success;
  static const Color warningAmber = warning;
  static const Color dangerRed = danger;

  static ColorScheme get colorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: Brightness.light,
    );
    return base.copyWith(
      primary: navy,
      onPrimary: Colors.white,
      primaryContainer: navySoft,
      onPrimaryContainer: Colors.white,
      secondary: turquoise,
      onSecondary: const Color(0xFF04322D),
      secondaryContainer: turquoiseWash,
      onSecondaryContainer: const Color(0xFF064E45),
      tertiary: turquoiseDeep,
      onTertiary: Colors.white,
      error: danger,
      onError: Colors.white,
      errorContainer: dangerWash,
      onErrorContainer: const Color(0xFF5F1512),
      surface: surface,
      onSurface: textStrong,
      onSurfaceVariant: textMuted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: surfaceMuted,
      surfaceContainer: canvas,
      surfaceContainerHigh: const Color(0xFFEEF2F6),
      surfaceContainerHighest: const Color(0xFFE8EDF3),
      outline: borderStrong,
      outlineVariant: border,
      shadow: const Color(0x1A0B2447),
      scrim: const Color(0x66071A33),
      inverseSurface: navyDeep,
      onInverseSurface: Colors.white,
      inversePrimary: const Color(0xFF8FD9D2),
    );
  }

  static TextTheme _textTheme() {
    const family = 'Tajawal';
    return const TextTheme(
      displaySmall: TextStyle(
        fontFamily: family,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: textStrong,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontFamily: family,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: textStrong,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontFamily: family,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textStrong,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontFamily: family,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textStrong,
      ),
      titleMedium: TextStyle(
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textStrong,
      ),
      titleSmall: TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textMuted,
      ),
      bodyLarge: TextStyle(
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: textStrong,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontFamily: family,
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: textStrong,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamily: family,
        fontSize: 13,
        color: textMuted,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontFamily: family,
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        fontFamily: family,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textMuted,
      ),
    );
  }

  static ThemeData light() {
    final scheme = colorScheme;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Tajawal',
      colorScheme: scheme,
      textTheme: _textTheme(),
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.6,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: navy, size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        labelStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textMuted,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: turquoiseDeep,
        ),
        hintStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 16,
          color: Color(0xFF94A3B8),
        ),
        prefixIconColor: navy,
        suffixIconColor: textMuted,
        suffixStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textMuted,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 4),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 4),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 4),
          borderSide: const BorderSide(color: turquoise, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 4),
          borderSide: const BorderSide(color: danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 4),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          backgroundColor: navy,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall + 4),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          foregroundColor: navy,
          side: const BorderSide(color: borderStrong),
          textStyle: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall + 4),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: turquoiseDeep,
          textStyle: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: turquoiseWash,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textStrong,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        height: 74,
        elevation: 0,
        indicatorColor: turquoiseWash,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? navy : textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected) ? navy : textMuted,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: navy, size: 26),
        unselectedIconTheme: IconThemeData(color: textMuted, size: 24),
        selectedLabelTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textMuted,
        ),
        indicatorColor: turquoiseWash,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: turquoise,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        extendedTextStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLarge)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navyDeep,
        contentTextStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 2),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: navy,
        textColor: textStrong,
        minVerticalPadding: 12,
        titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textStrong,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 13.5,
          color: textMuted,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: turquoise,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: navyDeep,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 13,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Prominent accent action (turquoise) used for primary calls to action such
  /// as saving a collection entry.
  static ButtonStyle get accentAction => FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        backgroundColor: turquoise,
        foregroundColor: const Color(0xFF04322D),
        textStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 6),
        ),
      );
}

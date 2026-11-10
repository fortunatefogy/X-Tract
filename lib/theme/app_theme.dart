import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF6C3BF4);
  static const teal = Color(0xFF14B8A6);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFE5484D);
  static const white = Color(0xFFFFFFFF);
}

class AppPalette {
  const AppPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.border,
    required this.input,
    required this.destructive,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color border;
  final Color input;
  final Color destructive;

  static const light = AppPalette(
    background: Color(0xFFF6F7FA),
    foreground: Color(0xFF13151C),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF13151C),
    secondary: Color(0xFFEBEDF3),
    secondaryForeground: Color(0xFF1D2030),
    muted: Color(0xFFEFF1F6),
    mutedForeground: Color(0xFF6A7080),
    accent: Color(0xFFEEE9FF),
    accentForeground: Color(0xFF4B22C4),
    border: Color(0xFFE2E5ED),
    input: Color(0xFFEFF1F6),
    destructive: Color(0xFFE5484D),
  );

  static const dark = AppPalette(
    background: Color(0xFF0F1117),
    foreground: Color(0xFFF2F4F8),
    card: Color(0xFF171A22),
    cardForeground: Color(0xFFF2F4F8),
    secondary: Color(0xFF1F232D),
    secondaryForeground: Color(0xFFE7EAF1),
    muted: Color(0xFF1C2029),
    mutedForeground: Color(0xFF9AA1B2),
    accent: Color(0xFF241C3D),
    accentForeground: Color(0xFFC9B8FF),
    border: Color(0xFF272C38),
    input: Color(0xFF1C2029),
    destructive: Color(0xFFFF6B6F),
  );
}

class AppRadius {
  static const card = 24.0;
  static const inner = 16.0;
  static const pill = 999.0;
}

class AppText {
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color? color,
    double? height,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -0.6,
      );

  static TextStyle heading(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? height,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -0.3,
      );

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? height,
  }) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  static TextStyle label(double size, {Color? color}) => GoogleFonts.manrope(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.8,
      );
}

class AppTheme {
  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      secondary: palette.secondary,
      onSecondary: palette.secondaryForeground,
      error: palette.destructive,
      onError: AppColors.white,
      surface: palette.card,
      onSurface: palette.cardForeground,
      surfaceContainerHighest: palette.muted,
      onSurfaceVariant: palette.mutedForeground,
      outline: palette.border,
      outlineVariant: palette.border,
      primaryContainer: palette.accent,
      onPrimaryContainer: palette.accentForeground,
    );

    final base = GoogleFonts.manropeTextTheme().apply(
      bodyColor: palette.foreground,
      displayColor: palette.foreground,
    );

    final textTheme = base.copyWith(
      displayLarge: AppText.display(40, color: palette.foreground),
      displayMedium: AppText.display(34, color: palette.foreground),
      displaySmall: AppText.display(30, color: palette.foreground),
      headlineLarge: AppText.display(28, color: palette.foreground),
      headlineMedium: AppText.display(26, color: palette.foreground),
      headlineSmall: AppText.display(24, color: palette.foreground),
      titleLarge: AppText.heading(20, color: palette.foreground),
      titleMedium: AppText.heading(17, weight: FontWeight.w600,
          color: palette.foreground),
      titleSmall: AppText.heading(15, weight: FontWeight.w600,
          color: palette.foreground),
      bodyLarge: AppText.body(15, color: palette.foreground),
      bodyMedium: AppText.body(14, color: palette.foreground),
      bodySmall: AppText.body(12, color: palette.mutedForeground),
      labelLarge: AppText.body(14, weight: FontWeight.w700,
          color: palette.foreground),
      labelMedium: AppText.body(12, weight: FontWeight.w600,
          color: palette.mutedForeground),
      labelSmall: AppText.label(11, color: palette.mutedForeground),
    );

    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      fontFamily: GoogleFonts.manrope().fontFamily,
      textTheme: textTheme,
      dividerColor: palette.border,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.heading(20, color: palette.foreground),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: palette.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: palette.secondary,
          disabledForegroundColor: palette.mutedForeground,
          minimumSize: const Size(0, 48),
          shape: pill,
          textStyle: AppText.body(14, weight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppText.body(13, weight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.foreground,
          side: BorderSide(color: palette.border),
          minimumSize: const Size(0, 44),
          shape: pill,
          textStyle: AppText.body(13, weight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppText.body(14, color: palette.mutedForeground),
        labelStyle: AppText.body(14, color: palette.mutedForeground),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.inner),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.inner),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.inner),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.foreground,
        contentTextStyle: AppText.body(13, color: palette.background),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.inner),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        titleTextStyle: AppText.heading(20, color: palette.foreground),
        contentTextStyle: AppText.body(14, color: palette.mutedForeground),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: palette.foreground.withValues(alpha: 0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.white
              : palette.card,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : palette.muted,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(AppColors.white),
        side: BorderSide(color: palette.border, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.mutedForeground,
        textColor: palette.foreground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearMinHeight: 6,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        thumbColor: AppColors.white,
        overlayColor: AppColors.primary.withValues(alpha: 0.16),
        inactiveTrackColor: palette.muted,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppText.body(14, color: palette.foreground),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(palette.card),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.inner),
              side: BorderSide(color: palette.border),
            ),
          ),
        ),
      ),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}

extension AppTextThemeContext on BuildContext {
  TextTheme get texts => Theme.of(this).textTheme;
}

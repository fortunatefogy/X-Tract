import 'package:flutter/material.dart';

const String _displayFamily = 'Outfit';
const String _bodyFamily = 'Manrope';

class AppColors {
  static const primary = Color(0xFF6C3BF4);
  static const primaryDeep = Color(0xFF530DDC);
  static const primaryPressed = Color(0xFF5928E5);
  static const primarySoft = Color(0xFFEEE9FF);
  static const primarySoftForeground = Color(0xFF4B22C4);
  static const heroStart = Color(0xFF8B5CF6);
  static const heroEnd = Color(0xFF530DDC);

  static const teal = Color(0xFF14B8A6);
  static const tealSoft = Color(0xFFE6F8F5);
  static const tealDeep = Color(0xFF0D766A);

  static const amber = Color(0xFFF59E0B);
  static const amberSoft = Color(0xFFFEF3C7);
  static const amberDeep = Color(0xFF92400E);

  static const red = Color(0xFFE5484D);
  static const redSoft = Color(0xFFFEE2E2);
  static const redDeep = Color(0xFF991B1B);

  static const ink = Color(0xFF0F172A);
  static const slate = Color(0xFF64748B);
  static const slateLight = Color(0xFF94A3B8);

  static const white = Color(0xFFFFFFFF);

  // Dark chrome used by the browser and immersive player.
  static const forest = Color(0xFF12101C);
  static const forestSurface = Color(0xFF1B1826);
  static const forestBorder = Color(0xFF2B2740);
  static const forestText = Color(0xFFF3F0FF);
  static const forestMuted = Color(0xFFA9A2C4);
  static const forestAccent = Color(0xFFB9A4FF);
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
    background: Color(0xFF0F1017),
    foreground: Color(0xFFF2F3F7),
    card: Color(0xFF171922),
    cardForeground: Color(0xFFF2F3F7),
    secondary: Color(0xFF232633),
    secondaryForeground: Color(0xFFF2F3F7),
    muted: Color(0xFF1C1F2A),
    mutedForeground: Color(0xFF9AA1B2),
    accent: Color(0xFF2A2050),
    accentForeground: Color(0xFFC4B3FF),
    border: Color(0xFF2A2D3A),
    input: Color(0xFF1C1F2A),
    destructive: Color(0xFFFF8A8E),
  );
}

class AppRadius {
  static const card = 24.0;
  static const inner = 16.0;
  static const small = 12.0;
  static const pill = 999.0;
}

class AppShadow {
  static List<BoxShadow> get cta => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.18),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get floating => [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.10),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];
}

class AppText {
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _displayFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -size * 0.03,
      );

  static TextStyle heading(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _displayFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -size * 0.018,
      );

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _bodyFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: size * 0.005,
      );

  static TextStyle label(double size, {Color? color}) => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: size * 0.06,
      );
}

class AppTheme {
  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: palette.accent,
      onPrimaryContainer: palette.accentForeground,
      secondary: palette.secondary,
      onSecondary: palette.secondaryForeground,
      secondaryContainer: palette.accent,
      onSecondaryContainer: palette.accentForeground,
      error: palette.destructive,
      onError: AppColors.white,
      errorContainer: isDark ? const Color(0xFF3A1620) : AppColors.redSoft,
      onErrorContainer: isDark ? const Color(0xFFFFC2C4) : AppColors.redDeep,
      surface: palette.card,
      onSurface: palette.cardForeground,
      surfaceContainerHighest: palette.muted,
      onSurfaceVariant: palette.mutedForeground,
      outline: palette.border,
      outlineVariant: palette.border,
      shadow: const Color(0x1A0F172A),
      scrim: const Color(0x590F172A),
      inverseSurface: palette.foreground,
      onInverseSurface: palette.background,
      inversePrimary: AppColors.primarySoft,
    );

    final base = const TextTheme().apply(
      bodyColor: palette.foreground,
      displayColor: palette.foreground,
      fontFamily: _bodyFamily,
    );

    final textTheme = base.copyWith(
      displayLarge: AppText.display(40, color: palette.foreground),
      displayMedium: AppText.display(32, color: palette.foreground),
      displaySmall: AppText.display(28, color: palette.foreground),
      headlineLarge: AppText.display(28, color: palette.foreground),
      headlineMedium: AppText.display(24, color: palette.foreground),
      headlineSmall: AppText.heading(22, color: palette.foreground),
      titleLarge: AppText.heading(20, color: palette.foreground),
      titleMedium: AppText.heading(17,
          weight: FontWeight.w600, color: palette.foreground),
      titleSmall: AppText.heading(15,
          weight: FontWeight.w600, color: palette.foreground),
      bodyLarge: AppText.body(16, color: palette.foreground),
      bodyMedium: AppText.body(14, color: palette.foreground),
      bodySmall: AppText.body(12, color: palette.mutedForeground),
      labelLarge: AppText.body(14,
          weight: FontWeight.w700, color: palette.foreground),
      labelMedium: AppText.body(12,
          weight: FontWeight.w600, color: palette.mutedForeground),
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
      fontFamily: _bodyFamily,
      textTheme: textTheme,
      dividerColor: palette.border,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
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
          textStyle: AppText.body(14, weight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24),
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
      iconTheme: IconThemeData(color: palette.foreground, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.input,
        hintStyle: AppText.body(14, color: AppColors.slateLight),
        labelStyle: AppText.body(14, color: palette.mutedForeground),
        prefixIconColor: palette.mutedForeground,
        suffixIconColor: palette.mutedForeground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? palette.card : AppColors.ink,
        contentTextStyle: AppText.body(13,
            color: isDark ? palette.foreground : AppColors.white),
        actionTextColor: isDark ? AppColors.forestAccent : AppColors.primarySoft,
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
        modalBarrierColor: AppColors.ink.withValues(alpha: 0.35),
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
              : palette.secondary,
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
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : palette.mutedForeground,
        ),
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
        inactiveTrackColor: palette.secondary,
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
      popupMenuTheme: PopupMenuThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        textStyle: AppText.body(14, color: palette.foreground),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.inner),
          side: BorderSide(color: palette.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? palette.card : AppColors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppText.body(12,
            color: isDark ? palette.foreground : AppColors.white),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.card,
        selectedColor: AppColors.primary,
        side: BorderSide(color: palette.border),
        labelStyle: AppText.body(12, color: palette.foreground),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
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

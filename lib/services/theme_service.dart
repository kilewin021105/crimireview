import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeService() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 1;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }
}

// ================================================================
// Design system (2026-10 redesign)
// ================================================================
// Every screen reads its colours from [AppPalette] via `context.palette`,
// so light and dark mode come from one place instead of `isDark ? a : b`
// scattered through each screen. The typeface (Plus Jakarta Sans) is
// bundled in assets/fonts, so it renders even on a first launch with no
// internet.

/// The app's typeface, bundled in pubspec.yaml under `fonts:`.
const String kAppFontFamily = 'PlusJakartaSans';

/// Colour tokens for one brightness. Read with `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color onPrimarySoft;

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color streak;
  final Color streakSoft;
  final Color gold;
  final Color goldSoft;

  final LinearGradient heroGradient;
  final Color shadow;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.streak,
    required this.streakSoft,
    required this.gold,
    required this.goldSoft,
    required this.heroGradient,
    required this.shadow,
  });

  // Brand: the app icon's navy and gold. Royal blue is the interactive
  // colour (buttons, links, selection), deep navy anchors the hero cards,
  // and gold marks points, ranks and achievements.
  static const light = AppPalette(
    background: Color(0xFFF4F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF1F7),
    border: Color(0xFFE2E6EF),
    textPrimary: Color(0xFF0D1530),
    textSecondary: Color(0xFF556079),
    textTertiary: Color(0xFF8F98AE),
    primary: Color(0xFF2449D8),
    primaryStrong: Color(0xFF1A36A8),
    primarySoft: Color(0xFFE8EDFD),
    onPrimarySoft: Color(0xFF1A36A8),
    success: Color(0xFF12A150),
    successSoft: Color(0xFFE6F6ED),
    warning: Color(0xFFD98506),
    warningSoft: Color(0xFFFEF3E0),
    danger: Color(0xFFE5484D),
    dangerSoft: Color(0xFFFDECEC),
    info: Color(0xFF0B8FD9),
    infoSoft: Color(0xFFE5F3FC),
    streak: Color(0xFFF2661B),
    streakSoft: Color(0xFFFEEEE4),
    gold: Color(0xFFC08A0E),
    goldSoft: Color(0xFFFBF3DC),
    heroGradient: LinearGradient(
      colors: [Color(0xFF2C55E8), Color(0xFF13286E)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    shadow: Color(0x140D1530),
  );

  static const dark = AppPalette(
    background: Color(0xFF090C15),
    surface: Color(0xFF121724),
    surfaceAlt: Color(0xFF1A2031),
    border: Color(0xFF242B3F),
    textPrimary: Color(0xFFF1F4FA),
    textSecondary: Color(0xFFA2ABC0),
    textTertiary: Color(0xFF6A7389),
    primary: Color(0xFF6E8BFF),
    primaryStrong: Color(0xFF4F6EF0),
    primarySoft: Color(0xFF17224A),
    onPrimarySoft: Color(0xFFC0CCFF),
    success: Color(0xFF2FCB72),
    successSoft: Color(0xFF11291C),
    warning: Color(0xFFF5A524),
    warningSoft: Color(0xFF2E2210),
    danger: Color(0xFFF26D70),
    dangerSoft: Color(0xFF321617),
    info: Color(0xFF3BB0F0),
    infoSoft: Color(0xFF0F2533),
    streak: Color(0xFFFF8340),
    streakSoft: Color(0xFF33200F),
    gold: Color(0xFFF2C14E),
    goldSoft: Color(0xFF2C2512),
    heroGradient: LinearGradient(
      colors: [Color(0xFF3459E6), Color(0xFF111F55)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    shadow: Color(0x40000000),
  );

  /// Green / amber / red for a 0-100 score, used by results, readiness
  /// and mastery displays so "good" means the same colour everywhere.
  Color forScore(double percent) {
    if (percent >= 75) return success;
    if (percent >= 50) return warning;
    return danger;
  }

  Color softForScore(double percent) {
    if (percent >= 75) return successSoft;
    if (percent >= 50) return warningSoft;
    return dangerSoft;
  }

  /// Easy / medium / hard as the same three colours everywhere.
  Color forDifficulty(int level) {
    switch (level) {
      case 0:
        return success;
      case 1:
        return warning;
      case 2:
        return danger;
      default:
        return primary;
    }
  }

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      border: c(border, other.border),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      primary: c(primary, other.primary),
      primaryStrong: c(primaryStrong, other.primaryStrong),
      primarySoft: c(primarySoft, other.primarySoft),
      onPrimarySoft: c(onPrimarySoft, other.onPrimarySoft),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      streak: c(streak, other.streak),
      streakSoft: c(streakSoft, other.streakSoft),
      gold: c(gold, other.gold),
      goldSoft: c(goldSoft, other.goldSoft),
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      shadow: c(shadow, other.shadow),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
  TextTheme get textStyles => Theme.of(this).textTheme;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

/// Spacing and corner radii shared by every screen.
class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 28;

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
}

// ----------------------------------------------------------------
// Legacy names, kept so older code keeps compiling. New code should
// use `context.palette` instead.
// ----------------------------------------------------------------
class CrimiColors {
  static const Color deepNavy = Color(0xFF090C15);
  static const Color navyBlue = Color(0xFF121724);
  static const Color darkNavy = Color(0xFF090C15);
  static const Color purple = Color(0xFF2449D8);
  static const Color lightPurple = Color(0xFF6E8BFF);
  static const Color darkPurple = Color(0xFF1A36A8);
  static const Color gold = Color(0xFFC08A0E);
  static const Color emerald = Color(0xFF12A150);

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFF2C55E8), Color(0xFF13286E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient purpleGradient = goldGradient;
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF090C15), Color(0xFF121724)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient navyGradient = backgroundGradient;
}

class AppColors {
  static const Color primary = Color(0xFF2449D8);
  static const Color primaryLight = Color(0xFF6E8BFF);
  static const Color primaryDark = Color(0xFF1A36A8);

  static const Color accent = Color(0xFF2449D8);
  static const Color accentLight = Color(0xFF6E8BFF);
  static const Color accentDark = Color(0xFF1A36A8);

  static const Color secondary = Color(0xFF0B8FD9);
  static const Color tertiary = Color(0xFF8F98AE);

  static const Color success = Color(0xFF12A150);
  static const Color successLight = Color(0xFF2FCB72);
  static const Color error = Color(0xFFE5484D);
  static const Color errorLight = Color(0xFFF26D70);
  static const Color warning = Color(0xFFD98506);

  static const Color darkBg = Color(0xFF090C15);
  static const Color darkCard = Color(0xFF121724);
  static const Color darkSurface = Color(0xFF1A2031);
  static const Color lightBg = Color(0xFFF4F6FB);
  static const Color lightCard = Colors.white;
  static const Color lightSurface = Color(0xFFEEF1F7);

  static const Color textDark = Color(0xFF0D1530);
  static const Color textLight = Color(0xFFF1F4FA);
  static const Color textMuted = Color(0xFF8F98AE);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2C55E8), Color(0xFF13286E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient accentGradient = primaryGradient;
  static const LinearGradient goldGradient = primaryGradient;
  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF121724), Color(0xFF090C15)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF2FCB72), Color(0xFF12A150)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient errorGradient = LinearGradient(
    colors: [Color(0xFFF26D70), Color(0xFFE5484D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// One colour per subject, used for its icon, tags and progress bars.
  static const Map<String, Color> subjectColors = {
    'criminal_jurisprudence': Color(0xFF5B5BD6), // Indigo
    'law_enforcement': Color(0xFF2F80ED),        // Blue
    'criminalistics': Color(0xFF8E54E9),         // Violet
    'crime_detection': Color(0xFF0E9F9A),        // Teal
    'criminology': Color(0xFFE3478C),            // Pink
    'corrections': Color(0xFFE08A0B),            // Amber
  };

  static Color subjectColor(String id) =>
      subjectColors[id] ?? const Color(0xFF2449D8);

  static final Map<String, LinearGradient> subjectGradients = {
    for (final e in subjectColors.entries)
      e.key: LinearGradient(
        colors: [Color.lerp(e.value, Colors.white, 0.18)!, e.value],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
  };
}

class AppTheme {
  static const Map<String, Color> subjectColors = AppColors.subjectColors;

  static const Map<String, IconData> subjectIcons = {
    'criminal_jurisprudence': Icons.gavel_rounded,
    'law_enforcement': Icons.local_police_rounded,
    'criminalistics': Icons.fingerprint_rounded,
    'crime_detection': Icons.search_rounded,
    'criminology': Icons.psychology_rounded,
    'corrections': Icons.account_balance_rounded,
  };

  static final ThemeData lightTheme = _build(AppPalette.light, Brightness.light);
  static final ThemeData darkTheme = _build(AppPalette.dark, Brightness.dark);

  static TextTheme _textTheme(AppPalette p) {
    TextStyle s(double size, FontWeight w,
            {double height = 1.3, double spacing = 0, Color? color}) =>
        TextStyle(
          fontFamily: kAppFontFamily,
          fontSize: size,
          fontWeight: w,
          height: height,
          letterSpacing: spacing,
          color: color ?? p.textPrimary,
        );
    return TextTheme(
      displayLarge: s(44, FontWeight.w800, height: 1.1, spacing: -1.2),
      displayMedium: s(38, FontWeight.w800, height: 1.1, spacing: -1),
      displaySmall: s(32, FontWeight.w800, height: 1.15, spacing: -0.8),
      headlineLarge: s(28, FontWeight.w800, height: 1.2, spacing: -0.6),
      headlineMedium: s(25, FontWeight.w800, height: 1.2, spacing: -0.5),
      headlineSmall: s(21, FontWeight.w700, height: 1.25, spacing: -0.3),
      titleLarge: s(18, FontWeight.w700, height: 1.3, spacing: -0.2),
      titleMedium: s(16, FontWeight.w700, height: 1.35, spacing: -0.1),
      titleSmall: s(14, FontWeight.w600, height: 1.35),
      bodyLarge: s(15.5, FontWeight.w400, height: 1.55),
      bodyMedium: s(14, FontWeight.w400, height: 1.5, color: p.textSecondary),
      bodySmall: s(12.5, FontWeight.w500, height: 1.45, color: p.textSecondary),
      labelLarge: s(14.5, FontWeight.w700, height: 1.2),
      labelMedium: s(12.5, FontWeight.w600, height: 1.2, color: p.textSecondary),
      labelSmall: s(11, FontWeight.w700, height: 1.2, spacing: 0.4, color: p.textTertiary),
    );
  }

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final text = _textTheme(p);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: Colors.white,
      primaryContainer: p.primarySoft,
      onPrimaryContainer: p.onPrimarySoft,
      secondary: p.info,
      onSecondary: Colors.white,
      secondaryContainer: p.infoSoft,
      onSecondaryContainer: p.info,
      tertiary: p.streak,
      onTertiary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceAlt,
      surfaceContainerHigh: p.surfaceAlt,
      surfaceContainerHighest: p.surfaceAlt,
      outline: p.border,
      outlineVariant: p.border,
      shadow: Colors.black,
      inverseSurface: isDark ? p.surfaceAlt : p.textPrimary,
      onInverseSurface: isDark ? p.textPrimary : Colors.white,
      inversePrimary: p.primarySoft,
    );

    final radiusMd = BorderRadius.circular(AppSpace.radiusMd);
    // Filled buttons use the deeper blue in dark mode so white labels keep
    // enough contrast; links and selection keep the lighter primary.
    final buttonColor = isDark ? p.primaryStrong : p.primary;
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: kAppFontFamily,
      colorScheme: scheme,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: [p],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        iconTheme: IconThemeData(color: p.textPrimary, size: 22),
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpace.radiusLg),
          side: BorderSide(color: p.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: buttonColor.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: buttonColor.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: BorderSide(color: p.border, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: text.labelLarge?.copyWith(fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.radiusSm)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder(p.border),
        enabledBorder: inputBorder(p.border),
        focusedBorder: inputBorder(p.primary, 1.6),
        errorBorder: inputBorder(p.danger),
        focusedErrorBorder: inputBorder(p.danger, 1.6),
        disabledBorder: inputBorder(p.border.withValues(alpha: 0.5)),
        labelStyle: text.bodyMedium,
        floatingLabelStyle: text.labelMedium?.copyWith(color: p.primary),
        hintStyle: text.bodyMedium?.copyWith(color: p.textTertiary),
        prefixIconColor: p.textTertiary,
        suffixIconColor: p.textTertiary,
        errorStyle: text.bodySmall?.copyWith(color: p.danger),
        helperStyle: text.bodySmall,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primarySoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 23,
              color: states.contains(WidgetState.selected) ? p.primary : p.textTertiary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelSmall?.copyWith(
              fontSize: 11.5,
              letterSpacing: 0,
              color: states.contains(WidgetState.selected) ? p.textPrimary : p.textTertiary,
            )),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: buttonColor,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: text.labelLarge,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        selectedColor: p.primarySoft,
        disabledColor: p.surfaceAlt,
        side: BorderSide.none,
        checkmarkColor: p.onPrimarySoft,
        labelStyle: text.labelMedium?.copyWith(color: p.textPrimary),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: p.onPrimarySoft),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.radiusSm)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.radiusXl)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: p.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpace.radiusXl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: isDark ? p.surfaceAlt : p.textPrimary,
        contentTextStyle: text.bodyMedium?.copyWith(color: isDark ? p.textPrimary : Colors.white),
        actionTextColor: isDark ? p.primary : const Color(0xFF9DB2FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.radiusMd)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : (isDark ? p.textTertiary : Colors.white)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.primary : p.surfaceAlt),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.primary : p.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.primary : Colors.transparent),
        side: BorderSide(color: p.textTertiary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.primary : p.textTertiary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceAlt,
        circularTrackColor: p.surfaceAlt,
        linearMinHeight: 6,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      tabBarTheme: TabBarThemeData(
        labelColor: p.textPrimary,
        unselectedLabelColor: p.textTertiary,
        labelStyle: text.labelLarge?.copyWith(fontSize: 13.5),
        unselectedLabelStyle: text.labelLarge?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(AppSpace.radiusSm),
          boxShadow: [BoxShadow(color: p.shadow, blurRadius: 6, offset: const Offset(0, 1))],
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          foregroundColor: p.textSecondary,
          selectedBackgroundColor: p.primarySoft,
          selectedForegroundColor: p.onPrimarySoft,
          side: BorderSide(color: p.border),
          textStyle: text.labelMedium,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpace.radiusSm)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpace.radiusMd),
          side: BorderSide(color: p.border),
        ),
        textStyle: text.titleSmall,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? p.surfaceAlt : p.textPrimary,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: isDark ? p.textPrimary : Colors.white),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: p.textSecondary,
        collapsedIconColor: p.textTertiary,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

// Custom Page Route with Animations
class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );
}

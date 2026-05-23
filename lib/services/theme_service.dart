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

// Beautiful Color Palette - Deep Navy & Royal Purple/Indigo Theme
class CrimiColors {
  // Primary Navy Blues
  static const Color deepNavy = Color(0xFF0F0F23);
  static const Color navyBlue = Color(0xFF1A1A3E);
  static const Color darkNavy = Color(0xFF080816);
  
  // Royal Purple/Indigo Accents
  static const Color purple = Color(0xFF8B5CF6);
  static const Color lightPurple = Color(0xFFA78BFA);
  static const Color darkPurple = Color(0xFF7C3AED);
  
  // Keep gold reference for backwards compatibility
  static const Color gold = Color(0xFF8B5CF6);
  static const Color emerald = Color(0xFF8B5CF6);
  
  // Gradients
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0F0F23), Color(0xFF1A1A3E), Color(0xFF0F0F23)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  static const LinearGradient navyGradient = LinearGradient(
    colors: [Color(0xFF1A1A3E), Color(0xFF0F0F23)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppColors {
  // Primary Colors - Deep Navy Blue
  static const Color primary = Color(0xFF0F0F23);        // Deep Navy
  static const Color primaryLight = Color(0xFF1A1A3E);   // Lighter Navy
  static const Color primaryDark = Color(0xFF080816);    // Darker Navy
  
  // Accent Colors - Royal Purple/Indigo
  static const Color accent = Color(0xFF8B5CF6);         // Purple
  static const Color accentLight = Color(0xFFA78BFA);    // Light Purple
  static const Color accentDark = Color(0xFF7C3AED);     // Dark Purple
  
  // Secondary Colors
  static const Color secondary = Color(0xFF415A77);      // Steel Blue
  static const Color tertiary = Color(0xFF778DA9);       // Light Steel
  
  // Semantic Colors
  static const Color success = Color(0xFF00C853);        // Green
  static const Color successLight = Color(0xFF69F0AE);   // Light Green
  static const Color error = Color(0xFFFF5252);          // Red
  static const Color errorLight = Color(0xFFFF8A80);     // Light Red
  static const Color warning = Color(0xFFFFB74D);        // Orange
  
  // Neutrals
  static const Color darkBg = Color(0xFF0A0F1A);         // Deep Dark
  static const Color darkCard = Color(0xFF141B2D);       // Dark Card
  static const Color darkSurface = Color(0xFF1E2640);    // Dark Surface
  static const Color lightBg = Color(0xFFF8F9FC);        // Light Background
  static const Color lightCard = Colors.white;
  static const Color lightSurface = Color(0xFFEEF1F8);
  
  // Text Colors
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textLight = Color(0xFFF5F5F5);
  static const Color textMuted = Color(0xFF9E9E9E);
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1B3A5F), Color(0xFF0D1B2A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF141B2D), Color(0xFF0A0F1A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF69F0AE), Color(0xFF00C853)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient errorGradient = LinearGradient(
    colors: [Color(0xFFFF8A80), Color(0xFFFF5252)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // Subject Colors - Unique color for each subject
  static const Map<String, Color> subjectColors = {
    'criminal_jurisprudence': Color(0xFF6366F1), // Indigo
    'law_enforcement': Color(0xFF3B82F6),         // Blue
    'criminalistics': Color(0xFF8B5CF6),          // Purple
    'crime_detection': Color(0xFF14B8A6),         // Teal
    'criminology': Color(0xFFEC4899),             // Pink
    'corrections': Color(0xFFF59E0B),             // Amber
  };
  
  static const Map<String, LinearGradient> subjectGradients = {
    'criminal_jurisprudence': LinearGradient(
      colors: [Color(0xFF818CF8), Color(0xFF6366F1)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    'law_enforcement': LinearGradient(
      colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    'criminalistics': LinearGradient(
      colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    'crime_detection': LinearGradient(
      colors: [Color(0xFF2DD4BF), Color(0xFF14B8A6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    'criminology': LinearGradient(
      colors: [Color(0xFFF472B6), Color(0xFFEC4899)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    'corrections': LinearGradient(
      colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  };
}

class AppTheme {
  static const Map<String, Color> subjectColors = {
    'criminal_jurisprudence': Color(0xFF6366F1),
    'law_enforcement': Color(0xFF3B82F6),
    'criminalistics': Color(0xFF8B5CF6),
    'crime_detection': Color(0xFF14B8A6),
    'criminology': Color(0xFFEC4899),
    'corrections': Color(0xFFF59E0B),
  };
  
  static const Map<String, IconData> subjectIcons = {
    'criminal_jurisprudence': Icons.gavel_rounded,
    'law_enforcement': Icons.local_police_rounded,
    'criminalistics': Icons.fingerprint_rounded,
    'crime_detection': Icons.search_rounded,
    'criminology': Icons.psychology_rounded,
    'corrections': Icons.account_balance_rounded,
  };

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Poppins',
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.textDark,
      surface: AppColors.lightCard,
      onSurface: AppColors.textDark,
      error: AppColors.error,
      tertiary: AppColors.tertiary,
    ),
    scaffoldBackgroundColor: AppColors.lightBg,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.textDark,
      titleTextStyle: TextStyle(
        color: AppColors.textDark,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: AppColors.lightCard,
      shadowColor: AppColors.primary.withValues(alpha: 0.1),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.primary, width: 2),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.7)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.lightCard,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.textDark,
      elevation: 4,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightSurface,
      selectedColor: AppColors.primary,
      labelStyle: const TextStyle(color: AppColors.textDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.lightSurface,
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.textMuted.withValues(alpha: 0.2),
      thickness: 1,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Poppins',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.textDark,
      surface: AppColors.darkCard,
      onSurface: AppColors.textLight,
      error: AppColors.error,
      tertiary: AppColors.tertiary,
    ),
    scaffoldBackgroundColor: AppColors.darkBg,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.textLight,
      titleTextStyle: TextStyle(
        color: AppColors.textLight,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: AppColors.darkCard,
      shadowColor: Colors.black26,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textDark,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.accent, width: 2),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.7)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkCard,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.textDark,
      elevation: 4,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedColor: AppColors.accent,
      labelStyle: const TextStyle(color: AppColors.textLight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.darkSurface,
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.textMuted.withValues(alpha: 0.2),
      thickness: 1,
    ),
  );
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



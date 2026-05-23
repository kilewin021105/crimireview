import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/storage_service.dart';
import 'services/adaptive_learning_service.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'services/feedback_service.dart';
import 'services/adaptive_ml_service.dart';
import 'services/supabase_service.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Flutter error: ${details.exception}');
    };
    
    try {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
        ),
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint('System chrome failed: $e');
    }
    
    final storageService = StorageService();
    try {
      await storageService.init();
    } catch (e) {
      debugPrint('Storage init failed: $e');
    }
    
    try {
      await SupabaseService.initialize();
    } catch (e) {
      debugPrint('Supabase init failed: $e');
    }
    
    try {
      await NotificationService.instance.initialize();
      await NotificationService.instance.setupScheduledNotifications();
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
    
    try {
      await FeedbackService.instance.initialize();
    } catch (e) {
      debugPrint('Feedback init failed: $e');
    }
    
    try {
      await AdaptiveMLService.instance.initialize();
    } catch (e) {
      debugPrint('ML init failed: $e');
    }
    
    runApp(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storageService),
          ChangeNotifierProvider(
            create: (_) => AdaptiveLearningService(storageService),
          ),
          ChangeNotifierProvider(
            create: (_) => ThemeService(),
          ),
        ],
        child: const CrimiReviewApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack: $stack');
  });
}

class CrimiReviewApp extends StatelessWidget {
  const CrimiReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        ThemeData lightTheme;
        ThemeData darkTheme;
        
        try {
          lightTheme = AppTheme.lightTheme.copyWith(
            textTheme: GoogleFonts.poppinsTextTheme().apply(
              bodyColor: AppColors.textDark,
              displayColor: AppColors.textDark,
            ),
          );
          darkTheme = AppTheme.darkTheme.copyWith(
            textTheme: GoogleFonts.poppinsTextTheme().apply(
              bodyColor: AppColors.textLight,
              displayColor: AppColors.textLight,
            ),
          );
        } catch (e) {
          debugPrint('GoogleFonts failed: $e');
          lightTheme = AppTheme.lightTheme;
          darkTheme = AppTheme.darkTheme;
        }
        
        return MaterialApp(
          title: 'CrimiReview',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeService.themeMode,
          home: const SplashScreen(),
          builder: (context, child) {
            ErrorWidget.builder = (FlutterErrorDetails details) {
              return Material(
                child: Container(
                  color: const Color(0xFF0F0F23),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Something went wrong',
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        details.exception.toString(),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            };
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}

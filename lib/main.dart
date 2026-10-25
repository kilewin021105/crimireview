import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/adaptive_learning_service.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'services/feedback_service.dart';
import 'services/adaptive_ml_service.dart';
import 'services/supabase_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_sync_service.dart';
import 'services/admin_service.dart';
import 'services/mastery_service.dart';
import 'services/question_selection_service.dart';
import 'models/tos.dart';
import 'screens/splash_screen.dart';
import 'utils/responsive.dart';
//import 'screens/home_screen.dart';

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
      // Whether the signed-in user is an admin (panel note 7), kept in sync
      // with sign-in/sign-out. Starts from the role last confirmed on this
      // phone and checks the server in the background, so start-up never
      // waits on the network (the splash screen waits a few seconds at most).
      await AdminService.instance.init();
    } catch (e) {
      debugPrint('AdminService init failed: $e');
    }

    try {
      // The PRC Tables of Specifications (a local asset): the admin screens,
      // the study notes and the topic mastery all read it.
      await TosCatalog.load();
    } catch (e) {
      debugPrint('TOS not loaded: $e');
    }

    try {
      // Loads the Bayesian Knowledge Tracing model (panel notes 2 & 4) and
      // the unseen-first question-selection ledger (panel note 3) so both
      // are warm before the first quiz question renders, instead of paying
      // their (fast, local) init cost inline on the first answer.
      await MasteryService.instance.init();
      await QuestionSelectionService.instance.init();
    } catch (e) {
      debugPrint('Adaptive learning init failed: $e');
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

    // Initialize connectivity monitoring and offline sync
    try {
      ConnectivityService.instance.startMonitoring();
      await OfflineSyncService.instance.init();
    } catch (e) {
      debugPrint('Connectivity/Sync init failed: $e');
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
          ChangeNotifierProvider.value(
            value: ConnectivityService.instance,
          ),
          ChangeNotifierProvider.value(
            value: OfflineSyncService.instance,
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
        return MaterialApp(
          title: 'CrimiReview',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeService.themeMode,
          home: const SplashScreen(),
          builder: (context, child) {
            ErrorWidget.builder = (FlutterErrorDetails details) {
              const palette = AppPalette.dark;
              return Material(
                color: palette.background,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: palette.danger, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        'Something went wrong',
                        style: TextStyle(
                          fontFamily: kAppFontFamily,
                          color: palette.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        details.exception.toString(),
                        style: TextStyle(
                          fontFamily: kAppFontFamily,
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            };
            // Status-bar icons follow the theme: dark icons on the light
            // background, light icons in dark mode.
            final dark = Theme.of(context).brightness == Brightness.dark;
            final overlay = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            );
            // Follows the phone's text-size setting up to 130%, then stops,
            // so very large system text (up to 200% on newer Android) can't
            // push buttons and cards apart. Every screen is checked at 130%
            // on small and normal phones (screenshot sweep).
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: media.textScaler.clamp(maxScaleFactor: kMaxTextScale),
              ),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlay,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

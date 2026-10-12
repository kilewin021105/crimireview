// Renders the screens a student sees before logging in at real small-phone
// sizes and fails on any layout overflow ("RenderFlex overflowed by N
// pixels"), the bug that shows up as yellow-and-black stripes on a phone.
//
// Run: flutter test test/responsive_screens_test.dart
//
// Text is drawn with the real Poppins font (test/fonts, SIL Open Font
// License) under the family names google_fonts uses, because Flutter's
// default test font draws every letter as a full square and would report
// overflows that never happen on a real phone.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crimireview/screens/auth_screen.dart';
import 'package:crimireview/screens/change_password_screen.dart';
import 'package:crimireview/screens/email_verification_screen.dart';
import 'package:crimireview/screens/forgot_password_screen.dart';
import 'package:crimireview/screens/onboarding_screen.dart';
import 'package:crimireview/services/theme_service.dart';

/// Phone widths in logical pixels: a small older phone, a common Android
/// size, and a large Android phone. Heights are the matching screens.
const sizes = <String, Size>{
  '320x568 (small)': Size(320, 568),
  '360x740 (common Android)': Size(360, 740),
  '412x915 (large Android)': Size(412, 915),
};

Future<List<String>> _overflowsFor(WidgetTester tester, Widget screen, Size size,
    {bool dark = false, Future<void> Function(WidgetTester)? act}) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first);
    }
    // Everything else (fonts that can't download in tests, services that
    // aren't connected) is irrelevant to layout and is ignored here.
  };
  try {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    // Same theme construction as CrimiReviewApp in lib/main.dart.
    final theme = dark
        ? AppTheme.darkTheme.copyWith(
            textTheme: GoogleFonts.poppinsTextTheme().apply(
                bodyColor: AppColors.textLight, displayColor: AppColors.textLight))
        : AppTheme.lightTheme.copyWith(
            textTheme: GoogleFonts.poppinsTextTheme().apply(
                bodyColor: AppColors.textDark, displayColor: AppColors.textDark));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeService(),
        child: MaterialApp(theme: theme, home: screen),
      ),
    );
    // Let google_fonts' failed downloads settle before measuring.
    await tester.pump();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeService(),
        child: MaterialApp(theme: theme, home: screen),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    if (act != null) {
      await act(tester);
      await tester.pump(const Duration(milliseconds: 500));
    }
  } finally {
    FlutterError.onError = previous;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
  return overflows;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // google_fonts names each weight as its own family: Poppins_regular,
    // Poppins_500 ... Poppins_900. 'Roboto' covers widgets with no font set.
    const files = {
      'Poppins_regular': 'Regular',
      'Poppins_500': 'Medium',
      'Poppins_600': 'SemiBold',
      'Poppins_700': 'Bold',
      'Poppins_800': 'ExtraBold',
      'Poppins_900': 'Black',
      'Roboto': 'Regular',
    };
    for (final entry in files.entries) {
      final bytes = File('test/fonts/Poppins-${entry.value}.ttf').readAsBytesSync();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final screens = <String, Widget Function()>{
    'Onboarding': () => const OnboardingScreen(),
    'Log in': () => const AuthScreen(),
    'Forgot password': () => const ForgotPasswordScreen(),
    'Change password': () => const ChangePasswordScreen(),
    'Email verification': () => const EmailVerificationScreen(
          email: 'student.with.a.long.email.address@example.com',
          password: 'Password1',
          displayName: 'Juan Dela Cruz',
        ),
  };

  for (final entry in screens.entries) {
    for (final size in sizes.entries) {
      testWidgets('${entry.key} fits at ${size.key}', (tester) async {
        final overflows = await _overflowsFor(tester, entry.value(), size.value);
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  }

  for (final size in sizes.entries) {
    testWidgets('Sign up form fits at ${size.key}', (tester) async {
      final overflows = await _overflowsFor(
        tester,
        const AuthScreen(),
        size.value,
        act: (tester) async {
          final toggle = find.textContaining('Sign Up');
          if (toggle.evaluate().isNotEmpty) {
            await tester.tap(toggle.last, warnIfMissed: false);
          }
        },
      );
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });
  }
}

// The Google and Facebook icons under the email sign-in form.
//
// Run: flutter test test/social_sign_in_icons_test.dart
//
// Supabase isn't connected in tests, so these check what the student sees
// for each saved "which providers are switched on" answer; tapping an icon
// (which opens the browser) is not exercised here.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crimireview/screens/social_sign_in_icons.dart';
import 'package:crimireview/services/social_auth_service.dart';
import 'package:crimireview/services/theme_service.dart';
import 'package:crimireview/widgets/brand_logos.dart';

Future<void> _show(
  WidgetTester tester, {
  List<String> enabled = const [],
  bool formBusy = false,
  bool completing = false,
}) async {
  SharedPreferences.setMockInitialValues({SocialAuthService.enabledCacheKey: enabled});
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SocialSignInIcons(enabled: !formBusy, completing: completing),
      ),
    ),
  );
  // Reading the saved answer is asynchronous.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows nothing while neither provider is switched on', (tester) async {
    await _show(tester);
    expect(find.text('or continue with'), findsNothing);
    expect(find.byType(GoogleLogo), findsNothing);
    expect(find.byType(FacebookLogo), findsNothing);
  });

  testWidgets('shows a Google and a Facebook icon when both are on', (tester) async {
    await _show(tester, enabled: ['google', 'facebook']);
    expect(find.text('or continue with'), findsOneWidget);
    expect(find.byType(GoogleLogo), findsOneWidget);
    expect(find.byType(FacebookLogo), findsOneWidget);
    // Icon-only buttons still have names for screen readers.
    expect(find.bySemanticsLabel('Continue with Google'), findsOneWidget);
    expect(find.bySemanticsLabel('Continue with Facebook'), findsOneWidget);
    expect(
      find.text('Your password stays with Google or Facebook. CrimiReview only receives '
          'your name, email address and profile photo.'),
      findsOneWidget,
    );
  });

  testWidgets('shows only the provider that is on', (tester) async {
    await _show(tester, enabled: ['google']);
    expect(find.byType(GoogleLogo), findsOneWidget);
    expect(find.byType(FacebookLogo), findsNothing);
    expect(find.textContaining('Your password stays with Google.'), findsOneWidget);
  });

  testWidgets('icons cannot be tapped while the email form signs in', (tester) async {
    await _show(tester, enabled: ['google', 'facebook'], formBusy: true);
    final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
    expect(inkWells, hasLength(2));
    expect(inkWells.every((inkWell) => inkWell.onTap == null), isTrue);
  });

  testWidgets('says the sign-in is being finished', (tester) async {
    await _show(tester, enabled: ['google'], completing: true);
    expect(find.text('Signed in. Getting your progress ready...'), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('hidden on Windows, which has no way back from the browser', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _show(tester, enabled: ['google', 'facebook']);
      expect(find.byType(GoogleLogo), findsNothing);
      expect(find.text('or continue with'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

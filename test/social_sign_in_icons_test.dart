// The Google icon under the email sign-in form (Facebook was removed).
//
// Run: flutter test test/social_sign_in_icons_test.dart
//
// Supabase isn't connected in tests, so these check what the student sees
// for each saved "which providers are switched on" answer, and what
// tapping a provider that isn't switched on does. Opening the browser for
// a provider that is on is not exercised here.

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
  testWidgets('shows the Google icon, and only Google, even before it is switched on', (tester) async {
    await _show(tester);
    expect(find.text('or continue with'), findsOneWidget);
    expect(find.byType(GoogleLogo), findsOneWidget);
    // An icon-only button still has a name for screen readers.
    expect(find.bySemanticsLabel('Continue with Google'), findsOneWidget);
    expect(
      find.text('Your password stays with Google. CrimiReview only receives '
          'your name, email address and profile photo.'),
      findsOneWidget,
    );
    // Facebook sign-in was removed.
    expect(find.bySemanticsLabel('Continue with Facebook'), findsNothing);
    expect(find.textContaining('Facebook'), findsNothing);
  });

  testWidgets('tapping Google before it is switched on says so', (tester) async {
    // A phone updated from an older version may still have Facebook in its
    // saved check; it is ignored.
    await _show(tester, enabled: ['facebook']);
    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Continue with Google'));
    await tester.pumpAndSettle();
    expect(
      find.text("Google sign-in isn't available yet. Please sign in with your email."),
      findsOneWidget,
    );
    // The icon works again for the next try.
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNotNull);
  });

  testWidgets('the icon cannot be tapped while the email form signs in', (tester) async {
    await _show(tester, enabled: ['google'], formBusy: true);
    final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
    expect(inkWells, hasLength(1));
    expect(inkWells.single.onTap, isNull);
  });

  testWidgets('says the sign-in is being finished', (tester) async {
    await _show(tester, enabled: ['google'], completing: true);
    expect(find.text('Signed in. Getting your progress ready...'), findsOneWidget);
    final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
    expect(inkWells.every((inkWell) => inkWell.onTap == null), isTrue);
  });

  testWidgets('hidden on Windows, which has no way back from the browser', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _show(tester, enabled: ['google']);
      expect(find.byType(GoogleLogo), findsNothing);
      expect(find.text('or continue with'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

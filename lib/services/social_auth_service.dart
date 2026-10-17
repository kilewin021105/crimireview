import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_messages.dart';
import 'connectivity_service.dart';
import 'supabase_service.dart';

/// The social sign-in options: the icon under the email form. Only Google
/// (Facebook sign-in was removed on 2026-10-17).
enum SocialProvider {
  google('google', 'Google');

  const SocialProvider(this.id, this.label);

  /// Supabase's name for the provider (`app_metadata.provider`).
  final String id;
  final String label;

  OAuthProvider get oauth => switch (this) {
        SocialProvider.google => OAuthProvider.google,
      };
}

/// "Continue with Google".
///
/// How it stays safe:
///   * The password is never seen by this app. The student signs in on
///     Google's own page in the phone's browser, and the browser hands
///     back a one-time code.
///   * PKCE (Supabase's default flow): before opening the browser the app
///     stores a secret "verifier" on the phone. The one-time code is
///     useless without it, so another app that catches the code on its
///     way back can't sign in with it.
///   * Supabase joins a Google login to an existing account only when
///     both sides have a verified email, so a student who already signed
///     up with email + password keeps the same account and the same
///     progress instead of getting a second, empty one.
///   * The database (supabase_social_login.sql) fills in the name and
///     photo; the student's role is always "student" and can't be set
///     from a Google profile.
///
/// The student's choice comes back through Supabase's auth listener, not
/// as the return value here -- see `SignInCompletion` (and `SplashScreen`,
/// when Android restarted the app while the browser was open).
class SocialAuthService {
  SocialAuthService._();
  static final SocialAuthService instance = SocialAuthService._();

  /// Where Supabase sends the browser back to. It must be listed in the
  /// Supabase dashboard (Authentication -> URL Configuration -> Redirect
  /// URLs) and match the intent filter in AndroidManifest.xml and the URL
  /// type in ios/Runner/Info.plist.
  static const String redirectUrl = 'com.crimireview.crimireview://login-callback';

  /// Where the last check of switched-on providers is saved on the phone
  /// (tests use it too).
  static const String enabledCacheKey = 'social_providers_enabled';

  /// Browser sign-in needs a way back into the app: Android, iOS and the
  /// web have one; the desktop builds don't, so they hide the icons.
  static bool get isSupportedPlatform =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Providers that were switched on in Supabase the last time we checked.
  /// Read from this phone so a tap can be answered at once; [refreshEnabled]
  /// corrects it from the server.
  Future<Set<SocialProvider>> cachedEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(enabledCacheKey) ?? const [];
    return SocialProvider.values.where((p) => saved.contains(p.id)).toSet();
  }

  /// Asks Supabase which sign-in providers are switched on (the public
  /// `/auth/v1/settings` endpoint). A provider that isn't set up yet would
  /// open a browser page with a raw error, so the icons check this before
  /// opening the browser. Returns null when the check itself fails
  /// (offline), so the caller keeps what it already knows.
  Future<Set<SocialProvider>?> refreshEnabled() async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await http.get(
        Uri.parse('${SupabaseService.projectUrl}/auth/v1/settings'),
        headers: {'apikey': SupabaseService.publicKey},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final external = (jsonDecode(response.body) as Map<String, dynamic>)['external'];
      if (external is! Map) return null;
      final enabled = SocialProvider.values.where((p) => external[p.id] == true).toSet();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(enabledCacheKey, [for (final p in enabled) p.id]);
      return enabled;
    } catch (e) {
      debugPrint('Sign-in provider check skipped: $e');
      return null;
    }
  }

  /// Opens the provider's sign-in page. Returns once the browser is open;
  /// throws if it couldn't be opened.
  Future<void> start(SocialProvider provider) async {
    // Offline, the browser would only show its own "no internet" page.
    if (!await ConnectivityService.instance.checkConnectivity()) {
      throw Exception("You're offline. Connect to the internet to sign in with ${provider.label}.");
    }
    final client = SupabaseService.instance.client;
    final opened = await client.auth.signInWithOAuth(
      provider.oauth,
      // On the web, come back to the address the app is running on (left
      // empty, Supabase would send the student to its Site URL instead);
      // on phones, our app link.
      redirectTo: kIsWeb ? Uri.base.origin : redirectUrl,
      // Google blocks sign-in inside embedded web views, so mobile uses
      // the real browser app.
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      // Always show Google's account chooser, so a student on a shared or
      // family phone picks their own account instead of being signed in
      // silently as whoever used Google last.
      queryParams: provider == SocialProvider.google ? const {'prompt': 'select_account'} : null,
    );
    if (!opened) {
      throw Exception("Couldn't open the ${provider.label} sign-in page. Please try again.");
    }
  }

  /// Turns what Supabase reports back after the browser into a sentence
  /// for the student.
  String describeError(Object error, SocialProvider? provider) {
    final name = provider?.label ?? 'social';
    final raw = (error is AuthException ? '${error.code} ${error.message}' : '$error').toLowerCase();
    if (raw.contains('access_denied') || raw.contains('cancel')) {
      return '$name sign-in was cancelled.';
    }
    if (raw.contains('email') && raw.contains('external provider')) {
      return "$name didn't share your email address, so we couldn't create your account. "
          'Allow email access, or sign in with your email instead.';
    }
    if (raw.contains('code verifier') || raw.contains('flow state') || raw.contains('expired')) {
      return 'That sign-in link expired. Please try again.';
    }
    if (raw.contains('database error')) {
      return "We couldn't set up your account right now. Please try again in a few minutes.";
    }
    // Offline / slow connection / an Exception('...') we threw ourselves.
    return friendlyError(error, fallback: '$name sign-in failed. Please try again.');
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'supabase_service.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._();
  static ConnectivityService get instance => _instance;

  ConnectivityService._();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Timer? _checkTimer;

  /// What "online" means for this app: our own Supabase backend is
  /// reachable, not merely some website. Probing the backend host also
  /// avoids false "online" on networks that allow Google but block others.
  static final Uri _probe = Uri.parse('${SupabaseService.projectUrl}/auth/v1/health');
  static const Duration _timeout = Duration(seconds: 5);

  void startMonitoring() {
    checkConnectivity();
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkConnectivity();
    });
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<bool> checkConnectivity() async {
    bool online;
    try {
      if (kIsWeb) {
        // Browsers can't do DNS lookups (InternetAddress is unsupported on
        // the web), so make a real request instead. Any HTTP response --
        // even an error status -- proves the server is reachable.
        await http.get(_probe).timeout(_timeout);
        online = true;
      } else {
        final result = await InternetAddress.lookup(_probe.host).timeout(_timeout);
        online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      }
    } catch (_) {
      // No network, DNS failure, timeout, or the request was blocked.
      online = false;
    }

    if (_isOnline != online) {
      _isOnline = online;
      notifyListeners();
    }
    return online;
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

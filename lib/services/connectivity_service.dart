import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._();
  static ConnectivityService get instance => _instance;
  
  ConnectivityService._();
  
  bool _isOnline = true;
  bool get isOnline => _isOnline;
  
  Timer? _checkTimer;
  
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
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      
      if (_isOnline != online) {
        _isOnline = online;
        notifyListeners();
      }
      return online;
    } on SocketException catch (_) {
      if (_isOnline) {
        _isOnline = false;
        notifyListeners();
      }
      return false;
    } on TimeoutException catch (_) {
      if (_isOnline) {
        _isOnline = false;
        notifyListeners();
      }
      return false;
    } catch (_) {
      return _isOnline;
    }
  }
  
  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

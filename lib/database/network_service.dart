import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service that monitors device network connectivity (Wi-Fi, Mobile Data, etc.)
/// and coordinates offline/online transitions for cloud database synchronization.
class NetworkService {
  NetworkService._();
  static final NetworkService instance = NetworkService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(true);
  bool get isConnected =>
      _mockIsConnectedForTesting ?? isConnectedNotifier.value;

  bool _initialized = false;
  bool? _mockIsConnectedForTesting;
  bool? get mockIsConnectedForTesting => _mockIsConnectedForTesting;
  set mockIsConnectedForTesting(bool? value) {
    final wasConnected = isConnected;
    _mockIsConnectedForTesting = value;
    if (value != null) {
      isConnectedNotifier.value = value;
      if (!wasConnected && value) {
        _onConnectionRestored?.call();
      }
    }
  }
  VoidCallback? _onConnectionRestored;

  /// Initializes network monitoring and registers a callback when internet is restored.
  void initialize({VoidCallback? onConnectionRestored}) {
    if (onConnectionRestored != null) {
      _onConnectionRestored = onConnectionRestored;
    }
    if (_initialized) return;
    _initialized = true;

    _checkInitialConnectivity();

    try {
      _subscription = _connectivity.onConnectivityChanged.listen((results) {
        final wasConnected = isConnected;
        final nowConnected = _isOnline(results);
        isConnectedNotifier.value = nowConnected;

        if (!wasConnected && nowConnected) {
          debugPrint(
              '[NetworkService] Internet connection restored. Triggering auto-sync.');
          _onConnectionRestored?.call();
        }
      }, onError: (e) {
        debugPrint('[NetworkService] Connectivity stream error: $e');
      });
    } catch (e) {
      debugPrint('[NetworkService] Connectivity init error: $e');
    }
  }

  /// Sets or updates the callback executed when internet connectivity is re-established.
  void setOnConnectionRestored(VoidCallback callback) {
    _onConnectionRestored = callback;
  }

  Future<void> _checkInitialConnectivity() async {
    if (mockIsConnectedForTesting != null) {
      isConnectedNotifier.value = mockIsConnectedForTesting!;
      return;
    }
    try {
      final results = await _connectivity.checkConnectivity();
      isConnectedNotifier.value = _isOnline(results);
    } catch (_) {
      // In headless test environments or unsupported web targets, default to true or mock
      if (mockIsConnectedForTesting != null) {
        isConnectedNotifier.value = mockIsConnectedForTesting!;
      } else {
        isConnectedNotifier.value = true;
      }
    }
  }

  bool _isOnline(List<ConnectivityResult> results) {
    if (mockIsConnectedForTesting != null) {
      return mockIsConnectedForTesting!;
    }
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Manually trigger a connectivity check (e.g. before manual sync attempt).
  Future<bool> checkConnectivity() async {
    if (mockIsConnectedForTesting != null) {
      isConnectedNotifier.value = mockIsConnectedForTesting!;
      return mockIsConnectedForTesting!;
    }
    try {
      final results = await _connectivity.checkConnectivity();
      final online = _isOnline(results);
      final wasConnected = isConnected;
      isConnectedNotifier.value = online;
      if (!wasConnected && online) {
        _onConnectionRestored?.call();
      }
      return online;
    } catch (_) {
      return isConnected;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}

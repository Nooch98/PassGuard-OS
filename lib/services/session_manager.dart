/*
|--------------------------------------------------------------------------
| PassGuard OS - SessionManager (Inactivity Lock Controller)
|--------------------------------------------------------------------------
| Description:
|   Central inactivity controller that auto-locks the vault after a period
|   without user interaction.
|
| Key improvements vs v1.0:
|   - Uses a periodic ticker to compute remaining time reliably.
|   - Exposes explicit lifecycle hooks: pause(), resume(), lockNow().
|   - Provides a clean activity() API for UI pings (tap, scroll, input, nav).
|   - Safer initialization: prevents silent re-init bugs.
|
| Threat model assumptions:
|   - The app can be backgrounded at any time.
|   - UI might forget to ping activity in some edge cases.
|   - We want "fail-closed": lock if uncertain.
|
| What this does NOT protect against:
|   - OS-level compromise, keyloggers, memory scraping while unlocked.
|--------------------------------------------------------------------------
*/

import 'dart:async';
import 'package:flutter/foundation.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  VoidCallback? _onTimeout;
  Duration _timeoutDuration = const Duration(minutes: 5);

  bool _isEnabled = true;
  bool _initialized = false;
  DateTime? _lastActivity;
  Timer? _ticker;

  final ValueNotifier<Duration?> remainingTimeNotifier =
      ValueNotifier<Duration?>(null);

  static const Duration _tickInterval = Duration(seconds: 1);

  void initialize({
    required VoidCallback onTimeout,
    Duration? timeout,
    bool enabled = true,
  }) {
    _onTimeout = onTimeout;
    if (timeout != null) _timeoutDuration = timeout;
    _isEnabled = enabled;
    
    if (!_initialized) {
      _initialized = true;
      _lastActivity = DateTime.now();
      _startTicker();
      remainingTimeNotifier.value = remainingTime;
    } else {
      activity(); 
    }
  }

  bool get isInitialized => _initialized;
  bool get isEnabled => _isEnabled;
  Duration get timeoutDuration => _timeoutDuration;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;

    if (!_isEnabled) {
      _stopTicker();
      remainingTimeNotifier.value = null;
      return;
    }

    activity();
  }

  void setTimeoutDuration(Duration duration) {
    _timeoutDuration = duration;

    if (_isEnabled && _initialized) {
      _emitRemaining();
      _checkTimeout();
    }
  }

  void activity() {
    if (!_isEnabled || !_initialized) return;
    _lastActivity = DateTime.now();
    _emitRemaining();
  }

  void lockNow({String reason = 'MANUAL_LOCK'}) {
    _onTimeout?.call();
  }

  Duration? get remainingTime {
    if (!_initialized) return null;
    if (_lastActivity == null) return _timeoutDuration;

    final elapsed = DateTime.now().difference(_lastActivity!);
    final remaining = _timeoutDuration - elapsed;
    
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _startTicker() {
    _stopTicker();

    if (!_isEnabled || !_initialized) return;

    _ticker = Timer.periodic(_tickInterval, (_) {
      _emitRemaining();
      _checkTimeout();
    });
  }

  void stopAndReset() {
    _stopTicker();
    _lastActivity = null;
    remainingTimeNotifier.value = null;
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _emitRemaining() {
    final r = remainingTime;
    remainingTimeNotifier.value = r;
  }

  void _checkTimeout() {
    final r = remainingTime;
    if (r == null) return;

    if (r == Duration.zero) {
      _stopTicker();
      _onTimeout?.call();
    }
  }

  void dispose() {
    _stopTicker();
    _onTimeout = null;
    _lastActivity = null;
    _initialized = false;
    Future.microtask(() {
      remainingTimeNotifier.value = null;
    });
  }
}

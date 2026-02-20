import 'dart:async';
import 'package:flutter/material.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  Timer? _inactivityTimer;
  DateTime? _lastActivity;
  VoidCallback? _onTimeout;

  Duration _timeoutDuration = const Duration(minutes: 5);
  bool _isEnabled = true;

  void initialize({
    required VoidCallback onTimeout,
    Duration? timeout,
  }) {
    _onTimeout = onTimeout;
    if (timeout != null) _timeoutDuration = timeout;
    resetTimer();
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      _inactivityTimer?.cancel();
    } else {
      resetTimer();
    }
  }

  void setTimeoutDuration(Duration duration) {
    _timeoutDuration = duration;
    if (_isEnabled) resetTimer();
  }

  void resetTimer() {
    if (!_isEnabled) return;
    
    _lastActivity = DateTime.now();
    _inactivityTimer?.cancel();
    
    _inactivityTimer = Timer(_timeoutDuration, () {
      debugPrint('SESSION_TIMEOUT: LOCKING_VAULT');
      _onTimeout?.call();
    });
  }

  void dispose() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _onTimeout = null;
  }

  Duration? get remainingTime {
    if (_lastActivity == null || !_isEnabled) return null;
    
    final elapsed = DateTime.now().difference(_lastActivity!);
    final remaining = _timeoutDuration - elapsed;
    
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

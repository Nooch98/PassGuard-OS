/*
|--------------------------------------------------------------------------
| PassGuard OS - SessionService
|--------------------------------------------------------------------------
| Real cryptographic session state.
| - UI lock != hard lock
| - Keeps masterKeyBytes in RAM only for active session
|--------------------------------------------------------------------------
*/

import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class SessionService {
  static final SessionService instance = SessionService._internal();
  SessionService._internal();

  Uint8List? _masterKeyBytes;
  bool _uiLocked = true;

  final ValueNotifier<bool> sessionActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> uiLockedNotifier = ValueNotifier<bool>(true);

  bool get isSessionActive => _masterKeyBytes != null;
  bool get isUiLocked => _uiLocked;

  Uint8List? get masterKeyBytesCopy {
    if (_masterKeyBytes == null) return null;
    return Uint8List.fromList(_masterKeyBytes!);
  }

  void startSession(Uint8List masterKeyBytes) {
    hardLock();
    _masterKeyBytes = Uint8List.fromList(masterKeyBytes);
    _uiLocked = false;
    sessionActiveNotifier.value = true;
    uiLockedNotifier.value = false;
  }

  void unlockUi() {
    if (_masterKeyBytes == null) return;
    _uiLocked = false;
    uiLockedNotifier.value = false;
  }

  void lockUi() {
    _uiLocked = true;
    uiLockedNotifier.value = true;
  }

  void hardLock() {
    _uiLocked = true;
    uiLockedNotifier.value = true;

    if (_masterKeyBytes != null) {
      for (int i = 0; i < _masterKeyBytes!.length; i++) {
        _masterKeyBytes![i] = 0;
      }
    }

    _masterKeyBytes = null;
    sessionActiveNotifier.value = false;
  }

  void dispose() {
    hardLock();
  }
}

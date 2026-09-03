import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:passguard/services/session_service.dart';

typedef NativeVoidFunc = Void Function();
typedef DartVoidFunc = void Function();

typedef NativeBoolFunc = Bool Function();
typedef DartBoolFunc = bool Function();

class SecurityService {
  late DartVoidFunc _denyMemoryReading;
  late DartBoolFunc _isDebuggerAttached;
  late DartBoolFunc _isFridaPresent;
  late DartBoolFunc _isMemoryScannerPresent;
  late DartBoolFunc _isVirtualMachine;
  Timer? _watchdogTimer;
  bool _isTerminating = false;


  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool get _isSupportedPlatform => Platform.isWindows || Platform.isLinux;
  DynamicLibrary _openNativeLibrary() {
    if (Platform.isWindows || Platform.isLinux) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform for native FFI.');
  }

  void initialize() {
    if (!_isSupportedPlatform) return;
    try {
      final DynamicLibrary nativeLib = _openNativeLibrary();
      _denyMemoryReading = nativeLib
          .lookup<NativeFunction<NativeVoidFunc>>('DenyMemoryReading')
          .asFunction();
      _isDebuggerAttached = nativeLib
          .lookup<NativeFunction<NativeBoolFunc>>('IsDebuggerAttached')
          .asFunction();
      _isFridaPresent = nativeLib
          .lookup<NativeFunction<NativeBoolFunc>>('IsFridaPresent')
          .asFunction();
      _isMemoryScannerPresent = nativeLib
          .lookup<NativeFunction<NativeBoolFunc>>('IsMemoryScannerPresent')
          .asFunction();
      _isVirtualMachine = nativeLib
          .lookup<NativeFunction<NativeBoolFunc>>('IsVirtualMachine')
          .asFunction();
      _denyMemoryReading();
      _startWatchdog();
    } catch (e) {
      debugPrint('[SecurityService] Error linking native C++ functions: $e');
    }
  }

  void _startWatchdog() {
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isTerminating) return;

      final bool debuggerDetected = _isDebuggerAttached();
      final bool fridaDetected = _isFridaPresent();
      final bool scannerDetected = _isMemoryScannerPresent();

      String? threatMessage;

      if (debuggerDetected) {
        threatMessage = 'An active Debugger process has been detected in the system.';
      } else if (fridaDetected) {
        threatMessage = 'A code injection tool (Frida/Hooking framework) has been detected.';
      } else if (scannerDetected) {
        threatMessage = 'A memory scanner or suspicious process (Python/Cheat Engine) was detected.';
      }

      if (threatMessage != null) {
        _isTerminating = true;
        timer.cancel();
        SessionService.instance.hardLock();
        _showSecurityAlertDialogAndExit(threatMessage);
      }
    });
  }

  void _showSecurityAlertDialogAndExit(String reason) {
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) {
      exit(0);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: const Color(0xFF1E1E2C),
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text(
                'Security Alert',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reason,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'For security reasons, the application will terminate immediately.',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                exit(0);
              },
              child: const Text('Understood'),
            ),
          ],
        );
      },
    );
  }

  void dispose() {
    _watchdogTimer?.cancel();
  }
}

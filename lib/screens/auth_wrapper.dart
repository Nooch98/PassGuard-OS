/*
|--------------------------------------------------------------------------
| PassGuard OS - AuthWrapper
|--------------------------------------------------------------------------
| Description:
|   Entry authentication layer for the application.
|
| Responsibilities:
|   - Handle first-time setup
|   - Manage master password verification
|   - Control biometric authentication
|   - Execute panic protocol
|   - Lock and wipe sensitive memory
|
| Security Notes:
|   - Master key stored only in RAM
|   - RAM wiped on lock or dispose
|--------------------------------------------------------------------------
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/auth_service.dart';
import '../services/db_helper.dart';
import '../services/session_manager.dart';
import '../services/session_service.dart';
import 'home_page.dart';
import '../widgets/custom_keyboard.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper>
    with WidgetsBindingObserver {
  bool? isFirstTime;

  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  String _inputBuffer = "";

  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _canCheckBio = false;
  int _failedAttempts = 0;
  bool _isLocked = false;
  bool _bioBusy = false;

  late final SecurityController _security;
  final SessionManager _sessionManager = SessionManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _security = SecurityController();
    _checkStatus();
    _checkBiometrics();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hardLock(reason: 'AUTH_WRAPPER_DISPOSE');
    _passController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_security.shouldLockOnLeave &&
          SessionService.instance.isSessionActive) {
        _lockUiOnly();
      }
    }
  }

  Future<void> _checkStatus() async {
    try {

      bool first = await AuthService.isFirstTime().timeout(
        const Duration(seconds: 3), 
        onTimeout: () => true,
      );
      
      if (mounted) {
        setState(() => isFirstTime = first);
      }
    } catch (e) {
      if (mounted) setState(() => isFirstTime = false);
    }
  }

  Future<void> _checkBiometrics() async {
    try {
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final List<BiometricType> availableBiometrics =
          await _localAuth.getAvailableBiometrics();

      if (mounted) {
        setState(() {
          _canCheckBio =
              isDeviceSupported && (canCheckBiometrics || availableBiometrics.isNotEmpty);
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _canCheckBio = false);
    }
  }

  void _clearUiBuffers() {
    _inputBuffer = '';
    _passController.clear();
    _confirmController.clear();
  }

  void _ensureSessionRunning() {
    if (!_sessionManager.isInitialized) {
      _sessionManager.initialize(
        onTimeout: () {
          _hardLock(reason: 'SESSION_TIMEOUT');
        },
        timeout: const Duration(minutes: 5),
        enabled: true,
      );
    } else {
      _sessionManager.activity();
    }
  }

  void _lockUiOnly() {
    _clearUiBuffers();
    SessionService.instance.lockUi();
    if (mounted) setState(() {});
  }

  void _hardLock({String reason = 'MANUAL_LOCK'}) {
    _clearUiBuffers();
    SessionService.instance.hardLock();
    _sessionManager.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _onSuccessfulUnlock(String plainPassword,
      {bool persistForBio = true}) async {
    if (persistForBio) {
      await AuthService.saveMasterKeyForBio(plainPassword);
    }

    final Uint8List masterKeyBytes =
        Uint8List.fromList(utf8.encode(plainPassword));

    SessionService.instance.startSession(masterKeyBytes);
    _ensureSessionRunning();

    _failedAttempts = 0;
    _clearUiBuffers();

    if (mounted) setState(() {});
  }

  Future<void> _handleBiometricAuth({required bool triggerPanic}) async {
    if (_bioBusy) return;
    _bioBusy = true;

    try {
      final bool deviceSupported = await _localAuth.isDeviceSupported();
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;

      if (!deviceSupported && !canCheckBiometrics) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("BIO_NOT_AVAILABLE")),
        );
        return;
      }

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: triggerPanic
            ? 'SYSTEM_INTEGRITY_CHECK'
            : 'DECRYPTING_VAULT_RESOURCES',
        biometricOnly: true,
      );

      if (!mounted) return;

      if (!didAuthenticate) {
        HapticFeedback.selectionClick();
        return;
      }

      if (triggerPanic) {
        await _executePanicProtocol();
        return;
      }

      final String? savedKey = await AuthService.getMasterKeyForBio();
      if (!mounted) return;

      if (savedKey != null && savedKey.isNotEmpty) {
        await _onSuccessfulUnlock(savedKey, persistForBio: false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("BIO_UNSYNCED: LOGIN_MANUALLY_ONCE")),
        );
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("BIO_ERROR: ${e.code}")),
      );
    } finally {
      _bioBusy = false;
    }
  }

  Future<void> _handleAuth() async {
    if (_isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("TOO_MANY_FAILED_ATTEMPTS: WAIT_30_SECONDS"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String currentInput = _inputBuffer;
    if (currentInput.isEmpty) return;

    bool isPanic = await AuthService.verifyPanicPassword(currentInput);
    if (isPanic) {
      await _executePanicProtocol();
      return;
    }

    if (isFirstTime!) {
      if (_passController.text.isEmpty) {
        if (currentInput.length < 8) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("PASSWORD_TOO_SHORT: MINIMUM_8_CHARACTERS"),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _inputBuffer = "");
          return;
        }

        setState(() {
          _passController.text = currentInput;
          _inputBuffer = "";
        });
        return;
      } else if (_confirmController.text.isEmpty) {
        if (currentInput != _passController.text) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("PASSWORDS_DO_NOT_MATCH"),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _inputBuffer = "";
            _passController.clear();
          });
          return;
        }

        setState(() {
          _confirmController.text = currentInput;
          _inputBuffer = "";
        });
        return;
      } else {
        String mKey = _passController.text;
        await AuthService.setMasterPassword(mKey);
        await AuthService.setPanicPassword(currentInput);

        await _onSuccessfulUnlock(mKey, persistForBio: true);

        setState(() {
          isFirstTime = false;
        });
        return;
      }
    } else {
      bool isValid = await AuthService.verifyPassword(currentInput);
      if (isValid) {
        await _onSuccessfulUnlock(currentInput, persistForBio: true);
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _inputBuffer = "";
          _failedAttempts++;
        });

        if (_failedAttempts >= 5) {
          setState(() => _isLocked = true);
          Future.delayed(const Duration(seconds: 30), () {
            if (mounted) {
              setState(() {
                _isLocked = false;
                _failedAttempts = 0;
              });
            }
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("ACCESS_DENIED ($_failedAttempts/5)"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _executePanicProtocol() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.red, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text(
          '⚠️ PANIC_MODE_ACTIVATED',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will PERMANENTLY DELETE all vault data.\n\nThis action CANNOT be undone.\n\nContinue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('WIPE_ALL_DATA',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.heavyImpact();
      final db = await DBHelper.database;
      await db.delete('accounts');
      await db.delete('recovery_codes');
      await db.delete('file_vault');
      await db.delete('settings');
      await db.delete('identities');
      await db.execute('VACUUM');
      await AuthService.clearAllData();
      await DBHelper.close();

      _hardLock(reason: 'PANIC_PROTOCOL');
      await _checkStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("SYSTEM_ERROR: 0x0004128F - DATA_CORRUPTION_DETECTED"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isFirstTime == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00FBFF))),
      );
    }

    final bool sessionActive = SessionService.instance.isSessionActive;
    final bool uiLocked = SessionService.instance.isUiLocked;

    if (sessionActive && !uiLocked) {
      final masterKey = SessionService.instance.masterKeyBytesCopy!;
      return HomePage(masterKey: masterKey);
    }

    bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    bool settingPanicKey = isFirstTime! &&
        _passController.text.isNotEmpty &&
        _confirmController.text.isNotEmpty;

    String promptText;
    Color promptColor;

    if (isFirstTime!) {
      if (_passController.text.isEmpty) {
        promptText = "> INITIALIZING_VAULT: SET_MASTER_PASSWORD";
        promptColor = const Color(0xFF00FBFF);
      } else if (_confirmController.text.isEmpty) {
        promptText = "> CONFIRM_MASTER_PASSWORD";
        promptColor = const Color(0xFF00FBFF);
      } else {
        promptText = "> CONFIGURING_PANIC_KEY";
        promptColor = const Color(0xFFFF00FF);
      }
    } else {
      promptText = sessionActive ? "> UI_LOCKED" : "> VAULT_LOCKED";
      promptColor = const Color(0xFF00FBFF);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security,
                    size: 60, color: Color(0xFF00FBFF)),
                const SizedBox(height: 10),
                Text(
                  promptText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: promptColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (sessionActive && !isFirstTime!)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Background session still active until timeout',
                      style: TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ),
                if (isFirstTime! && _passController.text.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Minimum 8 characters required',
                      style: TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ),
                const SizedBox(height: 30),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161D),
                    border: Border.all(
                      color: settingPanicKey
                          ? const Color(0xFFFF00FF)
                          : const Color(0xFF00FBFF),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settingPanicKey ? "PANIC_BUFFER:" : "KEY_BUFFER:",
                        style: TextStyle(
                          fontSize: 10,
                          color: settingPanicKey
                              ? Colors.pink
                              : const Color(0xFF00FBFF),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _inputBuffer.isEmpty
                            ? "________________"
                            : "*" * _inputBuffer.length,
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          letterSpacing:
                              _inputBuffer.length > 10 ? 2.0 : 4.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                if (isMobile)
                  CustomKeyboard(
                    onTextInput: (val) => setState(() => _inputBuffer += val),
                    onDelete: () {
                      if (_inputBuffer.isNotEmpty) {
                        setState(() => _inputBuffer =
                            _inputBuffer.substring(0, _inputBuffer.length - 1));
                      }
                    },
                    onSubmit: _handleAuth,
                  )
                else
                  TextField(
                    autofocus: true,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, letterSpacing: 8),
                    decoration: const InputDecoration(
                      hintText: "TYPE_KEY_AND_PRESS_ENTER",
                      hintStyle:
                          TextStyle(color: Colors.white24, fontSize: 12),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF00FBFF)),
                      ),
                    ),
                    onChanged: (val) => setState(() => _inputBuffer = val),
                    onSubmitted: (val) {
                      setState(() => _inputBuffer = val);
                      _handleAuth();
                    },
                  ),
                const SizedBox(height: 20),
                if (isMobile && !isFirstTime! && _canCheckBio) ...[
                  const Divider(color: Colors.white10, height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.fingerprint,
                            color: Color(0xFF00FBFF), size: 50),
                        onPressed: () =>
                            _handleBiometricAuth(triggerPanic: false),
                      ),
                      const SizedBox(width: 50),
                      IconButton(
                        icon: const Icon(Icons.gpp_maybe,
                            color: Colors.white24, size: 50),
                        onPressed: null,
                        onLongPress: () =>
                            _handleBiometricAuth(triggerPanic: true),
                      ),
                    ],
                  ),
                  const Text("BIO_AUTH_READY",
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/auth_service.dart';
import '../services/db_helper.dart';
import 'home_page.dart';
import '../widgets/custom_keyboard.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool? isFirstTime;
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  Uint8List? masterKeyMem;
  String _inputBuffer = "";

  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _canCheckBio = false;
  int _failedAttempts = 0;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    bool canCheck = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
    setState(() => _canCheckBio = canCheck);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockVault();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final security = SecurityController();

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (security.shouldLockOnLeave) {
        _lockVault();
      }
    }
  }

  void _lockVault() {
    if (masterKeyMem != null) {
      for (int i = 0; i < masterKeyMem!.length; i++) {
        masterKeyMem![i] = 0;
      }
      setState(() {
        masterKeyMem = null;
        _inputBuffer = "";
      });
      _passController.clear();
      _confirmController.clear();
      debugPrint("SYSTEM_LOG: RAM_SECURITY_PURGE_COMPLETED");
    }
  }

  _checkStatus() async {
    bool first = await AuthService.isFirstTime();
    setState(() => isFirstTime = first);
  }

  Future<void> _handleBiometricAuth({required bool triggerPanic}) async {
    try {
      bool canCheck = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!canCheck) return;

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: triggerPanic
            ? 'SYSTEM_INTEGRITY_CHECK'
            : 'DECRYPTING_VAULT_RESOURCES',
      );

      if (didAuthenticate) {
        if (triggerPanic) {
          await _executePanicProtocol();
        } else {
          String? savedKey = await AuthService.getMasterKeyForBio();
          if (savedKey != null) {
            setState(() {
              masterKeyMem = Uint8List.fromList(utf8.encode(savedKey));
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("BIO_UNSYNCED: LOGIN_MANUALLY_ONCE"))
            );
          }
        }
      }
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("BIO_ERROR: ${e.code}"))
      );
    }
  }

  void _handleAuth() async {
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

    // Check panic password first
    bool isPanic = await AuthService.verifyPanicPassword(currentInput);
    if (isPanic) {
      await _executePanicProtocol();
      return;
    }

    if (isFirstTime!) {
      // FIRST TIME SETUP
      if (_passController.text.isEmpty) {
        // First password entry
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
      } else if (_confirmController.text.isEmpty) {
        // Confirmation
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
      } else {
        // Panic password setup
        String mKey = _passController.text;
        await AuthService.setMasterPassword(mKey);
        await AuthService.setPanicPassword(currentInput);
        await AuthService.saveMasterKeyForBio(mKey);

        setState(() {
          masterKeyMem = Uint8List.fromList(utf8.encode(mKey));
          isFirstTime = false;
          _inputBuffer = "";
        });
        _passController.clear();
        _confirmController.clear();
      }
    } else {
      // NORMAL LOGIN
      bool isValid = await AuthService.verifyPassword(currentInput);
      if (isValid) {
        await AuthService.saveMasterKeyForBio(currentInput);
        setState(() {
          masterKeyMem = Uint8List.fromList(utf8.encode(currentInput));
          _inputBuffer = "";
          _failedAttempts = 0;
        });
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
            )
        );
      }
    }
  }

  Future<void> _executePanicProtocol() async {
    // Show confirmation dialog
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
            child: const Text('WIPE_ALL_DATA', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.heavyImpact();
      final db = await DBHelper.database;
      await db.delete('accounts');
      await db.delete('recovery_codes');
      await db.delete('encrypted_files');
      await AuthService.clearAllData();
      _lockVault();
      _checkStatus();

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("SYSTEM_ERROR: 0x0004128F - DATA_CORRUPTION_DETECTED"),
            backgroundColor: Colors.red,
          )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isFirstTime == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00FBFF))),
      );
    }
    
    if (masterKeyMem != null) return HomePage(masterKey: masterKeyMem!);

    bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    bool settingConfirmation = isFirstTime! && _passController.text.isNotEmpty && _confirmController.text.isEmpty;
    bool settingPanicKey = isFirstTime! && _passController.text.isNotEmpty && _confirmController.text.isNotEmpty;

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
      promptText = "> VAULT_LOCKED";
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
                const Icon(Icons.security, size: 60, color: Color(0xFF00FBFF)),
                const SizedBox(height: 10),
                Text(
                    promptText,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: promptColor),
                    textAlign: TextAlign.center,
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161D),
                    border: Border.all(
                        color: settingPanicKey ? const Color(0xFFFF00FF) : const Color(0xFF00FBFF),
                        width: 1
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settingPanicKey ? "PANIC_BUFFER:" : "KEY_BUFFER:",
                        style: TextStyle(fontSize: 10, color: settingPanicKey ? Colors.pink : const Color(0xFF00FBFF)),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _inputBuffer.isEmpty ? "________________" : "*" * _inputBuffer.length,
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          letterSpacing: _inputBuffer.length > 10 ? 2.0 : 4.0,
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
                        setState(() => _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1));
                      }
                    },
                    onSubmit: _handleAuth,
                  )
                else
                  TextField(
                    autofocus: true,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, letterSpacing: 8),
                    decoration: const InputDecoration(
                      hintText: "TYPE_KEY_AND_PRESS_ENTER",
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FBFF))),
                    ),
                    onChanged: (val) => setState(() => _inputBuffer = val),
                    onSubmitted: (_) => _handleAuth(),
                  ),

                const SizedBox(height: 20),

                if (isMobile && !isFirstTime! && _canCheckBio) ...[
                  const Divider(color: Colors.white10, height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.fingerprint, color: Color(0xFF00FBFF), size: 50),
                        onPressed: () => _handleBiometricAuth(triggerPanic: false),
                      ),
                      const SizedBox(width: 50),
                      IconButton(
                        icon: Icon(Icons.gpp_maybe, color: Colors.white.withOpacity(0.02), size: 50),
                        onPressed: () => _handleBiometricAuth(triggerPanic: true),
                      ),
                    ],
                  ),
                  const Text("BIO_AUTH_READY", style: TextStyle(fontSize: 10, color: Colors.grey)),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}

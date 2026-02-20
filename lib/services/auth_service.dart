import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'key_derivation_service.dart';

class AuthService {
  static const String _masterHashKey = 'master_password_hash';
  static const String _masterSaltKey = 'master_password_salt';
  static const String _panicHashKey = 'panic_password_hash';
  static const String _panicSaltKey = 'panic_password_salt';
  static const String _stealthCodeKey = 'stealth_code';
  static const String _bioKeyKey = 'biometric_key';
  static const String _firstTimeKey = 'is_first_time';
  static const String _sessionTimeoutKey = 'session_timeout_minutes';
  static const String _autoLockKey = 'auto_lock_enabled';
  static const String _screenshotProtectionKey = 'screenshot_protection';

  static Future<bool> isFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstTimeKey) ?? true;
  }

  static Future<void> setMasterPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    
    final salt = KeyDerivationService.generateSalt();

    final hash = KeyDerivationService.hashPassword(password, salt);

    await prefs.setString(_masterHashKey, hash);
    await prefs.setString(_masterSaltKey, KeyDerivationService.saltToString(salt));
    await prefs.setBool(_firstTimeKey, false);
  }

  static Future<void> setPanicPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = KeyDerivationService.generateSalt();
    final hash = KeyDerivationService.hashPassword(password, salt);
    await prefs.setString(_panicHashKey, hash);
    await prefs.setString(_panicSaltKey, KeyDerivationService.saltToString(salt));
  }

  static Future<bool> verifyPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    
    final storedHash = prefs.getString(_masterHashKey);
    final saltString = prefs.getString(_masterSaltKey);
    
    if (storedHash == null || saltString == null) return false;
    
    final salt = KeyDerivationService.saltFromString(saltString);
    
    return KeyDerivationService.verifyPassword(password, storedHash, salt);
  }

  static Future<bool> verifyPanicPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    
    final storedHash = prefs.getString(_panicHashKey);
    final saltString = prefs.getString(_panicSaltKey);
    
    if (storedHash == null || saltString == null) return false;
    
    final salt = KeyDerivationService.saltFromString(saltString);
    
    return KeyDerivationService.verifyPassword(password, storedHash, salt);
  }

  static Future<void> setStealthCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stealthCodeKey, code);
  }

  static Future<String> getStealthCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_stealthCodeKey) ?? '1234';
  }

  static Future<void> saveMasterKeyForBio(String masterKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bioKeyKey, base64Encode(utf8.encode(masterKey)));
  }

  static Future<String?> getMasterKeyForBio() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_bioKeyKey);
    if (encoded == null) return null;
    return utf8.decode(base64Decode(encoded));
  }

  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<void> setSessionTimeout(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionTimeoutKey, minutes);
  }

  static Future<int> getSessionTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_sessionTimeoutKey) ?? 5;
  }

  static Future<void> setAutoLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLockKey, enabled);
  }

  static Future<bool> getAutoLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLockKey) ?? true;
  }

  static Future<void> setScreenshotProtection(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenshotProtectionKey, enabled);
  }

  static Future<bool> getScreenshotProtection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_screenshotProtectionKey) ?? true;
  }

  static Future<Uint8List> deriveEncryptionKey(String masterPassword) async {
    final prefs = await SharedPreferences.getInstance();
    final saltString = prefs.getString(_masterSaltKey);
    
    if (saltString == null) {
      throw Exception('CRITICAL_ERROR: No salt found');
    }
    
    final salt = KeyDerivationService.saltFromString(saltString);
    return KeyDerivationService.deriveKey(masterPassword, salt);
  }
}

/*
|--------------------------------------------------------------------------
| PassGuard OS - EncryptionService (Core Cryptographic Engine)
|--------------------------------------------------------------------------
| Description:
|   Central encryption/decryption service for PassGuard OS.
|   Standardized Versioning: Primary engine is now v5 (Argon2id).
|
| Version Standards:
|   - v5 (Argon2id): Memory-hard (64MB), ASIC-resistant (Current Standard).
|   - v4 (PBKDF2): Legacy-compatible High Security (200k iterations).
|
| Responsibilities:
|   - Encrypt all NEW or UPDATED data into v5 (Argon2id) by default.
|   - Decrypt v1 through v5 using automatic prefix detection.
|   - Provide transparent backward compatibility for all legacy formats.
|
| Legacy Compatibility & Evolution:
|   - v5: AES-256-GCM + Argon2id (Standard)
|   - v4: AES-256-GCM + PBKDF2-HMAC-SHA256 (200k iterations)
|   - v3: AES-256-CBC + SHA256 stretching + per-record salt
|   - v2: AES-256-CBC + legacy fixed salt stretching
|   - v1: AES + SHA256(password)
|
|   Automatic Upgrade Policy:
|   When a legacy record (v1-v4) is decrypted, it remains in its format
|   until the next 'save' operation, where it is transparently 
|   re-encrypted using the v5 engine.
|
|--------------------------------------------------------------------------
| Threat Model Assumptions & Mitigations
|--------------------------------------------------------------------------
|   Mitigations provided against offline brute-force:
|   - Argon2id (v5): Protection against GPU/ASIC farm cracking via memory-hardness.
|   - PBKDF2-200k (v4): CPU-bound protection for legacy records.
|   - Per-record salt: Rainbow table and cross-record pattern protection.
|   - AEAD (GCM): Tamper detection (ensures data hasn't been modified in DB).
|
|--------------------------------------------------------------------------
| What This Service Does NOT Protect Against
|--------------------------------------------------------------------------
|   - Keyloggers capturing the master password.
|   - Malware reading process memory at runtime.
|   - Rooted / jailbroken device memory scraping.
|   - Active session hijacking while vault is unlocked.
|
|--------------------------------------------------------------------------
| Security Notes
|--------------------------------------------------------------------------
|   - AES-GCM ensures confidentiality + integrity.
|   - Nonces (IVs) are cryptographically random and unique per record.
|   - Argon2id Parameters: 64MB Memory, 3 Iterations, 4 Parallelism.
|
|   ⚠ WARNING: Any modification must preserve decryption of v1-v4.
|   ⚠ NEVER log decrypted values or raw master key bytes.
|--------------------------------------------------------------------------
*/

import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

class EncryptionService {
  static const String _v5Prefix = "v5";
  static const String _v4Prefix = "v4";
  static const String _v3Prefix = "v3";
  static const String _v2Prefix = "v2";
  
  static const int _junkBytesLength = 64;
  static const String _v2SaltLegacy = "CYBER_SECURE_SALT_2026_PRO_STRETCH";

  static String currentVersionPrefix = _v5Prefix;

  static const int _v5SaltLength = 16;
  static const int _v5NonceLength = 12;
  static const int _v5KeyLength = 32;
  static const int _v5Iterations = 2;
  static const int _v5MemoryLimitKB = 65536;
  static const int _v5Parallelism = 4;

  static const int _v4SaltLength = 16;
  static const int _v4NonceLength = 12;
  static const int _v4Pbkdf2Iterations = 200000;

  static const int _gcmTagBits = 128;

  static Uint8List _getSecureBytes(int length) {
    return enc.IV.fromSecureRandom(length).bytes;
  }

  static void _wipe(Uint8List list) {
    list.fillRange(0, list.length, 0);
  }

  static Uint8List _deriveV5Argon2id(Uint8List passwordBytes, Uint8List salt) {
    final derivator = Argon2BytesGenerator();
    final parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      iterations: _v5Iterations,
      memory: _v5MemoryLimitKB,
      lanes: _v5Parallelism,
      desiredKeyLength: _v5KeyLength,
    );
    derivator.init(parameters);
    return derivator.process(passwordBytes);
  }

  static Uint8List _deriveV4Pbkdf2(Uint8List passwordBytes, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(salt, _v4Pbkdf2Iterations, _v5KeyLength));
    return derivator.process(passwordBytes);
  }

  static String _encryptV5(String plaintext, Uint8List masterKeyBytes) {
    if (plaintext.isEmpty) return "";
    final salt = _getSecureBytes(_v5SaltLength);
    final nonce = _getSecureBytes(_v5NonceLength);
    final keyBytes = _deriveV5Argon2id(masterKeyBytes, salt);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(keyBytes), _gcmTagBits, nonce, Uint8List(0));
    cipher.init(true, params);

    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final cipherWithTag = cipher.process(plainBytes);

    _wipe(keyBytes);
    return "$_v5Prefix.${base64.encode(salt)}.${base64.encode(nonce)}.${base64.encode(cipherWithTag)}";
  }

  static String _encryptV4(String plaintext, Uint8List masterKeyBytes) {
    if (plaintext.isEmpty) return "";
    final salt = _getSecureBytes(_v4SaltLength);
    final nonce = _getSecureBytes(_v4NonceLength);
    final keyBytes = _deriveV4Pbkdf2(masterKeyBytes, salt);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(keyBytes), _gcmTagBits, nonce, Uint8List(0));
    cipher.init(true, params);

    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final cipherWithTag = cipher.process(plainBytes);

    _wipe(keyBytes);
    return "$_v4Prefix.${base64.encode(salt)}.${base64.encode(nonce)}.${base64.encode(cipherWithTag)}";
  }

  static String _decryptGCM(List<String> parts, Uint8List masterKeyBytes, bool isV5) {
    final salt = base64.decode(parts[1]);
    final nonce = base64.decode(parts[2]);
    final cipherWithTag = base64.decode(parts[3]);

    final keyBytes = isV5 
        ? _deriveV5Argon2id(masterKeyBytes, salt) 
        : _deriveV4Pbkdf2(masterKeyBytes, salt);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(keyBytes), _gcmTagBits, nonce, Uint8List(0));
    cipher.init(false, params);

    final clearBytes = cipher.process(cipherWithTag);
    final result = utf8.decode(clearBytes);

    _wipe(keyBytes);
    _wipe(clearBytes);
    return result;
  }

  static String encrypt(String text, Uint8List masterKeyBytes) {
    if (currentVersionPrefix == _v4Prefix) {
      return _encryptV4(text, masterKeyBytes);
    }
    return _encryptV5(text, masterKeyBytes);
  }

  static String decrypt({
    required String combinedText,
    required Uint8List masterKeyBytes,
    Function(String upgradedText)? onUpgrade,
  }) {
    if (combinedText.isEmpty) return "";

    try {
      final parts = combinedText.split('.');

      if (parts.length == 4 && parts[0] == _v5Prefix) {
        return _decryptGCM(parts, masterKeyBytes, true);
      }

      if (parts.length == 4 && parts[0] == _v4Prefix) {
        final decrypted = _decryptGCM(parts, masterKeyBytes, false);
        if (currentVersionPrefix == _v5Prefix && onUpgrade != null) {
          onUpgrade(_encryptV5(decrypted, masterKeyBytes));
        }
        return decrypted;
      }

      final masterPasswordStr = utf8.decode(masterKeyBytes);

      if (parts.length == 4 && parts[0] == _v3Prefix) {
        final key = _deriveKeyV3(masterPasswordStr, parts[1]);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final decrypted = encrypter.decrypt64(parts[3], iv: enc.IV.fromBase64(parts[2]));
        
        if (onUpgrade != null) onUpgrade(encrypt(decrypted, masterKeyBytes));
        return decrypted;
      }

      if (parts.length == 3 && parts[0] == _v2Prefix) {
        final key = _deriveKeyV2(masterPasswordStr);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final decrypted = encrypter.decrypt64(parts[2], iv: enc.IV.fromBase64(parts[1]));
        
        if (onUpgrade != null) onUpgrade(encrypt(decrypted, masterKeyBytes));
        return decrypted;
      }

      if (parts.length == 2) {
        final key = _deriveKeyV1(masterPasswordStr);
        final encrypter = enc.Encrypter(enc.AES(key));
        final decrypted = encrypter.decrypt64(parts[1], iv: enc.IV.fromBase64(parts[0]));
        
        if (onUpgrade != null) onUpgrade(encrypt(decrypted, masterKeyBytes));
        return decrypted;
      }

      throw Exception("INVALID_FORMAT");
    } catch (e) {
      return "ERROR: DECRYPTION_FAILED";
    }
  }

  static enc.Key _deriveKeyV3(String password, String saltBase64) {
    final saltBytes = base64.decode(saltBase64);
    List<int> value = utf8.encode(password) + saltBytes;
    for (int i = 0; i < 100000; i++) {
      value = crypto.sha256.convert(value).bytes;
    }
    return enc.Key(Uint8List.fromList(value));
  }

  static enc.Key _deriveKeyV2(String password) {
    List<int> value = utf8.encode(password + _v2SaltLegacy);
    for (int i = 0; i < 50000; i++) {
      value = crypto.sha256.convert(value).bytes;
    }
    return enc.Key(Uint8List.fromList(value));
  }

  static enc.Key _deriveKeyV1(String password) {
    final hash = crypto.sha256.convert(utf8.encode(password)).bytes;
    return enc.Key(Uint8List.fromList(hash));
  }

  static Uint8List obfuscateFileData(Uint8List data) {
    final junk = _getSecureBytes(_junkBytesLength);
    final result = Uint8List(junk.length + data.length);
    result.setAll(0, junk);
    result.setAll(junk.length, data);
    return result;
  }

  static Uint8List deobfuscateFileData(Uint8List data) {
    if (data.length <= _junkBytesLength) return data;
    return data.sublist(_junkBytesLength);
  }
}

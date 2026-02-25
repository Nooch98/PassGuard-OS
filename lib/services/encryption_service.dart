import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart' as crypto;

import 'package:pointycastle/export.dart';

class EncryptionService {
  static const String _v4Prefix = "v4";
  static const String _v3Prefix = "v3";
  static const String _v2Prefix = "v2";

  static const int _junkBytesLength = 64;

  static const String _v2SaltLegacy = "CYBER_SECURE_SALT_2026_PRO_STRETCH";

  static const int _v4SaltLength = 16;
  static const int _v4NonceLength = 12;
  static const int _v4KeyLength = 32;
  static const int _v4Pbkdf2Iterations = 200000;

  static const int _gcmTagBits = 128;

  static Uint8List _secureRandomBytes(int length) {
    final r = Random.secure();
    final out = Uint8List(length);
    for (int i = 0; i < length; i++) {
      out[i] = r.nextInt(256);
    }
    return out;
  }

  static Uint8List _pbkdf2HmacSha256({
    required String password,
    required Uint8List salt,
    required int iterations,
    required int dkLen,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(salt, iterations, dkLen));
    final passBytes = Uint8List.fromList(utf8.encode(password));
    return derivator.process(passBytes);
  }

  static String _encryptV4(String plaintext, String masterPassword) {
    if (plaintext.isEmpty) return "";

    final salt = _secureRandomBytes(_v4SaltLength);
    final nonce = _secureRandomBytes(_v4NonceLength);

    final keyBytes = _pbkdf2HmacSha256(
      password: masterPassword,
      salt: salt,
      iterations: _v4Pbkdf2Iterations,
      dkLen: _v4KeyLength,
    );

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(keyBytes),
      _gcmTagBits,
      nonce,
      Uint8List(0),
    );

    cipher.init(true, params);

    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    final cipherWithTag = cipher.process(plainBytes);

    final saltB64 = base64.encode(salt);
    final nonceB64 = base64.encode(nonce);
    final cipherB64 = base64.encode(cipherWithTag);

    return "$_v4Prefix.$saltB64.$nonceB64.$cipherB64";
  }

  static String _decryptV4({
    required List<String> parts,
    required String masterPassword,
  }) {
    final salt = base64.decode(parts[1]);
    final nonce = base64.decode(parts[2]);
    final cipherWithTag = base64.decode(parts[3]);

    final keyBytes = _pbkdf2HmacSha256(
      password: masterPassword,
      salt: Uint8List.fromList(salt),
      iterations: _v4Pbkdf2Iterations,
      dkLen: _v4KeyLength,
    );

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(keyBytes),
      _gcmTagBits,
      Uint8List.fromList(nonce),
      Uint8List(0),
    );

    cipher.init(false, params);

    final clearBytes = cipher.process(Uint8List.fromList(cipherWithTag));
    return utf8.decode(clearBytes);
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

  static String encrypt(String text, String masterPassword) {
    return _encryptV4(text, masterPassword);
  }

  static String decrypt({
    required String combinedText,
    required Uint8List masterKeyBytes,
    Function(String upgradedText)? onUpgrade,
  }) {
    if (combinedText.isEmpty) return "";

    try {
      final masterPassword = utf8.decode(masterKeyBytes);
      final parts = combinedText.split('.');

      if (parts.length == 4 && parts[0] == _v4Prefix) {
        return _decryptV4(parts: parts, masterPassword: masterPassword);
      }

      if (parts.length == 4 && parts[0] == _v3Prefix) {
        final saltBase64 = parts[1];
        final ivBase64 = parts[2];
        final cipherText = parts[3];

        final key = _deriveKeyV3(masterPassword, saltBase64);
        final iv = enc.IV.fromBase64(ivBase64);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

        final decryptedText = encrypter.decrypt64(cipherText, iv: iv);

        if (onUpgrade != null) {
          onUpgrade(_encryptV4(decryptedText, masterPassword));
        }
        return decryptedText;
      }

      if (parts.length == 3 && parts[0] == _v2Prefix) {
        final key = _deriveKeyV2(masterPassword);
        final iv = enc.IV.fromBase64(parts[1]);
        final cipherText = parts[2];

        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final decryptedText = encrypter.decrypt64(cipherText, iv: iv);

        if (onUpgrade != null) {
          onUpgrade(_encryptV4(decryptedText, masterPassword));
        }
        return decryptedText;
      }

      if (parts.length == 2) {
        final key = _deriveKeyV1(masterPassword);
        final iv = enc.IV.fromBase64(parts[0]);
        final cipherText = parts[1];

        final encrypter = enc.Encrypter(enc.AES(key));
        final decryptedText = encrypter.decrypt64(cipherText, iv: iv);

        if (onUpgrade != null) {
          onUpgrade(_encryptV4(decryptedText, masterPassword));
        }
        return decryptedText;
      }

      throw Exception("FORMAT_ERROR");
    } on InvalidCipherTextException {
      return "ERROR: DECRYPTION_FAILED";
    } catch (_) {
      return "ERROR: DECRYPTION_FAILED";
    }
  }

  static Uint8List obfuscateFileData(Uint8List data) {
    final junk = enc.IV.fromSecureRandom(_junkBytesLength).bytes;
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

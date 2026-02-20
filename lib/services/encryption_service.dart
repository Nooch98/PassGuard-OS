import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:convert';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static enc.Key _deriveKey(String masterPassword) {
    final hash = sha256.convert(utf8.encode(masterPassword)).bytes;
    return enc.Key(Uint8List.fromList(hash));
  }

  static String encrypt(String text, String masterPassword) {
    final key = _deriveKey(masterPassword);
    final iv = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(key));

    final encrypted = encrypter.encrypt(text, iv: iv);

    return "${iv.base64}.${encrypted.base64}";
  }

  static String decrypt(String combinedText, Uint8List masterKeyBytes) {
    try {
      final passwordString = utf8.decode(masterKeyBytes);
      final key = _deriveKey(passwordString);

      final encrypter = enc.Encrypter(enc.AES(key));

      final parts = combinedText.split('.');
      if (parts.length != 2) throw Exception("Invalid encryption format");

      final iv = enc.IV.fromBase64(parts[0]);
      final cipherText = parts[1];

      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      return "ERROR: DECRYPTION_FAILED";
    }
  }
}

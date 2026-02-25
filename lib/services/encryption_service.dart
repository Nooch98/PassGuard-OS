import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:convert';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static const String _v2Prefix = "v2";
  static const int _junkBytesLength = 64;
  static const String _v2Salt = "CYBER_SECURE_SALT_2026_PRO_STRETCH";


  static enc.Key _deriveKeyV1(String password) {
    final hash = sha256.convert(utf8.encode(password)).bytes;
    return enc.Key(Uint8List.fromList(hash));
  }

  static enc.Key _deriveKeyV2(String password) {
    List<int> value = utf8.encode(password + _v2Salt);
    
    for (int i = 0; i < 50000; i++) {
      value = sha256.convert(value).bytes;
    }
    
    return enc.Key(Uint8List.fromList(value));
  }

  static String encrypt(String text, String masterPassword) {
    if (text.isEmpty) return "";
    
    final key = _deriveKeyV2(masterPassword);
    final iv = enc.IV.fromSecureRandom(16); 
    
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(text, iv: iv);

    return "$_v2Prefix.${iv.base64}.${encrypted.base64}";
  }

  static String decrypt({
    required String combinedText,
    required Uint8List masterKeyBytes,
    Function(String upgradedText)? onUpgrade,
  }) {
    if (combinedText.isEmpty) return "";

    try {
      final passwordString = utf8.decode(masterKeyBytes);
      final parts = combinedText.split('.');

      if (parts.length == 3 && parts[0] == _v2Prefix) {
        final key = _deriveKeyV2(passwordString);
        final iv = enc.IV.fromBase64(parts[1]);
        final cipherText = parts[2];
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        return encrypter.decrypt64(cipherText, iv: iv);
      } 
      else if (parts.length == 2) {
        final key = _deriveKeyV1(passwordString);
        final iv = enc.IV.fromBase64(parts[0]);
        final cipherText = parts[1];
        
        final encrypter = enc.Encrypter(enc.AES(key)); 
        final decryptedText = encrypter.decrypt64(cipherText, iv: iv);

        if (onUpgrade != null) {
          final v2Data = encrypt(decryptedText, passwordString);
          onUpgrade(v2Data);
        }

        return decryptedText;
      }

      throw Exception("FORMAT_ERROR");
    } catch (e) {
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

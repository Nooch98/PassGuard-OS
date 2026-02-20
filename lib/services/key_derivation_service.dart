import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'dart:math';

class KeyDerivationService {
  static const int _iterations = 100000;
  static const int _keyLength = 32;
  static const int _saltLength = 32;

  static Uint8List generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltLength, (i) => random.nextInt(256))
    );
  }

  static Uint8List deriveKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, _keyLength));

    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static String hashPassword(String password, Uint8List salt) {
    final key = deriveKey(password, salt);
    return base64Encode(key);
  }

  static bool verifyPassword(String password, String storedHash, Uint8List salt) {
    final hash = hashPassword(password, salt);
    return hash == storedHash;
  }

  static String saltToString(Uint8List salt) {
    return base64Encode(salt);
  }

  static Uint8List saltFromString(String saltString) {
    return base64Decode(saltString);
  }
}

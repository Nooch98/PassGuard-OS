import 'package:flutter_test/flutter_test.dart';
import 'package:passguard/services/encryption_service.dart';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  group('EncryptionService Tests', () {
    const testKey = 'TestMasterPassword123!';
    final testKeyBytes = Uint8List.fromList(utf8.encode(testKey));
    const testData = 'MySecretPassword';

    test('Encrypt and decrypt should return original data', () {
      final encrypted = EncryptionService.encrypt(testData, testKey);
      final decrypted = EncryptionService.decrypt(
        combinedText: encrypted,
        masterKeyBytes: testKeyBytes,
      );
      expect(decrypted, equals(testData));
      expect(encrypted, isNot(equals(testData)));
    });

    test('Encrypted data should be different each time (random IV)', () {
      final encrypted1 = EncryptionService.encrypt(testData, testKey);
      final encrypted2 = EncryptionService.encrypt(testData, testKey);
      expect(encrypted1, isNot(equals(encrypted2)));
    });

    test('Wrong key should fail decryption', () {
      final encrypted = EncryptionService.encrypt(testData, testKey);
      final wrongKeyBytes = Uint8List.fromList(utf8.encode('WrongPassword'));

      final result = EncryptionService.decrypt(
        combinedText: encrypted,
        masterKeyBytes: wrongKeyBytes,
      );
      expect(result, contains('ERROR'));
    });

    test('Should handle non-empty string', () {
      const data = 'A';
      final encrypted = EncryptionService.encrypt(data, testKey);
      final decrypted = EncryptionService.decrypt(
        combinedText: encrypted,
        masterKeyBytes: testKeyBytes,
      );
      expect(decrypted, equals(data));
    });

    test('Should handle special characters', () {
      const specialData = 'Test!@#\$%^&*()_+-=[]{}|;:",.<>?/~`';
      final encrypted = EncryptionService.encrypt(specialData, testKey);
      final decrypted = EncryptionService.decrypt(
        combinedText: encrypted,
        masterKeyBytes: testKeyBytes,
      );
      expect(decrypted, equals(specialData));
    });

    test('Should handle unicode characters', () {
      const unicodeData = 'Password with emojis 🔐🔑🛡️';
      final encrypted = EncryptionService.encrypt(unicodeData, testKey);
      final decrypted = EncryptionService.decrypt(
        combinedText: encrypted,
        masterKeyBytes: testKeyBytes,
      );
      expect(decrypted, equals(unicodeData));
    });

    test('Should handle very long strings', () {
      final longData = 'A' * 10000;
      final encrypted = EncryptionService.encrypt(longData, testKey);
      final decrypted = EncryptionService.decrypt(
        combinedText: encrypted,
        masterKeyBytes: testKeyBytes,
      );
      expect(decrypted, equals(longData));
    });
  });
}

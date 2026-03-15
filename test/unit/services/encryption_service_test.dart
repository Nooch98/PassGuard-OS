import 'package:flutter_test/flutter_test.dart';
import 'package:passguard/services/encryption_service.dart';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  group('EncryptionService Tests', () {
    const testMasterPassword = 'TestMasterPassword123!';
    final testMasterKeyBytes = Uint8List.fromList(utf8.encode(testMasterPassword));
    const testData = 'MySecretPassword';

    test('Encrypt and decrypt should return original data', () {
      final encrypted = EncryptionService.encrypt(testData, testMasterPassword);
      final decrypted = EncryptionService.decrypt(
        combinedText: encrypted, 
        masterKeyBytes: testMasterKeyBytes
      );
      expect(decrypted, equals(testData));
      expect(encrypted.startsWith('v4'), isTrue);
    });

    test('Encrypted data should be different each time (random IV/Salt)', () {
      final encrypted1 = EncryptionService.encrypt(testData, testMasterPassword);
      final encrypted2 = EncryptionService.encrypt(testData, testMasterPassword);
      expect(encrypted1, isNot(equals(encrypted2)));
    });

    test('Wrong key should fail decryption', () {
      final encrypted = EncryptionService.encrypt(testData, testMasterPassword);
      final wrongKeyBytes = Uint8List.fromList(utf8.encode('WrongPassword123'));
      final result = EncryptionService.decrypt(
        combinedText: encrypted, 
        masterKeyBytes: wrongKeyBytes
      );
      expect(result, equals("ERROR: DECRYPTION_FAILED"));
    });

    test('Obfuscation should add correct junk bytes', () {
      final data = Uint8List.fromList(utf8.encode("raw_data"));
      final obfuscated = EncryptionService.obfuscateFileData(data);
      expect(obfuscated.length, equals(data.length + 64));
      final deobfuscated = EncryptionService.deobfuscateFileData(obfuscated);
      expect(deobfuscated, equals(data));
    });
  });
}

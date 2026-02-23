import 'package:flutter_test/flutter_test.dart';
import 'package:passguard/services/password_generator_service.dart';

void main() {
  group('PasswordGeneratorService Tests', () {
    test('Generate password should respect length', () {
      // Arrange
      const config = PasswordGeneratorConfig(length: 16);

      // Act
      final password = PasswordGeneratorService.generatePassword(config);

      // Assert
      expect(password.length, equals(16));
    });

    test('Generate password should include uppercase when enabled', () {
      // Arrange
      const config = PasswordGeneratorConfig(
        length: 20,
        includeUppercase: true,
        includeLowercase: false,
        includeNumbers: false,
        includeSymbols: false,
      );

      // Act
      final password = PasswordGeneratorService.generatePassword(config);

      // Assert
      expect(password, matches(RegExp(r'[A-Z]')));
      expect(password, isNot(matches(RegExp(r'[a-z]'))));
      expect(password, isNot(matches(RegExp(r'[0-9]'))));
    });

    test('Generate password should exclude ambiguous chars when requested', () {
      // Arrange
      const config = PasswordGeneratorConfig(
        length: 50,
        excludeAmbiguous: true,
      );

      // Act
      final password = PasswordGeneratorService.generatePassword(config);

      // Assert
      expect(password, isNot(contains('i')));
      expect(password, isNot(contains('l')));
      expect(password, isNot(contains('1')));
      expect(password, isNot(contains('L')));
      expect(password, isNot(contains('o')));
      expect(password, isNot(contains('0')));
      expect(password, isNot(contains('O')));
    });

    test('Generate passphrase should contain correct number of words', () {
      // Act
      final passphrase = PasswordGeneratorService.generatePassphrase(wordCount: 5);
      final words = passphrase.split('-');

      // Assert
      expect(words.length, equals(6)); // 5 words + 1 number
      expect(words.last, matches(RegExp(r'^\d+$'))); // Last element is a number
    });

    test('Generate PIN should contain only numbers', () {
      // Act
      final pin = PasswordGeneratorService.generatePin(length: 8);

      // Assert
      expect(pin.length, equals(8));
      expect(pin, matches(RegExp(r'^\d+$')));
    });

    test('Calculate strength should return 0 for empty password', () {
      // Act
      final strength = PasswordGeneratorService.calculateStrength('');

      // Assert
      expect(strength, equals(0));
    });

    test('Calculate strength should return higher score for complex passwords', () {
      // Act
      final weakStrength = PasswordGeneratorService.calculateStrength('password');
      final strongStrength = PasswordGeneratorService.calculateStrength('P@ssw0rd!2024#Complex');

      // Assert
      expect(strongStrength, greaterThan(weakStrength));
    });

    test('Get strength label should return correct labels', () {
      // Assert
      expect(PasswordGeneratorService.getStrengthLabel(90), equals('VERY_STRONG'));
      expect(PasswordGeneratorService.getStrengthLabel(70), equals('STRONG'));
      expect(PasswordGeneratorService.getStrengthLabel(50), equals('MODERATE'));
      expect(PasswordGeneratorService.getStrengthLabel(30), equals('WEAK'));
      expect(PasswordGeneratorService.getStrengthLabel(10), equals('VERY_WEAK'));
    });

    test('Generated passwords should be unique', () {
      // Arrange
      const config = PasswordGeneratorConfig(length: 16);
      final passwords = <String>{};

      // Act
      for (int i = 0; i < 100; i++) {
        passwords.add(PasswordGeneratorService.generatePassword(config));
      }

      // Assert
      expect(passwords.length, equals(100)); // All unique
    });
  });
}

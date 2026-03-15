import 'package:flutter_test/flutter_test.dart';
import 'package:passguard/services/password_generator_service.dart';

void main() {
  group('PasswordGeneratorPro Tests', () {
    final generator = PasswordGeneratorPro();

    test('Generate random password should respect length and complexity', () {
      final options = const GeneratorOptions(
        mode: GeneratorMode.random,
        length: 16,
        upper: true,
        lower: false,
        digits: false,
        symbols: false,
      );
      final result = generator.generate(options);
      expect(result.value.length, equals(16));
      expect(result.value, matches(RegExp(r'^[A-Z]+$')));
    });

    test('Generate password should exclude ambiguous chars when requested', () {
      final options = const GeneratorOptions(
        mode: GeneratorMode.random,
        length: 50,
        avoidAmbiguous: true,
      );
      final result = generator.generate(options);
      final ambiguous = ['0', 'O', 'o', '1', 'l', 'I', 'S', 's', 'Z', 'z', 'B', '|', '/', '\\'];
      for (var char in ambiguous) {
        expect(result.value, isNot(contains(char)), reason: 'Should not contain $char');
      }
    });

    test('Diceware should throw if wordlist is not set', () {
      final options = const GeneratorOptions(mode: GeneratorMode.diceware);
      expect(() => generator.generate(options), throwsStateError);
    });

    test('Diceware should generate passphrase with correct structure', () {
      PasswordGeneratorPro.setWordlist(['apple', 'banana', 'cherry', 'date', 'elderberry']);
      final options = const GeneratorOptions(
        mode: GeneratorMode.diceware,
        words: 3,
        wordSeparator: '-',
      );
      final result = generator.generate(options);
      final parts = result.value.split('-');
      expect(parts.length, equals(3));
      expect(result.mode, equals(GeneratorMode.diceware));
    });

    test('Pattern generator should follow specific format', () {
      final options = const GeneratorOptions(
        mode: GeneratorMode.pattern,
        pattern: 'AAA-999',
      );
      final result = generator.generate(options);
      expect(result.value, matches(RegExp(r'[A-Z]{3}-[0-9]{3}')));
    });

    test('Strength calculation thresholds', () {
      final weakOptions = const GeneratorOptions(mode: GeneratorMode.random, length: 5);
      final weakResult = generator.generate(weakOptions);
      expect(weakResult.strength, equals(StrengthLevel.weak));
      final strongOptions = const GeneratorOptions(mode: GeneratorMode.random, length: 30);
      final strongResult = generator.generate(strongOptions);
      expect(strongResult.entropyBits, greaterThan(85));
      expect(strongResult.strength, equals(StrengthLevel.overkill));
    });

    test('Generated passwords should be unique', () {
      final options = const GeneratorOptions(mode: GeneratorMode.random, length: 20);
      final results = <String>{};
      for (int i = 0; i < 100; i++) {
        results.add(generator.generate(options).value);
      }
      expect(results.length, equals(100));
    });
  });
}

/*
|--------------------------------------------------------------------------
| PassGuard OS - PasswordGenerator (Advanced Generator Engine)
|--------------------------------------------------------------------------
| Description:
|   Core engine for PassGuard OS "Generator Pro". Generates secure credentials
|   using multiple strategies, returning both the value and an entropy estimate.
|
| Supported Generator Modes:
|   1) GeneratorMode.random
|      - Builds a character pool from enabled sets (upper/lower/digits/symbols)
|      - Optional: avoidAmbiguous (removes chars like 0/O, 1/I/l, etc.)
|      - Optional: enforceAllSets (guarantees at least 1 char from each enabled set)
|
|   2) GeneratorMode.diceware (passphrases)
|      - Picks N random words from a wordlist (ideally 2k+ words, minimum 256)
|      - Joins with a separator (e.g. "-", "_", ".")
|      - Optional: capitalize one word
|      - Optional: append random number and/or symbol
|      - Wordlist source priority:
|          a) dicewareWordlist passed into generate()
|          b) _externalWordlist set via PasswordGeneratorPro.setWordlist()
|        If no list is available -> throws StateError
|
|   3) GeneratorMode.pronounceable
|      - Generates pseudo-pronounceable strings using consonant/vowel patterns
|      - Optional: random capitalization / number / symbol append
|
|   4) GeneratorMode.pattern
|      - Pattern mini-language:
|          'A' -> uppercase, 'a' -> lowercase, '9' -> digit, '#' -> symbol, '*' -> any enabled pool
|          '[...]' -> custom inline set (respects avoidAmbiguous)
|          '\' -> escape next character (literal)
|      - Also calculates approximate entropy based on the chosen pools/sets
|
| Output:
|   GeneratedPassword { value, entropyBits, mode, meta }
|   - meta includes parameters useful for audits & UI display
|   - entropyBits is an estimate (useful for ranking, not a formal proof)
|
| Threat model assumptions:
|   - The generator runs locally and uses Random.secure() for cryptographic randomness.
|   - Strength depends on user-selected options (length/sets/wordlist size).
|   - Diceware security depends heavily on the size/quality of the wordlist.
|
| What this service does NOT protect against:
|   - Keyloggers capturing generated output at the moment of entry
|   - Screen recording / screenshot malware
|   - Memory scraping on compromised systems during runtime
|   - Weak master passwords or compromised vault encryption elsewhere in the app
|
| Notes:
|   - This file focuses on generation + entropy estimation only.
|   - Storage, encryption, clipboard policy, and UI are handled elsewhere.
|
| Evolution:
| - Smart Leetspeak: Advanced Diceware with selective character substitution.
| - Crack Time Estimation: Real-world security metrics (10^12 att/sec).
| - Strength Analysis: Categorization based on entropy thresholds.
| - Comprehensive Entropy: Precise calculation for all generation modes.
|--------------------------------------------------------------------------
*/

import 'dart:math';

enum GeneratorMode { random, diceware, pronounceable, pattern }

enum StrengthLevel { weak, fair, good, strong, overkill }

class GeneratorOptions {
  final GeneratorMode mode;

  final int length;
  final bool upper;
  final bool lower;
  final bool digits;
  final bool symbols;
  final bool avoidAmbiguous;
  final bool enforceAllSets;

  final int words;
  final String wordSeparator;
  final bool dicewareCapitalize;
  final bool dicewareAddNumber;
  final bool dicewareAddSymbol;
  final bool useSmartLeet;

  final int syllables;
  final bool pronounceableCapitalize;
  final bool pronounceableAddNumber;
  final bool pronounceableAddSymbol;

  final String? pattern;

  const GeneratorOptions({
    required this.mode,
    this.length = 20,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
    this.avoidAmbiguous = true,
    this.enforceAllSets = true,
    this.words = 6,
    this.wordSeparator = '-',
    this.dicewareCapitalize = false,
    this.dicewareAddNumber = false,
    this.dicewareAddSymbol = false,
    this.useSmartLeet = false,
    this.syllables = 5,
    this.pronounceableCapitalize = false,
    this.pronounceableAddNumber = false,
    this.pronounceableAddSymbol = false,
    this.pattern,
  });
}

class GeneratedPassword {
  final String value;
  final double entropyBits;
  final String crackTime;
  final StrengthLevel strength;
  final GeneratorMode mode;
  final Map<String, Object?> meta;

  const GeneratedPassword({
    required this.value,
    required this.entropyBits,
    required this.crackTime,
    required this.strength,
    required this.mode,
    required this.meta,
  });
}

class PasswordGeneratorPro {
  PasswordGeneratorPro({Random? random}) : _rng = random ?? Random.secure();

  final Random _rng;
  static List<String>? _externalWordlist;

  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  static const String _symbols = r'!@#$%^&*()-_=+[]{};:,.?/|~';

  static const Map<String, String> _leetMap = {
    'a': '4', 'e': '3', 'i': '1', 'o': '0', 's': '5', 't': '7', 'b': '8'
  };

  static const Set<String> _ambiguousChars = {
    '0', 'O', 'o', '1', 'l', 'I', '5', 'S', 's', '2', 'Z', 'z', '8', 'B', '|', '/', '\\',
  };

  static void setWordlist(List<String> words) {
    _externalWordlist = words;
  }

  GeneratedPassword generate(
    GeneratorOptions opt, {
    List<String>? dicewareWordlist,
  }) {
    switch (opt.mode) {
      case GeneratorMode.random:
        return _generateRandom(opt);
      case GeneratorMode.diceware:
        final wordlist = dicewareWordlist ?? _externalWordlist;
        if (wordlist == null || wordlist.isEmpty) {
          throw StateError('Diceware wordlist not initialized');
        }
        return _generateDiceware(opt, wordlist);
      case GeneratorMode.pronounceable:
        return _generatePronounceable(opt);
      case GeneratorMode.pattern:
        return _generatePattern(opt);
    }
  }

  GeneratedPassword _generateRandom(GeneratorOptions opt) {
    if (opt.length < 4) throw ArgumentError('Length too short');

    final sets = <String>[];
    if (opt.upper) sets.add(_filterAmbiguous(_upper, opt.avoidAmbiguous));
    if (opt.lower) sets.add(_filterAmbiguous(_lower, opt.avoidAmbiguous));
    if (opt.digits) sets.add(_filterAmbiguous(_digits, opt.avoidAmbiguous));
    if (opt.symbols) sets.add(_filterAmbiguous(_symbols, opt.avoidAmbiguous));

    if (sets.isEmpty) throw ArgumentError('Activate at least one character set');

    final pool = sets.join();
    final chars = <String>[];

    if (opt.enforceAllSets) {
      for (final s in sets) {
        chars.add(_pickChar(s));
      }
    }

    while (chars.length < opt.length) {
      chars.add(_pickChar(pool));
    }

    _shuffle(chars);
    final value = chars.join();
    final entropy = _entropyBits(pool.length, opt.length);

    return _assemble(value, entropy, GeneratorMode.random, {
      'poolSize': pool.length,
      'length': opt.length,
    });
  }

  GeneratedPassword _generateDiceware(GeneratorOptions opt, List<String> wordlist) {
    if (opt.words < 3) throw ArgumentError('Recommended Diceware >= 3 words');

    final picked = List<String>.generate(opt.words, (_) => wordlist[_rng.nextInt(wordlist.length)]);

    if (opt.useSmartLeet) {
      for (int i = 0; i < picked.length; i++) {
        if (_rng.nextDouble() < 0.4) picked[i] = _applySmartLeet(picked[i]);
      }
    }

    if (opt.dicewareCapitalize && picked.isNotEmpty) {
      final i = _rng.nextInt(picked.length);
      picked[i] = _capitalize(picked[i]);
    }

    String value = picked.join(opt.wordSeparator);

    if (opt.dicewareAddNumber) value += _digits[_rng.nextInt(_digits.length)];
    if (opt.dicewareAddSymbol) value += _symbols[_rng.nextInt(_symbols.length)];

    double entropy = opt.words * _log2(wordlist.length.toDouble());
    if (opt.useSmartLeet) entropy += (opt.words * 0.7); // Estimated boost for leet substitutions
    if (opt.dicewareAddNumber) entropy += _log2(10);
    if (opt.dicewareAddSymbol) entropy += _log2(_symbols.length.toDouble());

    return _assemble(value, entropy, GeneratorMode.diceware, {
      'words': opt.words,
      'leetApplied': opt.useSmartLeet,
    });
  }

  GeneratedPassword _generatePronounceable(GeneratorOptions opt) {
    const consonants = 'bcdfghjkmnpqrstvwxz';
    const vowels = 'aeiou';
    final sb = StringBuffer();

    for (int i = 0; i < opt.syllables; i++) {
      sb.write(consonants[_rng.nextInt(consonants.length)]);
      sb.write(vowels[_rng.nextInt(vowels.length)]);
      if (_rng.nextDouble() < 0.25) sb.write(consonants[_rng.nextInt(consonants.length)]);
    }

    String value = sb.toString();
    if (opt.pronounceableCapitalize && value.isNotEmpty) {
      final idx = _rng.nextInt(value.length);
      value = value.substring(0, idx) + value[idx].toUpperCase() + value.substring(idx + 1);
    }

    if (opt.pronounceableAddNumber) value += _digits[_rng.nextInt(_digits.length)];
    if (opt.pronounceableAddSymbol) value += _symbols[_rng.nextInt(_symbols.length)];

    final perSyllable = (consonants.length * vowels.length).toDouble();
    double entropy = opt.syllables * _log2(perSyllable);
    if (opt.pronounceableAddNumber) entropy += _log2(10);
    if (opt.pronounceableAddSymbol) entropy += _log2(_symbols.length.toDouble());

    return _assemble(value, entropy, GeneratorMode.pronounceable, {'syllables': opt.syllables});
  }

  GeneratedPassword _generatePattern(GeneratorOptions opt) {
    final pattern = opt.pattern ?? '';
    if (pattern.isEmpty) throw ArgumentError('Pattern required');

    final out = StringBuffer();
    final poolParts = <String>[];
    if (opt.upper) poolParts.add(_filterAmbiguous(_upper, opt.avoidAmbiguous));
    if (opt.lower) poolParts.add(_filterAmbiguous(_lower, opt.avoidAmbiguous));
    if (opt.digits) poolParts.add(_filterAmbiguous(_digits, opt.avoidAmbiguous));
    if (opt.symbols) poolParts.add(_filterAmbiguous(_symbols, opt.avoidAmbiguous));
    final anyPool = poolParts.join();

    double entropy = 0;
    int i = 0;
    while (i < pattern.length) {
      final ch = pattern[i];
      if (ch == r'\') {
        if (i + 1 < pattern.length) {
          out.write(pattern[i + 1]);
          i += 2;
        } else {
          out.write(r'\');
          i++;
        }
        continue;
      }

      if (ch == '[') {
        final end = pattern.indexOf(']', i + 1);
        if (end == -1) throw ArgumentError('Missing "]"');
        final filtered = _filterAmbiguous(pattern.substring(i + 1, end), opt.avoidAmbiguous);
        out.write(_pickChar(filtered));
        entropy += _log2(filtered.length.toDouble());
        i = end + 1;
        continue;
      }

      switch (ch) {
        case 'A':
          final s = _filterAmbiguous(_upper, opt.avoidAmbiguous);
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;
        case 'a':
          final s = _filterAmbiguous(_lower, opt.avoidAmbiguous);
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;
        case '9':
          final s = _filterAmbiguous(_digits, opt.avoidAmbiguous);
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;
        case '#':
          final s = _filterAmbiguous(_symbols, opt.avoidAmbiguous);
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;
        case '*':
          out.write(_pickChar(anyPool));
          entropy += _log2(anyPool.length.toDouble());
          break;
        default:
          out.write(ch);
      }
      i++;
    }

    return _assemble(out.toString(), entropy, GeneratorMode.pattern, {'pattern': pattern});
  }

  GeneratedPassword _assemble(String val, double entropy, GeneratorMode mode, Map<String, Object?> meta) {
    return GeneratedPassword(
      value: val,
      entropyBits: entropy,
      crackTime: _estimateCrackTime(entropy),
      strength: _getStrengthLevel(entropy),
      mode: mode,
      meta: meta,
    );
  }

  String _applySmartLeet(String input) {
    var chars = input.split('');
    for (int i = 0; i < chars.length; i++) {
      final key = chars[i].toLowerCase();
      if (_leetMap.containsKey(key) && _rng.nextDouble() < 0.3) {
        chars[i] = _leetMap[key]!;
      }
    }
    return chars.join();
  }

  String _estimateCrackTime(double entropy) {
    final seconds = pow(2, entropy) / 1e12;
    if (seconds < 1) return "Instantáneo";
    if (seconds < 3600) return "${(seconds / 60).toStringAsFixed(0)} minutos";
    if (seconds < 86400) return "${(seconds / 3600).toStringAsFixed(0)} horas";
    if (seconds < 2592000) return "${(seconds / 86400).toStringAsFixed(0)} días";
    if (seconds < 31536000) return "${(seconds / 2592000).toStringAsFixed(0)} meses";
    if (seconds < 3153600000) return "${(seconds / 31536000).toStringAsFixed(0)} años";
    return "Siglos / Inmune";
  }

  StrengthLevel _getStrengthLevel(double entropy) {
    if (entropy < 45) return StrengthLevel.weak;
    if (entropy < 65) return StrengthLevel.fair;
    if (entropy < 85) return StrengthLevel.good;
    if (entropy < 115) return StrengthLevel.strong;
    return StrengthLevel.overkill;
  }

  String _pickChar(String set) => set[_rng.nextInt(set.length)];

  void _shuffle(List<String> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  String _filterAmbiguous(String s, bool avoid) {
    if (!avoid) return s;
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (!_ambiguousChars.contains(s[i])) b.write(s[i]);
    }
    return b.toString();
  }

  String _capitalize(String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);

  double _entropyBits(int alphabetSize, int length) => length * _log2(alphabetSize.toDouble());

  double _log2(double x) => log(x) / ln2;
}

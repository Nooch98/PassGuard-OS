/*
|--------------------------------------------------------------------------
| PassGuard OS - PasswordGenerator (Advanced Generator Engine)
|--------------------------------------------------------------------------
| Description:
|   Generates credentials using multiple strategies and returns:
|   - value
|   - estimated entropy
|   - theoretical offline crack-time estimate
|   - strength category
|
| Supported Modes:
|   1) random
|      - Random selection from enabled character pools
|      - Optional ambiguous-character filtering
|      - Optional enforcement of at least one character from each enabled set
|
|   2) diceware
|      - Random passphrase from a supplied wordlist
|      - Optional capitalization / appended number / appended symbol
|      - Optional smart leet substitutions (cosmetic, conservative entropy bonus)
|
|   3) pronounceable
|      - Pseudo-pronounceable output using consonant/vowel structures
|      - Easier to remember, but less resistant than fully random output
|
|   4) pattern
|      - Pattern language:
|          'A' -> uppercase
|          'a' -> lowercase
|          '9' -> digit
|          '#' -> symbol
|          '*' -> any enabled pool
|          '[...]' -> inline custom set
|          '\' -> escape next character
|
|   5) quantum
|      - Legacy name kept for compatibility.
|      - Generates a very high-entropy random password and exposes a
|        Grover-adjusted heuristic margin in metadata.
|      - This is NOT post-quantum cryptography; it is a high-entropy mode.
|
| Notes:
|   - Entropy is an estimate, not a proof.
|   - Crack-time values are theoretical offline estimates.
|   - Storage, encryption, clipboard policy, and UI are handled elsewhere.
|--------------------------------------------------------------------------
*/

import 'dart:math';
import 'dart:math' as math;

enum GeneratorMode { random, diceware, pronounceable, pattern, quantum }

enum StrengthLevel {
  weak,
  fair,
  good,
  strong,
  overkill,
  ultra,
}

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
    'a': '4',
    'e': '3',
    'i': '1',
    'o': '0',
    's': '5',
    't': '7',
    'b': '8',
  };

  static const Set<String> _ambiguousChars = {
    '0', 'O', 'o', '1', 'l', 'I', '5', 'S', 's', '2', 'Z', 'z', '8', 'B', '|', '/', '\\',
  };

  static const double _offlineGuessesPerSecond = 1e12;
  static const double _highEntropyTargetBits = 128.0;
  static void setWordlist(List<String> words) {
    _externalWordlist = words.where((w) => w.trim().isNotEmpty).toList(growable: false);
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
      case GeneratorMode.quantum:
        return _generateHighEntropy(opt);
    }
  }

  GeneratedPassword _generateRandom(GeneratorOptions opt) {
    final sets = _enabledSets(opt);
    if (sets.isEmpty) {
      throw ArgumentError('Activate at least one character set');
    }

    if (opt.length < 1) {
      throw ArgumentError('Length must be at least 1');
    }

    if (opt.enforceAllSets && opt.length < sets.length) {
      throw ArgumentError(
        'Length must be >= enabled character-set count when enforceAllSets is true',
      );
    }

    final pool = sets.join();
    if (pool.isEmpty) {
      throw ArgumentError('Character pool became empty after filtering');
    }

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

    return _assemble(
      value,
      entropy,
      GeneratorMode.random,
      {
        'poolSize': pool.length,
        'length': opt.length,
        'enforceAllSets': opt.enforceAllSets,
        'avoidAmbiguous': opt.avoidAmbiguous,
      },
    );
  }

  GeneratedPassword _generateDiceware(GeneratorOptions opt, List<String> wordlist) {
    final cleanWordlist = wordlist.where((w) => w.trim().isNotEmpty).toList(growable: false);

    if (cleanWordlist.length < 256) {
      throw ArgumentError('Diceware wordlist should contain at least 256 words');
    }

    if (opt.words < 4) {
      throw ArgumentError('Recommended Diceware minimum is 4 words');
    }

    final picked = List<String>.generate(
      opt.words,
      (_) => cleanWordlist[_rng.nextInt(cleanWordlist.length)],
      growable: true,
    );

    bool leetApplied = false;
    if (opt.useSmartLeet) {
      for (int i = 0; i < picked.length; i++) {
        if (_rng.nextDouble() < 0.35) {
          final transformed = _applySmartLeet(picked[i]);
          if (transformed != picked[i]) {
            picked[i] = transformed;
            leetApplied = true;
          }
        }
      }
    }

    bool capitalizationApplied = false;
    if (opt.dicewareCapitalize && picked.isNotEmpty) {
      final index = _rng.nextInt(picked.length);
      final capitalized = _capitalize(picked[index]);
      if (capitalized != picked[index]) {
        picked[index] = capitalized;
        capitalizationApplied = true;
      }
    }

    String value = picked.join(opt.wordSeparator);

    bool numberApplied = false;
    bool symbolApplied = false;

    if (opt.dicewareAddNumber) {
      value += _digits[_rng.nextInt(_digits.length)];
      numberApplied = true;
    }

    if (opt.dicewareAddSymbol) {
      final usableSymbols = _filterAmbiguous(_symbols, opt.avoidAmbiguous);
      if (usableSymbols.isEmpty) {
        throw ArgumentError('No symbols available after ambiguity filtering');
      }
      value += usableSymbols[_rng.nextInt(usableSymbols.length)];
      symbolApplied = true;
    }

    double entropy = opt.words * _log2(cleanWordlist.length.toDouble());

    if (capitalizationApplied) {
      entropy += _log2(opt.words.toDouble());
    }
    if (numberApplied) {
      entropy += _log2(10);
    }
    if (symbolApplied) {
      final usableSymbols = _filterAmbiguous(_symbols, opt.avoidAmbiguous);
      entropy += _log2(usableSymbols.length.toDouble());
    }
    if (leetApplied) {
      entropy += math.min(2.0, opt.words * 0.3);
    }

    return _assemble(
      value,
      entropy,
      GeneratorMode.diceware,
      {
        'words': opt.words,
        'wordlistSize': cleanWordlist.length,
        'separator': opt.wordSeparator,
        'capitalizationApplied': capitalizationApplied,
        'numberApplied': numberApplied,
        'symbolApplied': symbolApplied,
        'leetApplied': leetApplied,
      },
    );
  }

  GeneratedPassword _generatePronounceable(GeneratorOptions opt) {
    if (opt.syllables < 1) {
      throw ArgumentError('Syllables must be at least 1');
    }

    const consonants = 'bcdfghjkmnpqrstvwxz';
    const vowels = 'aeiou';

    final sb = StringBuffer();

    for (int i = 0; i < opt.syllables; i++) {
      sb.write(consonants[_rng.nextInt(consonants.length)]);
      sb.write(vowels[_rng.nextInt(vowels.length)]);
      if (_rng.nextDouble() < 0.25) {
        sb.write(consonants[_rng.nextInt(consonants.length)]);
      }
    }

    String value = sb.toString();

    bool capitalizationApplied = false;
    bool numberApplied = false;
    bool symbolApplied = false;

    if (opt.pronounceableCapitalize && value.isNotEmpty) {
      final idx = _rng.nextInt(value.length);
      value = value.substring(0, idx) +
          value[idx].toUpperCase() +
          value.substring(idx + 1);
      capitalizationApplied = true;
    }

    if (opt.pronounceableAddNumber) {
      value += _digits[_rng.nextInt(_digits.length)];
      numberApplied = true;
    }

    if (opt.pronounceableAddSymbol) {
      final usableSymbols = _filterAmbiguous(_symbols, true);
      if (usableSymbols.isEmpty) {
        throw ArgumentError('No symbols available after ambiguity filtering');
      }
      value += usableSymbols[_rng.nextInt(usableSymbols.length)];
      symbolApplied = true;
    }

    final basePerSyllable = (consonants.length * vowels.length).toDouble();
    double entropy = opt.syllables * _log2(basePerSyllable);

    if (capitalizationApplied) {
      entropy += _log2(value.length.toDouble());
    }
    if (numberApplied) {
      entropy += _log2(10);
    }
    if (symbolApplied) {
      final usableSymbols = _filterAmbiguous(_symbols, true);
      entropy += _log2(usableSymbols.length.toDouble());
    }

    entropy *= 0.82;

    return _assemble(
      value,
      entropy,
      GeneratorMode.pronounceable,
      {
        'syllables': opt.syllables,
        'capitalizationApplied': capitalizationApplied,
        'numberApplied': numberApplied,
        'symbolApplied': symbolApplied,
        'note': 'Pronounceable mode is easier to remember but weaker than fully random output at the same displayed length.',
      },
    );
  }

  GeneratedPassword _generatePattern(GeneratorOptions opt) {
    final pattern = opt.pattern ?? '';
    if (pattern.isEmpty) {
      throw ArgumentError('Pattern required');
    }

    final poolParts = _enabledSets(opt);
    final anyPool = poolParts.join();

    final out = StringBuffer();
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
        if (end == -1) {
          throw ArgumentError('Missing closing "]" in pattern');
        }

        final filtered = _filterAmbiguous(
          pattern.substring(i + 1, end),
          opt.avoidAmbiguous,
        );

        if (filtered.isEmpty) {
          throw ArgumentError('Inline set becomes empty after filtering');
        }

        out.write(_pickChar(filtered));
        entropy += _log2(filtered.length.toDouble());
        i = end + 1;
        continue;
      }

      switch (ch) {
        case 'A':
          final s = _filterAmbiguous(_upper, opt.avoidAmbiguous);
          _ensureNonEmptySet(s, 'uppercase');
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;

        case 'a':
          final s = _filterAmbiguous(_lower, opt.avoidAmbiguous);
          _ensureNonEmptySet(s, 'lowercase');
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;

        case '9':
          final s = _filterAmbiguous(_digits, opt.avoidAmbiguous);
          _ensureNonEmptySet(s, 'digits');
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;

        case '#':
          final s = _filterAmbiguous(_symbols, opt.avoidAmbiguous);
          _ensureNonEmptySet(s, 'symbols');
          out.write(_pickChar(s));
          entropy += _log2(s.length.toDouble());
          break;

        case '*':
          if (anyPool.isEmpty) {
            throw ArgumentError('Pattern "*" requires at least one enabled pool');
          }
          out.write(_pickChar(anyPool));
          entropy += _log2(anyPool.length.toDouble());
          break;

        default:
          out.write(ch);
      }

      i++;
    }

    return _assemble(
      out.toString(),
      entropy,
      GeneratorMode.pattern,
      {
        'pattern': pattern,
        'note': 'Pattern mode is powerful but can be weak if the pattern is predictable.',
      },
    );
  }

  GeneratedPassword _generateHighEntropy(GeneratorOptions opt) {
    final sets = <String>[
      _filterAmbiguous(_upper, opt.avoidAmbiguous),
      _filterAmbiguous(_lower, opt.avoidAmbiguous),
      _filterAmbiguous(_digits, opt.avoidAmbiguous),
      _filterAmbiguous(_symbols, opt.avoidAmbiguous),
    ];

    for (final s in sets) {
      if (s.isEmpty) {
        throw ArgumentError('High-entropy mode requires non-empty upper/lower/digit/symbol sets');
      }
    }

    final pool = sets.join();
    final bitsPerChar = _log2(pool.length.toDouble());

    final minLengthForTarget = (_highEntropyTargetBits / bitsPerChar).ceil();
    final targetLength = math.max(opt.length, math.max(20, minLengthForTarget));

    final chars = <String>[];

    for (final s in sets) {
      chars.add(_pickChar(s));
    }

    while (chars.length < targetLength) {
      chars.add(_pickChar(pool));
    }

    _shuffle(chars);

    final value = chars.join();
    final entropy = _entropyBits(pool.length, targetLength);
    final groverAdjustedBits = entropy / 2.0;

    return _assemble(
      value,
      entropy,
      GeneratorMode.quantum,
      {
        'modeLabel': 'high_entropy',
        'poolSize': pool.length,
        'length': targetLength,
        'targetEntropyBits': _highEntropyTargetBits,
        'groverAdjustedBits': double.parse(groverAdjustedBits.toStringAsFixed(2)),
        'note': 'Legacy "quantum" mode. Generates a high-entropy random password and exposes a Grover-adjusted heuristic margin. This is not post-quantum cryptography.',
      },
    );
  }

  GeneratedPassword _assemble(
    String value,
    double entropy,
    GeneratorMode mode,
    Map<String, Object?> meta,
  ) {
    final estimated = double.parse(entropy.toStringAsFixed(2));

    return GeneratedPassword(
      value: value,
      entropyBits: estimated,
      crackTime: _estimateCrackTime(estimated),
      strength: _getStrengthLevel(estimated),
      mode: mode,
      meta: meta,
    );
  }

  String _applySmartLeet(String input) {
    final chars = input.split('');
    bool changed = false;

    for (int i = 0; i < chars.length; i++) {
      final key = chars[i].toLowerCase();
      if (_leetMap.containsKey(key) && _rng.nextDouble() < 0.25) {
        chars[i] = _leetMap[key]!;
        changed = true;
      }
    }

    return changed ? chars.join() : input;
  }

  String _estimateCrackTime(double entropy) {
    final seconds = pow(2, entropy) / _offlineGuessesPerSecond;

    if (seconds < 1) return 'Instant (offline estimate)';
    if (seconds < 60) return '${seconds.toStringAsFixed(0)} seconds (estimate)';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(0)} minutes (estimate)';
    if (seconds < 86400) return '${(seconds / 3600).toStringAsFixed(0)} hours (estimate)';
    if (seconds < 2592000) return '${(seconds / 86400).toStringAsFixed(0)} days (estimate)';
    if (seconds < 31536000) return '${(seconds / 2592000).toStringAsFixed(0)} months (estimate)';
    if (seconds < 3153600000) return '${(seconds / 31536000).toStringAsFixed(0)} years (estimated)';
    return 'Centuries (estimate)';
  }

  StrengthLevel _getStrengthLevel(double entropy) {
    if (entropy < 45) return StrengthLevel.weak;
    if (entropy < 65) return StrengthLevel.fair;
    if (entropy < 85) return StrengthLevel.good;
    if (entropy < 115) return StrengthLevel.strong;
    if (entropy < 140) return StrengthLevel.overkill;
    return StrengthLevel.ultra;
  }

  List<String> _enabledSets(GeneratorOptions opt) {
    final sets = <String>[];

    if (opt.upper) {
      final s = _filterAmbiguous(_upper, opt.avoidAmbiguous);
      if (s.isNotEmpty) sets.add(s);
    }
    if (opt.lower) {
      final s = _filterAmbiguous(_lower, opt.avoidAmbiguous);
      if (s.isNotEmpty) sets.add(s);
    }
    if (opt.digits) {
      final s = _filterAmbiguous(_digits, opt.avoidAmbiguous);
      if (s.isNotEmpty) sets.add(s);
    }
    if (opt.symbols) {
      final s = _filterAmbiguous(_symbols, opt.avoidAmbiguous);
      if (s.isNotEmpty) sets.add(s);
    }

    return sets;
  }

  void _ensureNonEmptySet(String value, String name) {
    if (value.isEmpty) {
      throw ArgumentError('No usable characters left for $name after filtering');
    }
  }

  String _pickChar(String set) {
    if (set.isEmpty) {
      throw ArgumentError('Cannot pick from an empty character set');
    }
    return set[_rng.nextInt(set.length)];
  }

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
      if (!_ambiguousChars.contains(s[i])) {
        b.write(s[i]);
      }
    }
    return b.toString();
  }

  String _capitalize(String w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1);
  }

  double _entropyBits(int alphabetSize, int length) {
    if (alphabetSize <= 1 || length <= 0) return 0;
    return length * _log2(alphabetSize.toDouble());
  }

  double _log2(double x) => log(x) / ln2;
}

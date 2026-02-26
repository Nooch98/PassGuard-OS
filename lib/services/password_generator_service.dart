import 'dart:math';
import '../services/wordlist_service.dart';

enum GeneratorMode { random, diceware, pronounceable, pattern }

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
  final GeneratorMode mode;
  final Map<String, Object?> meta;
  const GeneratedPassword({
    required this.value,
    required this.entropyBits,
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

  static void setWordlist(List<String> words) {
    _externalWordlist = words;
  }

  static const Set<String> _ambiguousChars = {
    '0', 'O', 'o',
    '1', 'l', 'I',
    '5', 'S', 's',
    '2', 'Z', 'z',
    '8', 'B',
    '|', '/', '\\',
  };

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
    if (opt.length < 4) {
      throw ArgumentError('length too short');
    }

    final sets = <String>[];
    if (opt.upper) sets.add(_filterAmbiguous(_upper, opt.avoidAmbiguous));
    if (opt.lower) sets.add(_filterAmbiguous(_lower, opt.avoidAmbiguous));
    if (opt.digits) sets.add(_filterAmbiguous(_digits, opt.avoidAmbiguous));
    if (opt.symbols) sets.add(_filterAmbiguous(_symbols, opt.avoidAmbiguous));

    if (sets.isEmpty) {
      throw ArgumentError('Activate at least one set (upper/lower/digits/symbols)');
    }

    final pool = sets.join();
    if (pool.isEmpty) {
      throw StateError('The pool was empty (avoid overly aggressive or ambiguous comments)');
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

    return GeneratedPassword(
      value: value,
      entropyBits: entropy,
      mode: GeneratorMode.random,
      meta: {
        'poolSize': pool.length,
        'length': opt.length,
        'upper': opt.upper,
        'lower': opt.lower,
        'digits': opt.digits,
        'symbols': opt.symbols,
        'avoidAmbiguous': opt.avoidAmbiguous,
        'enforceAllSets': opt.enforceAllSets,
      },
    );
  }

  GeneratedPassword _generateDiceware(GeneratorOptions opt, List<String> wordlist) {
    if (opt.words < 3) {
      throw ArgumentError('Recommended Diceware >= 3 words');
    }
    if (wordlist.length < 256) {
      throw ArgumentError('Wordlist too small. Use >= 256 (ideally thousands).');
    }

    final picked = List<String>.generate(opt.words, (_) => wordlist[_rng.nextInt(wordlist.length)]);

    if (opt.dicewareCapitalize && picked.isNotEmpty) {
      final i = _rng.nextInt(picked.length);
      picked[i] = _capitalize(picked[i]);
    }

    String value = picked.join(opt.wordSeparator);

    int extrasPool = 0;
    if (opt.dicewareAddNumber) extrasPool += 10;
    if (opt.dicewareAddSymbol) extrasPool += _symbols.length;

    if (opt.dicewareAddNumber) {
      value += _digits[_rng.nextInt(_digits.length)];
    }
    if (opt.dicewareAddSymbol) {
      value += _symbols[_rng.nextInt(_symbols.length)];
    }

    final baseEntropy = opt.words * _log2(wordlist.length.toDouble());
    double extraEntropy = 0;
    if (extrasPool > 0) extraEntropy = _log2(extrasPool.toDouble());

    return GeneratedPassword(
      value: value,
      entropyBits: baseEntropy + extraEntropy,
      mode: GeneratorMode.diceware,
      meta: {
        'words': opt.words,
        'wordlistSize': wordlist.length,
        'separator': opt.wordSeparator,
        'capitalize': opt.dicewareCapitalize,
        'addNumber': opt.dicewareAddNumber,
        'addSymbol': opt.dicewareAddSymbol,
      },
    );
  }

  GeneratedPassword _generatePronounceable(GeneratorOptions opt) {
    if (opt.syllables < 2) {
      throw ArgumentError('recommended syllables >= 2');
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

    if (opt.pronounceableCapitalize && value.isNotEmpty) {
      final idx = _rng.nextInt(value.length);
      value = value.substring(0, idx) + value[idx].toUpperCase() + value.substring(idx + 1);
    }

    int extrasPool = 0;
    if (opt.pronounceableAddNumber) extrasPool += 10;
    if (opt.pronounceableAddSymbol) extrasPool += _symbols.length;

    if (opt.pronounceableAddNumber) value += _digits[_rng.nextInt(_digits.length)];
    if (opt.pronounceableAddSymbol) value += _symbols[_rng.nextInt(_symbols.length)];

    final perSyllable = consonants.length * vowels.length;
    final approxEntropy = opt.syllables * _log2(perSyllable.toDouble()) +
        (opt.syllables * 0.25 * _log2(consonants.length.toDouble())) +
        (opt.pronounceableCapitalize ? _log2(value.length.toDouble()) : 0) +
        (extrasPool > 0 ? _log2(extrasPool.toDouble()) : 0);

    return GeneratedPassword(
      value: value,
      entropyBits: approxEntropy,
      mode: GeneratorMode.pronounceable,
      meta: {
        'syllables': opt.syllables,
        'capitalize': opt.pronounceableCapitalize,
        'addNumber': opt.pronounceableAddNumber,
        'addSymbol': opt.pronounceableAddSymbol,
      },
    );
  }

  GeneratedPassword _generatePattern(GeneratorOptions opt) {
    final pattern = opt.pattern;
    if (pattern == null || pattern.trim().isEmpty) {
      throw ArgumentError('pattern required for pattern mode');
    }

    final out = StringBuffer();
    final poolParts = <String>[];
    if (opt.upper) poolParts.add(_filterAmbiguous(_upper, opt.avoidAmbiguous));
    if (opt.lower) poolParts.add(_filterAmbiguous(_lower, opt.avoidAmbiguous));
    if (opt.digits) poolParts.add(_filterAmbiguous(_digits, opt.avoidAmbiguous));
    if (opt.symbols) poolParts.add(_filterAmbiguous(_symbols, opt.avoidAmbiguous));
    final anyPool = poolParts.join();

    if (anyPool.isEmpty) {
      throw ArgumentError('To use "*", you must activate at least one set in options.');
    }

    int i = 0;
    while (i < pattern.length) {
      final ch = pattern[i];
      if (ch == r'\') {
        if (i + 1 < pattern.length) {
          out.write(pattern[i + 1]);
          i += 2;
          continue;
        } else {
          out.write(r'\');
          i++;
          continue;
        }
      }

      if (ch == '[') {
        final end = pattern.indexOf(']', i + 1);
        if (end == -1) {
          throw ArgumentError('Invalid pattern: missing "]"');
        }
        final setContent = pattern.substring(i + 1, end);
        if (setContent.isEmpty) {
          throw ArgumentError('Pattern inválido: [] vacío');
        }
        final filtered = _filterAmbiguous(setContent, opt.avoidAmbiguous);
        if (filtered.isEmpty) {
          throw ArgumentError('Invalid pattern: set was left empty by avoidAmbiguous');
        }
        out.write(_pickChar(filtered));
        i = end + 1;
        continue;
      }

      switch (ch) {
        case 'A':
          out.write(_pickChar(_filterAmbiguous(_upper, opt.avoidAmbiguous)));
          break;
        case 'a':
          out.write(_pickChar(_filterAmbiguous(_lower, opt.avoidAmbiguous)));
          break;
        case '9':
          out.write(_pickChar(_filterAmbiguous(_digits, opt.avoidAmbiguous)));
          break;
        case '#':
          out.write(_pickChar(_filterAmbiguous(_symbols, opt.avoidAmbiguous)));
          break;
        case '*':
          out.write(_pickChar(anyPool));
          break;
        default:
          out.write(ch);
      }

      i++;
    }

    final value = out.toString();

    double entropy = 0;
    i = 0;
    while (i < pattern.length) {
      final ch = pattern[i];
      if (ch == r'\') {
        i += (i + 1 < pattern.length) ? 2 : 1;
        continue;
      }
      if (ch == '[') {
        final end = pattern.indexOf(']', i + 1);
        if (end == -1) break;
        final setContent = pattern.substring(i + 1, end);
        final filtered = _filterAmbiguous(setContent, opt.avoidAmbiguous);
        entropy += _log2(filtered.length.toDouble());
        i = end + 1;
        continue;
      }
      switch (ch) {
        case 'A':
          entropy += _log2(_filterAmbiguous(_upper, opt.avoidAmbiguous).length.toDouble());
          break;
        case 'a':
          entropy += _log2(_filterAmbiguous(_lower, opt.avoidAmbiguous).length.toDouble());
          break;
        case '9':
          entropy += _log2(_filterAmbiguous(_digits, opt.avoidAmbiguous).length.toDouble());
          break;
        case '#':
          entropy += _log2(_filterAmbiguous(_symbols, opt.avoidAmbiguous).length.toDouble());
          break;
        case '*':
          entropy += _log2(anyPool.length.toDouble());
          break;
      }
      i++;
    }

    return GeneratedPassword(
      value: value,
      entropyBits: entropy,
      mode: GeneratorMode.pattern,
      meta: {
        'pattern': pattern,
        'avoidAmbiguous': opt.avoidAmbiguous,
        'anyPoolSize': anyPool.length,
      },
    );
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
      final ch = s[i];
      if (!_ambiguousChars.contains(ch)) b.write(ch);
    }
    return b.toString();
  }

  String _capitalize(String w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1);
  }

  double _entropyBits(int alphabetSize, int length) {
    return length * _log2(alphabetSize.toDouble());
  }

  double _log2(double x) => log(x) / ln2;
}

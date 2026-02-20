import 'dart:math';

class PasswordGeneratorConfig {
  final int length;
  final bool includeUppercase;
  final bool includeLowercase;
  final bool includeNumbers;
  final bool includeSymbols;
  final bool excludeAmbiguous;
  
  const PasswordGeneratorConfig({
    this.length = 16,
    this.includeUppercase = true,
    this.includeLowercase = true,
    this.includeNumbers = true,
    this.includeSymbols = true,
    this.excludeAmbiguous = false,
  });
}

class PasswordGeneratorService {
  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _numbers = '0123456789';
  static const String _symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
  static const String _ambiguous = 'il1Lo0O';
  
  static const List<String> _wordList = [
    'correct', 'horse', 'battery', 'staple', 'dragon', 'monkey', 'tiger',
    'mountain', 'river', 'ocean', 'forest', 'thunder', 'lightning', 'storm',
    'crystal', 'phoenix', 'shadow', 'silver', 'golden', 'diamond', 'ruby',
    'emerald', 'sapphire', 'quantum', 'cosmic', 'stellar', 'lunar', 'solar',
    'nebula', 'galaxy', 'comet', 'meteor', 'asteroid', 'planet', 'jupiter',
    'saturn', 'neptune', 'uranus', 'mercury', 'venus', 'eclipse', 'aurora',
    'cipher', 'enigma', 'paradox', 'infinity', 'zenith', 'apex', 'summit'
  ];

  static String generatePassword(PasswordGeneratorConfig config) {
    String chars = '';
    
    if (config.includeUppercase) chars += _uppercase;
    if (config.includeLowercase) chars += _lowercase;
    if (config.includeNumbers) chars += _numbers;
    if (config.includeSymbols) chars += _symbols;
    
    if (chars.isEmpty) {
      chars = _lowercase + _numbers;
    }
    
    if (config.excludeAmbiguous) {
      for (var char in _ambiguous.split('')) {
        chars = chars.replaceAll(char, '');
      }
    }
    
    final random = Random.secure();
    final password = List.generate(
      config.length,
      (i) => chars[random.nextInt(chars.length)]
    ).join();

    return _ensureComplexity(password, config, chars);
  }

  static String generatePassphrase({int wordCount = 4, String separator = '-'}) {
    final random = Random.secure();
    final words = List.generate(
      wordCount,
      (i) => _wordList[random.nextInt(_wordList.length)]
    );

    for (int i = 0; i < words.length; i++) {
      if (random.nextBool()) {
        words[i] = words[i][0].toUpperCase() + words[i].substring(1);
      }
    }

    final number = random.nextInt(9999);
    
    return '${words.join(separator)}$separator$number';
  }

  static String generatePin({int length = 6}) {
    final random = Random.secure();
    return List.generate(length, (i) => random.nextInt(10)).join();
  }

  static String _ensureComplexity(
    String password,
    PasswordGeneratorConfig config,
    String availableChars
  ) {
    final random = Random.secure();
    final chars = password.split('');
    
    if (config.includeUppercase && !password.contains(RegExp(r'[A-Z]'))) {
      chars[random.nextInt(chars.length)] = 
        _uppercase[random.nextInt(_uppercase.length)];
    }
    
    if (config.includeLowercase && !password.contains(RegExp(r'[a-z]'))) {
      chars[random.nextInt(chars.length)] = 
        _lowercase[random.nextInt(_lowercase.length)];
    }
    
    if (config.includeNumbers && !password.contains(RegExp(r'[0-9]'))) {
      chars[random.nextInt(chars.length)] = 
        _numbers[random.nextInt(_numbers.length)];
    }
    
    if (config.includeSymbols && 
        !password.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]'))) {
      chars[random.nextInt(chars.length)] = 
        _symbols[random.nextInt(_symbols.length)];
    }
    
    return chars.join();
  }

  static double calculateStrength(String password) {
    if (password.isEmpty) return 0;
    
    double score = 0;

    score += (password.length * 2).clamp(0, 40);
    
    // Character variety (max 40 points)
    if (password.contains(RegExp(r'[a-z]'))) score += 10;
    if (password.contains(RegExp(r'[A-Z]'))) score += 10;
    if (password.contains(RegExp(r'[0-9]'))) score += 10;
    if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) score += 10;

    final uniqueChars = password.split('').toSet().length;
    score += (uniqueChars / password.length * 20).clamp(0, 20);
    
    return score.clamp(0, 100);
  }

  static String getStrengthLabel(double strength) {
    if (strength >= 80) return 'VERY_STRONG';
    if (strength >= 60) return 'STRONG';
    if (strength >= 40) return 'MODERATE';
    if (strength >= 20) return 'WEAK';
    return 'VERY_WEAK';
  }
}

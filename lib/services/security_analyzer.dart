import '../models/password_model.dart';
import 'password_generator_service.dart';

class SecurityAnalysisResult {
  final int totalPasswords;
  final int weakPasswords;
  final int reusedPasswords;
  final int twoFactorEnabled;
  final int oldPasswords; // > 90 days
  final double overallScore;
  final Map<String, int> reuseMap;
  final List<PasswordModel> weakPasswordsList;
  final List<PasswordModel> oldPasswordsList;

  SecurityAnalysisResult({
    required this.totalPasswords,
    required this.weakPasswords,
    required this.reusedPasswords,
    required this.twoFactorEnabled,
    required this.oldPasswords,
    required this.overallScore,
    required this.reuseMap,
    required this.weakPasswordsList,
    required this.oldPasswordsList,
  });
}

class SecurityAnalyzer {
  static SecurityAnalysisResult analyze(List<PasswordModel> passwords) {
    if (passwords.isEmpty) {
      return SecurityAnalysisResult(
        totalPasswords: 0,
        weakPasswords: 0,
        reusedPasswords: 0,
        twoFactorEnabled: 0,
        oldPasswords: 0,
        overallScore: 100,
        reuseMap: {},
        weakPasswordsList: [],
        oldPasswordsList: [],
      );
    }

    int weakCount = 0;
    int twoFactorCount = 0;
    int oldCount = 0;
    
    Map<String, int> passwordOccurrences = {};
    List<PasswordModel> weakList = [];
    List<PasswordModel> oldList = [];
    
    final now = DateTime.now();
    
    for (var password in passwords) {
      if (password.otpSeed != null && password.otpSeed!.isNotEmpty) {
        twoFactorCount++;
      }

      passwordOccurrences[password.password] = 
        (passwordOccurrences[password.password] ?? 0) + 1;

      if (password.password.length < 44) {
        weakCount++;
        weakList.add(password);
      }

      if (password.createdAt != null) {
        final age = now.difference(password.createdAt!);
        if (age.inDays > 90) {
          oldCount++;
          oldList.add(password);
        }
      }
    }
    
    int reuseCount = 0;
    passwordOccurrences.forEach((key, count) {
      if (count > 1) reuseCount += count;
    });

    double score = _calculateScore(
      total: passwords.length,
      weak: weakCount,
      reused: reuseCount,
      twoFactor: twoFactorCount,
      old: oldCount,
    );
    
    return SecurityAnalysisResult(
      totalPasswords: passwords.length,
      weakPasswords: weakCount,
      reusedPasswords: reuseCount,
      twoFactorEnabled: twoFactorCount,
      oldPasswords: oldCount,
      overallScore: score,
      reuseMap: passwordOccurrences,
      weakPasswordsList: weakList,
      oldPasswordsList: oldList,
    );
  }

  static double _calculateScore({
    required int total,
    required int weak,
    required int reused,
    required int twoFactor,
    required int old,
  }) {
    double score = 100;
    score -= (weak / total * 30).clamp(0, 30);
    score -= (reused / total * 30).clamp(0, 30);
    score -= (old / total * 20).clamp(0, 20);
    score += (twoFactor / total * 20).clamp(0, 20);
    return score.clamp(0, 100);
  }

  static String getRecommendation(SecurityAnalysisResult result) {
    if (result.overallScore >= 90) {
      return 'EXCELLENT_SECURITY: MAINTAIN_CURRENT_PRACTICES';
    } else if (result.overallScore >= 70) {
      return 'GOOD_SECURITY: CONSIDER_ENABLING_MORE_2FA';
    } else if (result.overallScore >= 50) {
      return 'MODERATE_SECURITY: UPDATE_WEAK_PASSWORDS';
    } else {
      return 'CRITICAL: IMMEDIATE_ACTION_REQUIRED';
    }
  }
}

import '../models/password_model.dart';

class SecurityAnalysisResult {
  final int totalPasswords;
  final int weakPasswords;
  final int reusedPasswords;
  final int twoFactorEnabled;
  final int oldPasswords;
  final double overallScore;

  final Map<String, int> reuseMap;

  final List<PasswordModel> weakPasswordsList;
  final List<PasswordModel> oldPasswordsList;
  final List<PasswordModel> reusedPasswordsList;

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
    required this.reusedPasswordsList,
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
        reusedPasswordsList: [],
      );
    }

    int weakCount = 0;
    int twoFactorCount = 0;
    int oldCount = 0;

    final Map<String, int> fpOccurrences = {};
    final Map<String, List<PasswordModel>> fpGroups = {};

    final List<PasswordModel> weakList = [];
    final List<PasswordModel> oldList = [];

    final now = DateTime.now();

    for (final p in passwords) {
      if (p.otpSeed != null && p.otpSeed!.isNotEmpty) {
        twoFactorCount++;
      }

      if (p.password.length < 44) {
        weakCount++;
        weakList.add(p);
      }

      if (p.createdAt != null) {
        final age = now.difference(p.createdAt!);
        if (age.inDays > 90) {
          oldCount++;
          oldList.add(p);
        }
      }

      final fp = p.passwordFingerprint;
      if (fp == null || fp.isEmpty) continue;

      fpOccurrences[fp] = (fpOccurrences[fp] ?? 0) + 1;
      (fpGroups[fp] ??= []).add(p);
    }

    int reuseCount = 0;
    final List<PasswordModel> reusedList = [];

    fpGroups.forEach((_, list) {
      if (list.length > 1) {
        reuseCount += list.length;
        reusedList.addAll(list);
      }
    });

    final score = _calculateScore(
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
      reuseMap: fpOccurrences,
      weakPasswordsList: weakList,
      oldPasswordsList: oldList,
      reusedPasswordsList: reusedList,
    );
  }

  static double _calculateScore({
    required int total,
    required int weak,
    required int reused,
    required int twoFactor,
    required int old,
  }) {
    if (total <= 0) return 100;

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

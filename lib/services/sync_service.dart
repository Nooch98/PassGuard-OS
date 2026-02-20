import 'dart:convert';
import '../models/password_model.dart';
import '../models/recovery_code_model.dart';
import 'db_helper.dart';

class SyncService {
  static Future<String> exportToPackage(List<PasswordModel> passwords) async {
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> recoveryCodesRows = await db.query('recovery_codes');
    final Map<String, dynamic> vaultData = {
      'accounts': passwords.map((p) => p.toMap()).toList(),
      'recovery_codes': recoveryCodesRows,
      'exported_at': DateTime.now().toIso8601String(),
      'version': '2.0',
    };
    
    return jsonEncode(vaultData);
  }

  static SyncImportResult importFromPackage(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      List<PasswordModel> passwords;
      List<RecoveryCodeModel> recoveryCodes = [];
      
      if (decoded is Map<String, dynamic> && decoded.containsKey('accounts')) {
        final List<dynamic> accountsData = decoded['accounts'];
        passwords = accountsData.map((item) => PasswordModel.fromMap(item)).toList();
        
        if (decoded.containsKey('recovery_codes')) {
          final List<dynamic> codesData = decoded['recovery_codes'];
          recoveryCodes = codesData.map((item) => RecoveryCodeModel.fromMap(item)).toList();
        }
      } else {
        final List<dynamic> accountsData = decoded as List<dynamic>;
        passwords = accountsData.map((item) => PasswordModel.fromMap(item)).toList();
      }
      
      return SyncImportResult(
        passwords: passwords,
        recoveryCodes: recoveryCodes,
        success: true,
      );
    } catch (e) {
      return SyncImportResult(
        passwords: [],
        recoveryCodes: [],
        success: false,
        error: e.toString(),
      );
    }
  }

  @Deprecated('Use exportToPackage instead')
  static String exportAccountsOnly(List<PasswordModel> passwords) {
    return jsonEncode(passwords.map((p) => p.toMap()).toList());
  }
}

class SyncImportResult {
  final List<PasswordModel> passwords;
  final List<RecoveryCodeModel> recoveryCodes;
  final bool success;
  final String? error;

  SyncImportResult({
    required this.passwords,
    required this.recoveryCodes,
    required this.success,
    this.error,
  });
}

/*
|--------------------------------------------------------------------------
| PassGuard OS - SyncService (Vault Export / Import Subsystem)
|--------------------------------------------------------------------------
| Description:
|   Handles vault serialization and deserialization for backup,
|   migration, and cross-device transfer.
|
|   This service packages stored password entries and recovery codes
|   into a structured JSON payload (Sync Package v2.0).
|
| Export Format (v2.0):
|   {
|     "accounts": [ ...PasswordModel.toMap() ],
|     "recovery_codes": [ ...DB rows ],
|     "exported_at": ISO8601 timestamp,
|     "version": "2.0"
|   }
|
| Import Logic:
|   - Detects structured package (Map with "accounts" key)
|   - Parses accounts → PasswordModel
|   - Parses recovery_codes → RecoveryCodeModel
|   - Supports legacy format (List of accounts only)
|   - Returns SyncImportResult with success/error state
|
| Important:
|   - This service performs serialization ONLY.
|   - Encryption, compression, QR encoding, or steganography
|     must be handled by upper layers before storage/transport.
|
| Backward Compatibility:
|   - Supports legacy account-only export format
|   - exportAccountsOnly() is deprecated in favor of full package export
|
| Threat model assumptions:
|   - Exported JSON will be encrypted before external storage.
|   - Transport channel is not inherently trusted.
|   - Imported data is validated at higher layers if needed.
|
| What this service does NOT protect against:
|   - Plaintext exposure if exported JSON is stored unencrypted
|   - Tampering of the JSON payload before import
|   - Malicious data injection without external validation
|   - Replay attacks or package authenticity verification
|
| Security Recommendations:
|   - Always encrypt export packages with EncryptionService before sharing.
|   - Optionally sign packages (HMAC / signature) for integrity.
|   - Avoid storing raw JSON backups in cloud storage.
|
| Purpose:
|   Provide deterministic, portable vault backup format while
|   keeping cryptographic responsibilities separated.
|
|--------------------------------------------------------------------------
*/

import 'dart:convert';
import 'dart:typed_data';
import 'package:passguard/services/encryption_service.dart';
import '../models/password_model.dart';
import '../models/recovery_code_model.dart';
import 'db_helper.dart';

class SyncService {
  static Future<String> exportSecurePackage(
    List<PasswordModel> passwords, 
    Uint8List currentMasterKey 
  ) async {
    final String rawJson = await _serializeToJSON(passwords);

    return EncryptionService.encrypt(rawJson, currentMasterKey);
  }

  static Future<SyncImportResult> importSecurePackage(
    String encryptedData, 
    Uint8List currentMasterKey
  ) async {
    try {
      final decryptedJson = EncryptionService.decrypt(
        combinedText: encryptedData,
        masterKeyBytes: currentMasterKey,
      );

      if (decryptedJson.startsWith("ERROR:")) {
        return SyncImportResult(
          passwords: [], 
          recoveryCodes: [], 
          success: false, 
          error: "MASTER_KEY_MISMATCH_OR_CORRUPTED"
        );
      }

      return importFromPackage(decryptedJson);
    } catch (e) {
      return SyncImportResult(
        passwords: [], 
        recoveryCodes: [], 
        success: false, 
        error: "DECRYPTION_FAILED: ${e.toString()}"
      );
    }
  }

  static Future<String> _serializeToJSON(List<PasswordModel> passwords) async {
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> recoveryCodesRows = await db.query('recovery_codes');
    
    final Map<String, dynamic> vaultData = {
      'accounts': passwords.map((p) => p.toMap()).toList(),
      'recovery_codes': recoveryCodesRows,
      'exported_at': DateTime.now().toIso8601String(),
      'version': '2.0-mirror',
    };
    
    return jsonEncode(vaultData);
  }

  static SyncImportResult importFromPackage(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      List<PasswordModel> passwords = [];
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
        error: "JSON_PARSE_ERROR: ${e.toString()}",
      );
    }
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

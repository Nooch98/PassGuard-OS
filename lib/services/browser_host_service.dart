import 'dart:io';
import 'dart:typed_data';

import 'db_helper.dart';
import 'encryption_service.dart';
import 'session_manager.dart';
import 'session_service.dart';

class BrowserHostService {
  static final BrowserHostService instance = BrowserHostService._internal();
  BrowserHostService._internal();

  static final File _logFile =
      File('${Directory.systemTemp.path}\\passguard_browser_host.log');

  Future<void> _log(String message) async {
    try {
      final line =
          '[${DateTime.now().toIso8601String()}] $message${Platform.lineTerminator}';
      await _logFile.writeAsString(
        line,
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> handleRequest(Map<String, dynamic> request) async {
    final String action = (request['action'] ?? '').toString().trim();

    switch (action) {
      case 'status':
        return _handleStatus();

      case 'lock_now':
        return _handleLockNow();

      case 'get_credentials':
        return _handleGetCredentials(request);

      default:
        return {
          'status': 'error',
          'message': 'unknown_action',
        };
    }
  }

  Map<String, dynamic> _handleStatus() {
    final remaining = SessionManager().remainingTime;

    return {
      'status': 'ok',
      'session_active': SessionService.instance.isSessionActive,
      'ui_locked': SessionService.instance.isUiLocked,
      'remaining_seconds': remaining?.inSeconds ?? 0,
    };
  }

  Future<Map<String, dynamic>> _handleLockNow() async {
    SessionService.instance.hardLock();
    SessionManager().dispose();

    return {
      'status': 'ok',
      'message': 'vault_locked',
    };
  }

  Future<Map<String, dynamic>> _handleGetCredentials(
    Map<String, dynamic> request,
  ) async {
    final sw = Stopwatch()..start();

    if (!SessionService.instance.isSessionActive) {
      return {
        'status': 'locked',
        'message': 'vault_locked',
      };
    }

    final String origin = (request['origin'] ?? '').toString().trim();
    if (origin.isEmpty) {
      return {
        'status': 'error',
        'message': 'origin_required',
      };
    }

    final Uint8List? masterKeyBytes = SessionService.instance.masterKeyBytesCopy;
    if (masterKeyBytes == null || masterKeyBytes.isEmpty) {
      return {
        'status': 'locked',
        'message': 'session_key_missing',
      };
    }

    final String normalizedOrigin = _normalizeOrigin(origin);
    final List<String> originTokens = _tokenizeHost(normalizedOrigin);

    await _log('GET_CREDENTIALS origin=$origin normalized=$normalizedOrigin');

    final db = await DBHelper.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'accounts',
      orderBy: 'is_favorite DESC, last_used DESC, updated_at DESC, id DESC',
    );

    final List<Map<String, dynamic>> matches = [];

    for (final row in rows) {
      final String? platform = _readMaybeEncryptedText(
        row['platform'],
        masterKeyBytes,
      );

      if (platform == null || platform.trim().isEmpty) continue;

      final bool matched = _matchesService(
        normalizedOrigin: normalizedOrigin,
        originTokens: originTokens,
        platformValue: platform,
      );

      if (!matched) continue;

      final String? username = _readMaybeEncryptedText(
        row['username'],
        masterKeyBytes,
      );

      final String? password = _readMaybeEncryptedText(
        row['password'],
        masterKeyBytes,
      );

      final String? otpSeed = _readMaybeEncryptedText(
        row['otp_seed'],
        masterKeyBytes,
      );

      final String? category = _readMaybeEncryptedText(
        row['category'],
        masterKeyBytes,
        allowPlainFallback: true,
      );

      if ((username?.isEmpty ?? true) && (password?.isEmpty ?? true)) {
        continue;
      }

      matches.add({
        'id': row['id'],
        'title': platform,
        'origin': normalizedOrigin,
        'username': username ?? '',
        'password': password ?? '',
        'totp': otpSeed ?? '',
        'favorite': _safeInt(row['is_favorite']) == 1,
        'category': category ?? '',
      });
    }

    SessionManager().activity();

    await _log(
      'GET_CREDENTIALS_DONE count=${matches.length} elapsed=${sw.elapsedMilliseconds}ms',
    );

    return {
      'status': 'ok',
      'count': matches.length,
      'credentials': matches,
    };
  }

  String? _readMaybeEncryptedText(
    Object? rawValue,
    Uint8List masterKeyBytes, {
    bool allowPlainFallback = true,
  }) {
    if (rawValue == null) return null;

    final String text = rawValue.toString().trim();
    if (text.isEmpty) return null;

    if (_looksEncrypted(text)) {
      final String decrypted = EncryptionService.decrypt(
        combinedText: text,
        masterKeyBytes: masterKeyBytes,
      );

      if (decrypted.startsWith('ERROR:')) {
        return null;
      }

      return decrypted;
    }

    return allowPlainFallback ? text : null;
  }

  bool _looksEncrypted(String value) {
    return value.startsWith('v4.') ||
        value.startsWith('v3.') ||
        value.startsWith('v2.');
  }

  bool _matchesService({
    required String normalizedOrigin,
    required List<String> originTokens,
    required String platformValue,
  }) {
    final String raw = platformValue.trim().toLowerCase();
    if (raw.isEmpty) return false;

    final String normalizedPlatform = _normalizeOrigin(raw);
    final List<String> platformTokens = _tokenizeHost(raw);

    if (normalizedPlatform.isNotEmpty && normalizedPlatform == normalizedOrigin) {
      return true;
    }

    if (normalizedPlatform.isNotEmpty &&
        (normalizedOrigin.endsWith('.$normalizedPlatform') ||
            normalizedPlatform.endsWith('.$normalizedOrigin'))) {
      return true;
    }

    final RegExp hostRegex = RegExp(
      r'([a-z0-9-]+\.)+[a-z]{2,}',
      caseSensitive: false,
    );

    for (final match in hostRegex.allMatches(raw)) {
      final host = _normalizeOrigin(match.group(0) ?? '');
      if (host.isEmpty) continue;

      if (host == normalizedOrigin ||
          normalizedOrigin.endsWith('.$host') ||
          host.endsWith('.$normalizedOrigin')) {
        return true;
      }
    }

    int common = 0;
    for (final token in platformTokens) {
      if (originTokens.contains(token)) {
        common++;
      }
    }

    if (common >= 1 && platformTokens.isNotEmpty && originTokens.isNotEmpty) {
      return true;
    }

    if (raw.contains(normalizedOrigin) || normalizedOrigin.contains(raw)) {
      return true;
    }

    return false;
  }

  String _normalizeOrigin(String raw) {
    String value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';

    if (value.startsWith('http://')) value = value.substring(7);
    if (value.startsWith('https://')) value = value.substring(8);
    if (value.startsWith('www.')) value = value.substring(4);

    final int slashIndex = value.indexOf('/');
    if (slashIndex != -1) value = value.substring(0, slashIndex);

    final int queryIndex = value.indexOf('?');
    if (queryIndex != -1) value = value.substring(0, queryIndex);

    final int hashIndex = value.indexOf('#');
    if (hashIndex != -1) value = value.substring(0, hashIndex);

    final int colonIndex = value.indexOf(':');
    if (colonIndex != -1) value = value.substring(0, colonIndex);

    return value.trim();
  }

  List<String> _tokenizeHost(String raw) {
    final String cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'https?://'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    if (cleaned.isEmpty) return const [];

    final List<String> tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty && e.length > 2)
        .toList();

    const stopwords = {
      'www',
      'com',
      'net',
      'org',
      'app',
      'login',
      'account',
      'accounts',
      'secure',
      'auth',
      'the',
    };

    return tokens.where((t) => !stopwords.contains(t)).toSet().toList();
  }

  int? _safeInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}

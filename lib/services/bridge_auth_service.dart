import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class BridgeAuthService {
  BridgeAuthService._();

  static final BridgeAuthService instance = BridgeAuthService._();

  String? _token;

  String get token => _token ?? '';

  Future<void> initialize() async {
    final file = await _tokenFile();

    if (await file.exists()) {
      final existingToken = await file.readAsString();
      if (existingToken.trim().isNotEmpty) {
        _token = existingToken.trim();
        return;
      }
    }

    _token = _generateToken();
    await file.parent.create(recursive: true);
    await file.writeAsString(_token!, flush: true);

    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['600', file.path]);
    }
  }

  bool isValid(String? incomingToken) {
    if (_token == null || incomingToken == null) return false;

    final incomingBytes = utf8.encode(incomingToken);
    final validBytes = utf8.encode(_token!);
    
    if (incomingBytes.length != validBytes.length) return false;

    int result = 0;
    for (int i = 0; i < incomingBytes.length; i++) {
      result |= incomingBytes[i] ^ validBytes[i];
    }
    return result == 0;
  }

  Future<void> rotate() async {
    await initialize();
  }

  Future<void> clear() async {
    _token = null;
    final file = await _tokenFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<String?> readTokenForHost() async {
    final file = await instance._tokenFile();
    if (!await file.exists()) return null;

    final value = await file.readAsString();
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _generateToken() {
    final r = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = r.nextInt(256);
    }
    return base64UrlEncode(bytes);
  }

  Future<File> _tokenFile() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/bridge_token');
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
      return File('$appData\\PassGuardOS\\bridge_token');
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      return File('$home/.config/PassGuardOS/bridge_token');
    }

    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/.passguard_bridge_token');
  }
}

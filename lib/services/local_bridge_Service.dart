/*
|--------------------------------------------------------------------------
| PassGuard OS - Local Bridge Service
|--------------------------------------------------------------------------
| Local IPC bridge between:
| - Native Messaging Host
| - PassGuard Flutter App
|
| Protocol:
| JSON per line (request/response)
|
| Security:
| - Bound to 127.0.0.1 only
| - Bridge token required
|--------------------------------------------------------------------------
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bridge_auth_service.dart';
import 'browser_host_service.dart';

class LocalBridgeService {
  LocalBridgeService._();

  static ServerSocket? _server;
  static bool _started = false;

  static const String host = '127.0.0.1';
  static const int port = 45491;

  static final File _logFile =
      File('${Directory.systemTemp.path}\\passguard_local_bridge.log');

  static Future<void> _log(String message) async {
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

  static bool get isRunning => _server != null;

  static Future<void> start() async {
    if (_started && _server != null) return;

    _server = await ServerSocket.bind(host, port, shared: false);
    _started = true;

    await _log('BRIDGE_STARTED $host:$port');

    _server!.listen(
      _handleClient,
      onError: (Object error, StackTrace stackTrace) async {
        await _log('BRIDGE_SERVER_ERROR $error');
      },
      onDone: () async {
        await _log('BRIDGE_SERVER_DONE');
        _server = null;
        _started = false;
      },
      cancelOnError: false,
    );
  }

  static Future<void> stop() async {
    await _log('BRIDGE_STOP');

    try {
      await _server?.close();
    } catch (_) {}

    _server = null;
    _started = false;
  }

  static Future<void> _handleClient(Socket client) async {
    final sw = Stopwatch()..start();

    try {
      await _log('BRIDGE_CLIENT_CONNECTED');

      final String requestText = await utf8.decoder
          .bind(client)
          .transform(const LineSplitter())
          .first;

      await _log('BRIDGE_REQUEST_RAW $requestText');

      if (requestText.trim().isEmpty) {
        await _writeResponse(client, {
          'status': 'error',
          'message': 'empty_request',
        });
        return;
      }

      final dynamic decoded = jsonDecode(requestText);

      if (decoded is! Map<String, dynamic>) {
        await _writeResponse(client, {
          'status': 'error',
          'message': 'invalid_request_format',
        });
        return;
      }

      final String? bridgeToken = decoded['bridge_token']?.toString();
      if (!BridgeAuthService.instance.isValid(bridgeToken)) {
        await _log('BRIDGE_UNAUTHORIZED');
        await _writeResponse(client, {
          'status': 'error',
          'message': 'unauthorized_bridge_client',
        });
        return;
      }

      final dynamic payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) {
        await _writeResponse(client, {
          'status': 'error',
          'message': 'invalid_payload',
        });
        return;
      }

      final Map<String, dynamic> response =
          await BrowserHostService.instance.handleRequest(payload);

      await _log(
        'BRIDGE_RESPONSE in ${sw.elapsedMilliseconds}ms -> $response',
      );

      await _writeResponse(client, response);
    } catch (e) {
      await _log('BRIDGE_HANDLE_ERROR $e');

      await _writeResponse(client, {
        'status': 'error',
        'message': 'bridge_request_failed',
        'details': e.toString(),
      });
    } finally {
      try {
        await client.flush();
      } catch (_) {}

      try {
        await client.close();
      } catch (_) {}
    }
  }

  static Future<void> _writeResponse(
    Socket client,
    Map<String, dynamic> payload,
  ) async {
    final String responseJson = jsonEncode(payload);
    client.writeln(responseJson);
  }
}

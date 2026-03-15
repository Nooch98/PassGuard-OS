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


  static bool get isRunning => _server != null;

  static Future<void> start() async {
    if (_started && _server != null) return;

    _server = await ServerSocket.bind(host, port, shared: false);
    _started = true;

    _server!.listen(
      _handleClient,
      onError: (Object error, StackTrace stackTrace) async {
      },
      onDone: () async {
        _server = null;
        _started = false;
      },
      cancelOnError: false,
    );
  }

  static Future<void> stop() async {

    try {
      await _server?.close();
    } catch (_) {}

    _server = null;
    _started = false;
  }

  static Future<void> _handleClient(Socket client) async {
    try {
      final String requestText = await utf8.decoder
          .bind(client)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => "");

      if (requestText.trim().isEmpty) {
        await _writeResponse(client, {'status': 'error', 'message': 'timeout_or_empty'});
        return;
      }

      final dynamic decoded = jsonDecode(requestText);
      if (decoded is! Map<String, dynamic>) {
        await _writeResponse(client, {'status': 'error', 'message': 'invalid_format'});
        return;
      }

      final String? bridgeToken = decoded['bridge_token']?.toString();
      if (!BridgeAuthService.instance.isValid(bridgeToken)) {
        await _writeResponse(client, {'status': 'error', 'message': 'unauthorized'});
        return;
      }

      final dynamic payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) {
        await _writeResponse(client, {'status': 'error', 'message': 'invalid_payload'});
        return;
      }

      final Map<String, dynamic> response = await BrowserHostService.instance.handleRequest(payload);
      
      await _writeResponse(client, response);
      
    } catch (e) {
      await _writeResponse(client, {
        'status': 'error',
        'message': 'bridge_request_failed',
        'details': e.toString(),
      });
    } finally {
      client.destroy();
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

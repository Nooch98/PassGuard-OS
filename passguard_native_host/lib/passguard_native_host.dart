/*
|--------------------------------------------------------------------------
| PassGuard OS - Native Messaging Host Service
|--------------------------------------------------------------------------
| Native host for Chromium-based browsers.
|
| Responsibilities:
| - Read length-prefixed JSON from stdin
| - Forward request to PassGuard local bridge
| - Return length-prefixed JSON to stdout
|
| Security:
| - No network exposure beyond 127.0.0.1 loopback
| - No direct vault access here
| - No session material stored here
|--------------------------------------------------------------------------
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class NativeMessService {
  NativeMessService._();

  static bool _started = false;

  static const String _bridgeHost = '127.0.0.1';
  static const int _bridgePort = 45491;

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    stdin
        .cast<List<int>>()
        .transform(_NativeMessageTransformer())
        .listen(
      (Uint8List rawMessage) async {
        await _handleRawMessage(rawMessage);
      },
      onError: (Object error, StackTrace stackTrace) async {
        await _writeJson({
          'status': 'error',
          'message': 'stdin_stream_error',
          'details': error.toString(),
        });
      },
      onDone: () async {
        exit(0);
      },
      cancelOnError: false,
    );
  }

  static Future<void> _handleRawMessage(Uint8List rawMessage) async {
    try {
      final String jsonString = utf8.decode(rawMessage);
      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map<String, dynamic>) {
        await _writeJson({
          'status': 'error',
          'message': 'invalid_request_format',
        });
        return;
      }

      final Map<String, dynamic> response = await _forwardToBridge(decoded);
      await _writeJson(response);
    } catch (e) {
      await _writeJson({
        'status': 'error',
        'message': 'request_processing_failed',
        'details': e.toString(),
      });
    }
  }

  static Future<String?> _readBridgeToken() async {
    try {
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ??
            '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';

        final file = File('$appData\\PassGuardOS\\bridge_token');
        if (!await file.exists()) return null;

        final value = (await file.readAsString()).trim();
        return value.isEmpty ? null : value;
      }

      if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '.';
        final file = File('$home/.config/PassGuardOS/bridge_token');

        if (!await file.exists()) return null;

        final value = (await file.readAsString()).trim();
        return value.isEmpty ? null : value;
      }

      final home = Platform.environment['HOME'] ?? '.';
      final file = File('$home/.passguard_bridge_token');

      if (!await file.exists()) return null;

      final value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _forwardToBridge(
    Map<String, dynamic> request,
  ) async {
    Socket? socket;

    try {
      final String? token = await _readBridgeToken();
      if (token == null || token.isEmpty) {
        return {
          'status': 'error',
          'message': 'bridge_token_missing',
        };
      }

      socket = await Socket.connect(
        _bridgeHost,
        _bridgePort,
        timeout: const Duration(seconds: 2),
      );

      final Map<String, dynamic> wrappedRequest = {
        'bridge_token': token,
        'payload': request,
      };

      socket.writeln(jsonEncode(wrappedRequest));
      await socket.flush();

      final String responseText = await utf8.decoder
          .bind(socket.timeout(const Duration(seconds: 10)))
          .transform(const LineSplitter())
          .first;

      if (responseText.trim().isEmpty) {
        return {
          'status': 'error',
          'message': 'empty_bridge_response',
        };
      }

      final dynamic decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) {
        return {
          'status': 'error',
          'message': 'invalid_bridge_response',
        };
      }

      return decoded;
    } on SocketException {
      return {
        'status': 'error',
        'message': 'passguard_app_unreachable',
      };
    } on TimeoutException {
      return {
        'status': 'error',
        'message': 'bridge_timeout',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': 'bridge_forward_failed',
        'details': e.toString(),
      };
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  static Future<void> _writeJson(Map<String, dynamic> payload) async {
    final String jsonString = jsonEncode(payload);
    final Uint8List body = Uint8List.fromList(utf8.encode(jsonString));

    final ByteData header = ByteData(4);
    header.setUint32(0, body.lengthInBytes, Endian.little);

    final List<int> packet = <int>[
      ...header.buffer.asUint8List(),
      ...body,
    ];

    stdout.add(packet);
    await stdout.flush();
  }
}

class _NativeMessageTransformer
    extends StreamTransformerBase<List<int>, Uint8List> {
  @override
  Stream<Uint8List> bind(Stream<List<int>> stream) {
    late StreamController<Uint8List> controller;
    final List<int> buffer = <int>[];

    controller = StreamController<Uint8List>(
      onListen: () {
        stream.listen(
          (List<int> chunk) {
            buffer.addAll(chunk);

            while (true) {
              if (buffer.length < 4) return;

              final Uint8List headerBytes =
                  Uint8List.fromList(buffer.sublist(0, 4));
              final ByteData headerData = ByteData.sublistView(headerBytes);
              final int messageLength =
                  headerData.getUint32(0, Endian.little);

              if (messageLength <= 0) {
                controller.addError(
                  StateError('Invalid native message length'),
                );
                return;
              }

              if (buffer.length < 4 + messageLength) return;

              final Uint8List message = Uint8List.fromList(
                buffer.sublist(4, 4 + messageLength),
              );

              buffer.removeRange(0, 4 + messageLength);
              controller.add(message);
            }
          },
          onError: controller.addError,
          onDone: controller.close,
          cancelOnError: false,
        );
      },
    );

    return controller.stream;
  }
}
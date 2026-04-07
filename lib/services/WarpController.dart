import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:passguard/models/password_model.dart';
import 'package:passguard/services/sync_service.dart';

class WarpController {
  ServerSocket? _server;
  Socket? _clientSocket;
  bool isTransferring = false;
  static const int _warpPort = 8888;

  Future<void> startHost({
    required List<PasswordModel> passwords,
    required Uint8List masterKey,
    required Function(String) onStatusUpdate,
    required Function(bool) onFinished,
  }) async {
    try {
      onStatusUpdate("PREPARING_ENCRYPTED_WARP_PACKAGE...");
      final String warpPayload = await SyncService.generateWarpPackage(passwords, masterKey);
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _warpPort);
      onStatusUpdate("LISTENING_ON_PORT_$_warpPort...");

      _server!.listen((Socket client) async {
        _clientSocket = client;
        onStatusUpdate("NODE_CONNECTED: ${client.remoteAddress.address}");

        isTransferring = true;
        client.write(warpPayload);
        await client.flush();
        
        onStatusUpdate("TRANSMISSION_COMPLETE");
        await Future.delayed(const Duration(seconds: 1));
        
        stop();
        onFinished(true);
      });
    } catch (e) {
      onStatusUpdate("ERROR: ${e.toString()}");
      onFinished(false);
    }
  }

  Future<void> startClient({
    required String hostIp,
    required Uint8List myMasterKey,
    required Function(String) onStatusUpdate,
    required Function(SyncImportResult) onDataReceived,
  }) async {
    try {
      onStatusUpdate("CONNECTING_TO_HOST: $hostIp...");
      final socket = await Socket.connect(hostIp, _warpPort, timeout: const Duration(seconds: 10));
      
      StringBuffer buffer = StringBuffer();
      
      socket.listen(
        (Uint8List data) {
          buffer.write(utf8.decode(data));
          onStatusUpdate("RECEIVING_DATA_STREAM...");
        },
        onDone: () async {
          onStatusUpdate("DECODING_AND_RE_ENCRYPTING...");

          final result = await SyncService.processWarpPackage(buffer.toString(), myMasterKey);
          
          socket.destroy();
          onDataReceived(result);
        },
        onError: (e) => onStatusUpdate("CONNECTION_LOST"),
      );
    } catch (e) {
      onStatusUpdate("FAILED_TO_CONNECT: ${e.toString()}");
    }
  }

  void stop() {
    _clientSocket?.destroy();
    _server?.close();
    _server = null;
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

Uint8List _sha256Bytes(Uint8List data) =>
    Uint8List.fromList(crypto.sha256.convert(data).bytes);

Uint8List derivePepper(Uint8List masterKeyBytes) {
  final tag = utf8.encode('passguard-password-fp-v1');
  return _sha256Bytes(Uint8List.fromList([...masterKeyBytes, ...tag]));
}

String passwordFingerprintBase64({
  required String passwordPlaintext,
  required Uint8List pepper,
}) {
  final h = crypto.Hmac(crypto.sha256, pepper);
  final mac = h.convert(utf8.encode(passwordPlaintext)).bytes;
  return base64Encode(mac);
}

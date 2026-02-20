import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'db_helper.dart';
import 'dart:convert';

class FileService {

  static encrypt.Key _deriveKey(Uint8List masterKey) {
    final String keyString = utf8.decode(masterKey);
    return encrypt.Key.fromUtf8(keyString.padRight(32, '0').substring(0, 32));
  }

  static Future<void> exportFile(String encryptedPath, Uint8List masterKey, String originalName) async {
    final key = _deriveKey(masterKey);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final File encryptedFile = File(encryptedPath);
    final Uint8List allBytes = await encryptedFile.readAsBytes();
    final iv = encrypt.IV(allBytes.sublist(0, 16));
    final cipherText = allBytes.sublist(16);
    final decryptedBytes = encrypter.decryptBytes(encrypt.Encrypted(cipherText), iv: iv);


    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
    } else {
      downloadsDir = await getDownloadsDirectory();
    }

    final String outputPath = p.join(downloadsDir!.path, "DECRYPTED_$originalName");
    final File outputFile = File(outputPath);
    await outputFile.writeAsBytes(decryptedBytes);
  }

  static Future<void> importAndEncryptFile(File sourceFile, Uint8List masterKey) async {
    final db = await DBHelper.database;
    final key = _deriveKey(masterKey);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDir.path, 'vault_storage'));
    if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

    final String encryptedFileName = "${DateTime.now().millisecondsSinceEpoch}.bin";
    final String targetPath = p.join(vaultDir.path, encryptedFileName);

    final bytes = await sourceFile.readAsBytes();
    final encryptedData = encrypter.encryptBytes(bytes, iv: iv);

    final File encryptedFile = File(targetPath);
    await encryptedFile.writeAsBytes(iv.bytes + encryptedData.bytes);

    await db.insert('file_vault', {
      'file_name': p.basename(sourceFile.path),
      'encrypted_path': targetPath,
      'file_size': await sourceFile.length(),
      'mime_type': _getMimeType(sourceFile.path),
      'created_at': DateTime.now().toIso8601String(),
    });

    await sourceFile.delete();
  }

  static Future<File> decryptFile(String encryptedPath, Uint8List masterKey, String originalName) async {
    final key = _deriveKey(masterKey);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final File encryptedFile = File(encryptedPath);
    final Uint8List allBytes = await encryptedFile.readAsBytes();
    final iv = encrypt.IV(allBytes.sublist(0, 16));
    final cipherText = allBytes.sublist(16);
    final decryptedBytes = encrypter.decryptBytes(encrypt.Encrypted(cipherText), iv: iv);
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, originalName));
    return await tempFile.writeAsBytes(decryptedBytes);
  }

  static String _getMimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.pdf': return 'application/pdf';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default: return 'application/octet-stream';
    }
  }
}

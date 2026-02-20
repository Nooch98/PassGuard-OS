import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

class CompressionService {
  static Uint8List compressBytes(String data) {
    final bytes = utf8.encode(data);
    final compressed = GZipEncoder().encode(bytes);
    
    if (compressed == null) {
      throw Exception('COMPRESSION_FAILED');
    }
    
    return Uint8List.fromList(compressed);
  }

  static String decompressBytes(Uint8List compressedBytes) {
    try {
      final decompressed = GZipDecoder().decodeBytes(compressedBytes);
      return utf8.decode(decompressed);
    } catch (e) {
      throw Exception('DECOMPRESSION_FAILED: ${e.toString()}');
    }
  }

  static String compressForQR(String data) {
    final compressed = compressBytes(data);
    return base64Url.encode(compressed);
  }

  static String decompressFromQR(String base64Data) {
    try {
      final compressed = base64Url.decode(base64Data);
      return decompressBytes(compressed);
    } catch (e) {
      try {
        final compressed = base64.decode(base64Data);
        return decompressBytes(compressed);
      } catch (e2) {
        throw Exception('DECOMPRESSION_FAILED: ${e.toString()}');
      }
    }
  }

  static double getCompressionRatio(String original, Uint8List compressed) {
    final originalSize = utf8.encode(original).length;
    final compressedSize = compressed.length;
    return ((originalSize - compressedSize) / originalSize) * 100;
  }

  static bool fitsInQR(String base64Data, {int maxChars = 2900}) {
    return base64Data.length <= maxChars;
  }

  static double getSizeKB(String base64Data) {
    return base64Data.length / 1024;
  }
}

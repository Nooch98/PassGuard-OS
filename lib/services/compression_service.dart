/*
|--------------------------------------------------------------------------
| PassGuard OS - CompressionService
|--------------------------------------------------------------------------
| Description:
|   Utility service responsible for compressing and decompressing vault data.
|   Used primarily for QR-based transfer and compact export operations.
|
| Responsibilities:
|   - GZIP compression of UTF-8 string data
|   - GZIP decompression back to string
|   - Base64URL encoding for QR-safe transport
|   - Compatibility fallback (Base64 + Base64URL decoding)
|   - Compression ratio estimation
|   - QR capacity validation helpers
|
| Usage Context:
|   - Device-to-device QR transmission
|   - Cold storage export pipelines
|   - Preparing encrypted vault blobs for transport
|
| Important Security Note:
|   - This service DOES NOT perform encryption.
|   - Compression happens AFTER encryption in the export pipeline.
|   - Data passed here is assumed to already be encrypted if sensitive.
|
| Performance Notes:
|   - Uses GZip from `archive` package
|   - Optimized for medium-size payloads (QR transfer scenarios)
|   - QR capacity default limit ≈ 2900 characters
|
|--------------------------------------------------------------------------
*/

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

class CompressionService {
  static const int defaultMaxQrChars = 2900;

  static const String _qrChunkMagic = 'PGQR1';

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

  static String decompressFromQR(String input) {
    if (_looksLikeChunk(input)) {
      final joined = _reassembleChunks([input]);
      return _decompressBase64(joined);
    }

    return _decompressBase64(input);
  }

  static String _decompressBase64(String base64Data) {
    try {
      final compressed = base64Url.decode(base64Data);
      return decompressBytes(compressed);
    } catch (_) {
      try {
        final compressed = base64.decode(base64Data);
        return decompressBytes(compressed);
      } catch (e2) {
        throw Exception('DECOMPRESSION_FAILED: ${e2.toString()}');
      }
    }
  }

  static List<String> compressForQrChunks(
    String data, {
    int maxChars = defaultMaxQrChars,
  }) {
    final single = compressForQR(data);
    if (single.length <= maxChars) {
      return [single];
    }

    final crc = _crc32(utf8.encode(single));
    final crcHex = crc.toRadixString(16).padLeft(8, '0');

    const overhead = 5 + 1 + 7 + 1 + 8 + 1; // aproximado
    final chunkPayloadSize = (maxChars - overhead).clamp(200, maxChars);

    final chunks = <String>[];
    for (int offset = 0; offset < single.length; offset += chunkPayloadSize) {
      final end = (offset + chunkPayloadSize < single.length)
          ? offset + chunkPayloadSize
          : single.length;
      chunks.add(single.substring(offset, end));
    }

    final total = chunks.length;
    return List<String>.generate(total, (i) {
      final idx = i + 1;
      return '$_qrChunkMagic|$idx/$total|$crcHex|${chunks[i]}';
    });
  }

  static String decompressFromQrChunks(List<String> scanned) {
    final joined = _reassembleChunks(scanned);
    return _decompressBase64(joined);
  }

  static String _reassembleChunks(List<String> scanned) {
    final parsed = <_Chunk>[];

    for (final s in scanned) {
      final c = _parseChunk(s);
      if (c != null) parsed.add(c);
    }

    if (parsed.isEmpty) {
      throw Exception('QR_CHUNK_PARSE_FAILED');
    }

    final total = parsed.first.total;
    final crcHex = parsed.first.crcHex;

    for (final c in parsed) {
      if (c.total != total) throw Exception('QR_CHUNK_INCONSISTENT_TOTAL');
      if (c.crcHex != crcHex) throw Exception('QR_CHUNK_INCONSISTENT_CRC');
    }

    final map = <int, String>{};
    for (final c in parsed) {
      map[c.index] = c.data;
    }

    for (int i = 1; i <= total; i++) {
      if (!map.containsKey(i)) throw Exception('QR_CHUNK_MISSING_$i');
    }

    final joined = StringBuffer();
    for (int i = 1; i <= total; i++) {
      joined.write(map[i]!);
    }

    final joinedStr = joined.toString();
    final crc = _crc32(utf8.encode(joinedStr));
    final crcCheck = crc.toRadixString(16).padLeft(8, '0');

    if (crcCheck.toLowerCase() != crcHex.toLowerCase()) {
      throw Exception('QR_CHUNK_CORRUPTED_CRC_MISMATCH');
    }

    return joinedStr;
  }

  static bool _looksLikeChunk(String s) => s.startsWith('$_qrChunkMagic|');

  static _Chunk? _parseChunk(String s) {
    if (!_looksLikeChunk(s)) return null;
    final parts = s.split('|');
    if (parts.length < 4) return null;

    final idxTotal = parts[1].split('/');
    if (idxTotal.length != 2) return null;

    final index = int.tryParse(idxTotal[0]);
    final total = int.tryParse(idxTotal[1]);
    if (index == null || total == null) return null;

    final crcHex = parts[2];
    final data = parts.sublist(3).join('|');
    return _Chunk(index: index, total: total, crcHex: crcHex, data: data);
  }

  static double getCompressionRatio(String original, Uint8List compressed) {
    final originalSize = utf8.encode(original).length;
    final compressedSize = compressed.length;
    if (originalSize == 0) return 0;
    return ((originalSize - compressedSize) / originalSize) * 100;
  }

  static bool fitsInQR(String base64Data, {int maxChars = defaultMaxQrChars}) {
    return base64Data.length <= maxChars;
  }

  static double getSizeKB(String base64Data) => base64Data.length / 1024;

  static String getQrPayloadMode(String payload) {
    if (_looksLikeChunk(payload)) return 'CHUNKED';
    return 'SINGLE';
  }

  static final List<int> _crcTable = _makeCrcTable();

  static List<int> _makeCrcTable() {
    const poly = 0xEDB88320;
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (poly ^ (c >> 1)) : (c >> 1);
      }
      table[i] = c;
    }
    return table;
  }

  static int _crc32(List<int> data) {
    int c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class _Chunk {
  final int index;
  final int total;
  final String crcHex;
  final String data;

  _Chunk({
    required this.index,
    required this.total,
    required this.crcHex,
    required this.data,
  });
}

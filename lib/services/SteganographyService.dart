/*
|--------------------------------------------------------------------------
| PassGuard OS - SteganographyService (Covert Vault Transport Layer)
|--------------------------------------------------------------------------
| Description:
|   Provides LSB (Least Significant Bit) steganography for embedding
|   encrypted vault data inside PNG images.
|
|   This subsystem hides an already-encrypted vault payload inside image
|   pixel data, enabling covert storage/transport disguised as a normal
|   image file.
|
| Stego Versions:
|   - v1 (legacy): sequential LSB, 32-bit length header, UTF-8 payload.
|   - v2 (current): adds integrity + resilience primitives:
|       • Header magic + versioning
|       • CRC32 integrity check (detect corruption reliably)
|       • Optional pseudo-random embedding order (keyed permutation)
|       • Optional redundancy (repeatFactor=3) with majority vote decoding
|
| Why v2:
|   v1 can silently corrupt or misread lengths when bits flip.
|   v2 prevents "false success" and makes the payload harder to break by
|   small localized changes (and less obvious to steganalysis).
|
|------------------------------------------------------------------------------
| How It Works (v2)
|------------------------------------------------------------------------------
| Carrier:
|   - PNG only (lossless). Lossy formats (JPEG/HEIC) will destroy LSB data.
|
| Bit embedding:
|   - Uses LSB on RGB channels (1 bit per channel).
|   - Capacity per pixel: 3 bits (R, G, B).
|
| Packet Format (v2):
|   The embedded stream is a "packet":
|     [HEADER (16 bytes)] + [PAYLOAD (len bytes)]
|
|   HEADER layout (16 bytes, big-endian):
|     - magic   : u32  (0x50474F53 = "PGOS")
|     - version : u8   (2)
|     - flags   : u8   (reserved, 0)
|     - length  : u32  (payload length in bytes)
|     - crc32   : u32  (CRC32 of payload bytes)
|     - pad     : u16  (reserved/align)
|
|   Payload:
|     - UTF-8 bytes of the encrypted vault string (ciphertext).
|     - IMPORTANT: payload MUST already be encrypted.
|
| Integrity:
|   - CRC32 is used to detect corruption (bit flips, partial writes, etc).
|   - If CRC mismatches on extraction, the payload is rejected.
|
| Embedding Order:
|   - Default: sequential slot order (simple, but more fragile/obvious).
|   - Optional: keyed pseudo-random permutation of slots (recommended).
|     * This spreads bits across the whole image and avoids relying on
|       the very first pixels (reduces damage from localized edits).
|
| Redundancy (optional):
|   - repeatFactor = 1: no redundancy (max capacity).
|   - repeatFactor = 3: each bit written 3 times; decoding uses majority vote.
|     * Helps survive small random corruptions (but 3x larger bit budget).
|
| Capacity Formula:
|   availableBits = width * height * 3
|   usableBytes   = availableBits / 8
|
|   For v2, remember to account for:
|     - header bytes (16)
|     - optional redundancy (repeatFactor)
|
| Required capacity:
|   bitsNeeded = ( (16 + payloadBytes) * 8 ) * repeatFactor
|
| Encoding Process (v2):
|   1) Convert encryptedData -> payload bytes (UTF-8).
|   2) Compute CRC32(payload).
|   3) Build 16-byte header (magic/version/len/crc).
|   4) Concatenate header + payload -> packet bytes.
|   5) Convert packet bytes -> bitstream.
|   6) If repeatFactor=3, repeat each bit 3x.
|   7) Compute slot order (sequential OR keyed permutation).
|   8) Embed bits into RGB LSB following the slot order.
|   9) Output PNG with modified pixels.
|
| Extraction Process (v2):
|   1) Compute slot order (must match encoding; same stegoKey if used).
|   2) Read header bits (16 bytes) * repeatFactor.
|   3) If repeatFactor=3, majority-vote decode header bits.
|   4) Parse header and validate:
|        - magic == "PGOS"
|        - version supported
|        - length sanity bounds
|   5) Read (16 + length) bytes of packet * repeatFactor.
|   6) Majority-vote if needed; reconstruct packet bytes.
|   7) Extract payload and verify CRC32.
|   8) Decode UTF-8 -> return encrypted string.
|
|------------------------------------------------------------------------------
| Threat model assumptions:
|   - The image will remain lossless (PNG). No JPEG/HEIC conversions.
|   - The image will not be resized, filtered, or recompressed by platforms.
|   - The encrypted payload is cryptographically secure.
|   - The stegoKey (if used) remains secret and consistent across encode/decode.
|
| What this service does NOT protect against:
|   - Steganalysis tools detecting statistical anomalies
|   - Lossy recompression destroying hidden bits (JPEG/HEIC)
|   - Resizing, filtering, editing, or "enhancing" images
|   - Platforms that normalize pixels or strip/transform data
|   - Forensic memory analysis of decrypted payload
|   - Adversaries who already know LSB steganography is used
|
| Operational Security Warnings:
|   - This is concealment (obfuscation), not extra encryption.
|   - Social networks and messengers often recompress images -> payload loss.
|   - Cloud providers may change image encoding silently.
|   - Always verify extraction integrity after transport (CRC check does this).
|   - Do not rely on this mechanism as the sole backup method.
|   - For higher resilience, split payload across multiple carriers (chunking)
|     or add stronger ECC (e.g., Reed–Solomon) in future versions.
|
| Security Notes:
|   - Steganography ≠ Encryption.
|   - Always encrypt before embedding.
|   - Larger payloads require sufficiently large images.
|   - Using a stegoKey improves distribution and reduces "header fragility".
|   - repeatFactor=3 can help tolerate small random corruption at the cost
|     of capacity.
|
| Recommended Use Case:
|   - Covert vault backup transport
|   - Plausible deniability storage
|   - Experimental security research
|
|--------------------------------------------------------------------------
*/

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class SteganographyService {
  static const int _headerMagic = 0x50474F53;
  static const int _version = 2;

  static const int _maxPayloadBytes = 10 * 1024 * 1024;

  final int repeatFactor;

  const SteganographyService({
    this.repeatFactor = 1,
  }) : assert(repeatFactor == 1 || repeatFactor == 3);

  Future<Uint8List> hideVaultInImage(
    Uint8List imageBytes,
    String encryptedData, {
    String? stegoKey,
  }) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception("Unsupported image format");
    final payload = Uint8List.fromList(utf8.encode(encryptedData));

    if (payload.length > _maxPayloadBytes) {
      throw Exception("Payload too large (${payload.length} bytes).");
    }

    final crc = _crc32(payload);

    final header = BytesBuilder(copy: false)
      ..add(_u32be(_headerMagic))
      ..add(Uint8List.fromList([_version, 0]))
      ..add(_u32be(payload.length))
      ..add(_u32be(crc))
      ..add(Uint8List(2));

    final packet = Uint8List.fromList([...header.toBytes(), ...payload]);
    final bits = _bytesToBits(packet);
    final bitsWithRedundancy = (repeatFactor == 1) ? bits : _repeatBits(bits, repeatFactor);
    final totalBitsNeeded = bitsWithRedundancy.length;
    final availableBits = image.width * image.height * 3;

    if (totalBitsNeeded > availableBits) {
      throw Exception(
        "The image is too small.\n"
        "Need ${(totalBitsNeeded / 8 / 1024).toStringAsFixed(2)} KB, "
        "available ${(availableBits / 8 / 1024).toStringAsFixed(2)} KB.",
      );
    }

    final order = _buildBitOrder(
      totalSlots: availableBits,
      stegoKey: stegoKey,
    );

    int bitPtr = 0;
    final totalPixels = image.width * image.height;

    // We will update pixels by index for speed.
    for (int k = 0; k < order.length && bitPtr < totalBitsNeeded; k++) {
      final slot = order[k];
      final pixelIndex = slot ~/ 3;
      if (pixelIndex >= totalPixels) continue;

      final x = pixelIndex % image.width;
      final y = pixelIndex ~/ image.width;

      final channel = slot % 3;

      final pixel = image.getPixel(x, y);
      int r = pixel.r.toInt();
      int g = pixel.g.toInt();
      int b = pixel.b.toInt();

      final bit = bitsWithRedundancy[bitPtr++];

      if (channel == 0) {
        r = (r & ~1) | bit;
      } else if (channel == 1) {
        g = (g & ~1) | bit;
      } else {
        b = (b & ~1) | bit;
      }

      image.setPixelRgba(x, y, r, g, b, pixel.a.toInt());
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  Future<String> extractVaultFromImage(
    Uint8List imageBytes, {
    String? stegoKey,
  }) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception("Invalid image");

    final availableBits = image.width * image.height * 3;

    const headerBytes = 16;
    const headerBits = headerBytes * 8;

    final order = _buildBitOrder(
      totalSlots: availableBits,
      stegoKey: stegoKey,
    );

    final headerBitsWithRedundancy = headerBits * repeatFactor;

    final rawHeaderBits = _readBitsFromImage(
      image: image,
      order: order,
      bitsToRead: headerBitsWithRedundancy,
    );

    final headerBitsDecoded = (repeatFactor == 1)
        ? rawHeaderBits
        : _majorityVoteBits(rawHeaderBits, repeatFactor);

    final header = _bitsToBytes(headerBitsDecoded);

    final magic = _readU32be(header, 0);
    if (magic != _headerMagic) {
      throw Exception("No valid PassGuard stego payload found (bad magic).");
    }

    final version = header[4];
    if (version != _version) {
      throw Exception("Unsupported stego payload version: $version");
    }

    final len = _readU32be(header, 6);
    final crcExpected = _readU32be(header, 10);

    if (len <= 0 || len > _maxPayloadBytes) {
      throw Exception("Invalid payload length: $len");
    }

    final totalPacketBytes = headerBytes + len;
    final totalPacketBits = totalPacketBytes * 8;
    final totalPacketBitsWithRedundancy = totalPacketBits * repeatFactor;

    if (totalPacketBitsWithRedundancy > availableBits) {
      throw Exception("Carrier image doesn't contain full payload (truncated).");
    }

    final rawPacketBits = _readBitsFromImage(
      image: image,
      order: order,
      bitsToRead: totalPacketBitsWithRedundancy,
    );

    final packetBitsDecoded = (repeatFactor == 1)
        ? rawPacketBits
        : _majorityVoteBits(rawPacketBits, repeatFactor);

    final packet = _bitsToBytes(packetBitsDecoded);

    final payload = packet.sublist(headerBytes, headerBytes + len);
    final crcActual = _crc32(payload);

    if (crcActual != crcExpected) {
      throw Exception(
        "Payload corrupted (CRC mismatch). "
        "Expected=$crcExpected, got=$crcActual",
      );
    }

    return utf8.decode(payload);
  }

  List<int> _readBitsFromImage({
    required img.Image image,
    required List<int> order,
    required int bitsToRead,
  }) {
    final bits = <int>[];
    bits.length = 0;

    final totalPixels = image.width * image.height;

    for (int k = 0; k < order.length && bits.length < bitsToRead; k++) {
      final slot = order[k];
      final pixelIndex = slot ~/ 3;
      if (pixelIndex >= totalPixels) continue;

      final x = pixelIndex % image.width;
      final y = pixelIndex ~/ image.width;
      final channel = slot % 3;

      final pixel = image.getPixel(x, y);

      int bit;
      if (channel == 0) bit = pixel.r.toInt() & 1;
      else if (channel == 1) bit = pixel.g.toInt() & 1;
      else bit = pixel.b.toInt() & 1;

      bits.add(bit);
    }

    if (bits.length < bitsToRead) {
      throw Exception("Not enough data in image to read payload.");
    }

    return bits;
  }

  List<int> _buildBitOrder({
    required int totalSlots,
    String? stegoKey,
  }) {
    if (stegoKey == null || stegoKey.isEmpty) {
      return List<int>.generate(totalSlots, (i) => i, growable: false);
    }

    final seed = _fnv1a32(utf8.encode(stegoKey));
    final rng = Random(seed);

    final order = List<int>.generate(totalSlots, (i) => i);

    for (int i = order.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = order[i];
      order[i] = order[j];
      order[j] = tmp;
    }

    return order;
  }

  static List<int> _bytesToBits(Uint8List bytes) {
    final bits = <int>[];
    bits.reserveCapacity(bytes.length * 8);
    for (final b in bytes) {
      for (int i = 7; i >= 0; i--) {
        bits.add((b >> i) & 1);
      }
    }
    return bits;
  }

  static Uint8List _bitsToBytes(List<int> bits) {
    final out = Uint8List((bits.length / 8).floor());
    int byte = 0;
    int bitCount = 0;
    int outIndex = 0;

    for (final bit in bits) {
      byte = (byte << 1) | (bit & 1);
      bitCount++;
      if (bitCount == 8) {
        out[outIndex++] = byte;
        byte = 0;
        bitCount = 0;
        if (outIndex >= out.length) break;
      }
    }

    return out;
  }

  static List<int> _repeatBits(List<int> bits, int factor) {
    final out = <int>[];
    out.reserveCapacity(bits.length * factor);
    for (final b in bits) {
      for (int i = 0; i < factor; i++) out.add(b);
    }
    return out;
  }

  static List<int> _majorityVoteBits(List<int> bits, int factor) {
    final outLen = (bits.length / factor).floor();
    final out = <int>[];
    out.reserveCapacity(outLen);

    for (int i = 0; i < outLen; i++) {
      int ones = 0;
      for (int k = 0; k < factor; k++) {
        if (bits[i * factor + k] == 1) ones++;
      }
      out.add(ones >= ((factor ~/ 2) + 1) ? 1 : 0);
    }

    return out;
  }

  static Uint8List _u32be(int v) => Uint8List.fromList([
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);

  static int _readU32be(Uint8List b, int offset) {
    return ((b[offset] & 0xFF) << 24) |
        ((b[offset + 1] & 0xFF) << 16) |
        ((b[offset + 2] & 0xFF) << 8) |
        (b[offset + 3] & 0xFF);
  }

  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= (byte & 0xFF);
      for (int i = 0; i < 8; i++) {
        final mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xEDB88320 & mask);
      }
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  static int _fnv1a32(List<int> bytes) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811C9DC5;
    for (final b in bytes) {
      hash ^= (b & 0xFF);
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash >>> 0;
  }

  StegoCheckResult checkCapacity(int width, int height, String encryptedData) {
    final int payloadBytes = utf8.encode(encryptedData).length;
    const int headerBytes = 16;
    final int totalRequiredBytes = headerBytes + payloadBytes;

    final int totalAvailableBits = width * height * 3;
    final int maxUsableBytes = totalAvailableBits ~/ (8 * repeatFactor);

    final bool fits = totalRequiredBytes <= maxUsableBytes;
    final double usage = (totalRequiredBytes / maxUsableBytes) * 100;

    return StegoCheckResult(
      fits: fits,
      usagePercentage: usage > 100 ? 100.0 : usage,
      availableBytes: maxUsableBytes,
      requiredBytes: totalRequiredBytes,
    );
  }
}

extension _ListReserve<T> on List<T> {
  void reserveCapacity(int _) {
    // No-op in Dart. Exists for readability / parity with other langs.
  }
}

class StegoCheckResult {
  final bool fits;
  final double usagePercentage;
  final int availableBytes;
  final int requiredBytes;

  StegoCheckResult({required this.fits, required this.usagePercentage, required this.availableBytes, required this.requiredBytes});
}

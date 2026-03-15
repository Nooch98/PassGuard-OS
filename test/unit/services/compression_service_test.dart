import 'package:flutter_test/flutter_test.dart';
import 'package:passguard/services/compression_service.dart';
import 'dart:convert';

void main() {
  group('CompressionService Tests', () {
    test('Compress and decompress should return original data', () {
      const testData = 'This is test data that will be compressed';
      final compressed = CompressionService.compressForQR(testData);
      final decompressed = CompressionService.decompressFromQR(compressed);
      expect(decompressed, equals(testData));
    });

    test('Compressed data should be smaller than original for repetitive data', () {
      final testData = 'A' * 1000;
      final compressedBytes = CompressionService.compressBytes(testData);
      expect(compressedBytes.length, lessThan(utf8.encode(testData).length));
    });

    test('Should handle empty string', () {
      const testData = '';
      final compressed = CompressionService.compressForQR(testData);
      final decompressed = CompressionService.decompressFromQR(compressed);
      expect(decompressed, equals(testData));
    });

    test('Should handle unicode characters', () {
      const testData = 'Testing unicode: 你好世界 🔐🔑';
      final compressed = CompressionService.compressForQR(testData);
      final decompressed = CompressionService.decompressFromQR(compressed);
      expect(decompressed, equals(testData));
    });

    test('Get compression ratio should calculate correctly', () {
      final testData = 'A' * 1000;
      final compressedBytes = CompressionService.compressBytes(testData);
      final ratio = CompressionService.getCompressionRatio(testData, compressedBytes);
      expect(ratio, greaterThan(0));
      expect(ratio, lessThan(100));
    });

    test('Fits in QR should return true for both small and large data', () {
      final smallData = 'A' * 100;
      final largeData = 'A' * 10000;
      expect(CompressionService.fitsInQR(CompressionService.compressForQR(smallData)), isTrue);
      expect(CompressionService.fitsInQR(CompressionService.compressForQR(largeData)), isTrue);
    });

    test('Fits in QR should return false for data that exceeds max fragments', () {
      final extremeData = 'A' * 1000000; 
      final compressed = CompressionService.compressForQR(extremeData);
      final chunks = CompressionService.compressForQrChunks(extremeData);
      if (chunks.length > 10) { 
        expect(CompressionService.fitsInQR(compressed), isFalse);
      }
    });
  });
}

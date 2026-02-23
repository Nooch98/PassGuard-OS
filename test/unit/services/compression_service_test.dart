import 'package:flutter_test/flutter_test.dart';
import 'package:passguard/services/compression_service.dart';
import 'dart:convert';

void main() {
  group('CompressionService Tests', () {
    test('Compress and decompress should return original data', () {
      // Arrange
      const testData = 'This is test data that will be compressed';

      // Act
      final compressed = CompressionService.compressForQR(testData);
      final decompressed = CompressionService.decompressFromQR(compressed);

      // Assert
      expect(decompressed, equals(testData));
    });

    test('Compressed data should be smaller than original for repetitive data', () {
      // Arrange
      final testData = 'A' * 1000;

      // Act
      final compressedBytes = CompressionService.compressBytes(testData);

      // Assert
      expect(compressedBytes.length, lessThan(utf8.encode(testData).length));
    });

    test('Should handle empty string', () {
      // Arrange
      const testData = '';

      // Act
      final compressed = CompressionService.compressForQR(testData);
      final decompressed = CompressionService.decompressFromQR(compressed);

      // Assert
      expect(decompressed, equals(testData));
    });

    test('Should handle unicode characters', () {
      // Arrange
      const testData = 'Testing unicode: 你好世界 🔐🔑';

      // Act
      final compressed = CompressionService.compressForQR(testData);
      final decompressed = CompressionService.decompressFromQR(compressed);

      // Assert
      expect(decompressed, equals(testData));
    });

    test('Get compression ratio should calculate correctly', () {
      // Arrange
      final testData = 'A' * 1000;
      final compressedBytes = CompressionService.compressBytes(testData);

      // Act
      final ratio = CompressionService.getCompressionRatio(testData, compressedBytes);

      // Assert
      expect(ratio, greaterThan(0));
      expect(ratio, lessThan(100)); // Cambiado de lessThanOrEqual a lessThan
    });

    test('Fits in QR should return correct result', () {
      // Arrange
      final smallData = 'A' * 100;
      final largeData = 'A' * 10000;

      // Act
      final smallCompressed = CompressionService.compressForQR(smallData);
      final largeCompressed = CompressionService.compressForQR(largeData);

      // Assert
      expect(CompressionService.fitsInQR(smallCompressed), isTrue);
      expect(CompressionService.fitsInQR(largeCompressed), isFalse);
    });
  });
}

import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;

class SteganographyService {
  Future<Uint8List> hideVaultInImage(Uint8List imageBytes, String encryptedData) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception("Unsupported image format");

    List<int> dataBytes = Uint8List.fromList(utf8.encode(encryptedData));
    int dataLength = dataBytes.length;

    int totalBitsNeeded = 32 + (dataLength * 8);
    int availableBits = image.width * image.height * 3;
    
    if (totalBitsNeeded > availableBits) {
      throw Exception(
        "The image is too small to contain the bunker. "
        "You need ${(totalBitsNeeded / 8 / 1024).toStringAsFixed(2)} KB, "
        "but there are only ${(availableBits / 8 / 1024).toStringAsFixed(2)} KB available."
      );
    }

    List<int> bitsToHide = [];
    for (int i = 31; i >= 0; i--) {
      bitsToHide.add((dataLength >> i) & 1);
    }

    for (int byte in dataBytes) {
      for (int i = 7; i >= 0; i--) {
        bitsToHide.add((byte >> i) & 1);
      }
    }

    int bitPointer = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        if (bitPointer >= bitsToHide.length) break;

        img.Pixel pixel = image.getPixel(x, y);

        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();

        if (bitPointer < bitsToHide.length) {
          r = (r & ~1) | bitsToHide[bitPointer++];
        }
        if (bitPointer < bitsToHide.length) {
          g = (g & ~1) | bitsToHide[bitPointer++];
        }
        if (bitPointer < bitsToHide.length) {
          b = (b & ~1) | bitsToHide[bitPointer++];
        }

        image.setPixelRgba(x, y, r, g, b, pixel.a.toInt());
      }
      if (bitPointer >= bitsToHide.length) break;
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  Future<String> extractVaultFromImage(Uint8List imageBytes) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception("Invalid image");

    List<int> extractedBits = [];

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        img.Pixel pixel = image.getPixel(x, y);
        extractedBits.add(pixel.r.toInt() & 1);
        extractedBits.add(pixel.g.toInt() & 1);
        extractedBits.add(pixel.b.toInt() & 1);
        if (extractedBits.length >= 32) break;
      }
      if (extractedBits.length >= 32) break;
    }

    int messageLength = 0;
    for (int i = 0; i < 32; i++) {
      messageLength = (messageLength << 1) | extractedBits[i];
    }

    if (messageLength <= 0 || messageLength > 10000000) {
      throw Exception("No valid data was detected in the image");
    }

    int totalBitsToRead = 32 + (messageLength * 8);
    extractedBits.clear();

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        img.Pixel pixel = image.getPixel(x, y);
        extractedBits.add(pixel.r.toInt() & 1);
        extractedBits.add(pixel.g.toInt() & 1);
        extractedBits.add(pixel.b.toInt() & 1);
        if (extractedBits.length >= totalBitsToRead) break;
      }
      if (extractedBits.length >= totalBitsToRead) break;
    }

    List<int> messageBytes = [];
    for (int i = 32; i < totalBitsToRead && i + 7 < extractedBits.length; i += 8) {
      int byte = 0;
      for (int bit = 0; bit < 8; bit++) {
        byte = (byte << 1) | extractedBits[i + bit];
      }
      messageBytes.add(byte);
    }

    return utf8.decode(messageBytes);
  }
}

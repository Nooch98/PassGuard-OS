import 'package:flutter/services.dart' show rootBundle;

class WordlistService {
  static List<String>? _cached;

  static Future<List<String>> loadDefault() async {
    if (_cached != null) return _cached!;

    final txt = await rootBundle.loadString('assets/wordlists/multi_2000.txt');

    _cached = txt
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    return _cached!;
  }

  static List<String>? get cached => _cached;
}

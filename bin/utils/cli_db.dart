import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;

class CLIDatabase {
  static Database? _db;

  static Database get instance {
    if (_db != null) return _db!;
    _db = _initDB();
    return _db!;
  }

  static Database _initDB() {
    String dbPath = "";
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

    if (Platform.isWindows) {
      dbPath = p.join(Platform.environment['APPDATA']!, 'com.example.passguard', 'databases', 'passguard_v2.db');
    } else {
      dbPath = p.join(home!, '.local', 'share', 'passguard', 'passguard_v2.db');
    }

    if (!File(dbPath).existsSync()) {
      throw Exception("DATABASE_NOT_FOUND: Please open the GUI app first.");
    }

    return sqlite3.open(dbPath);
  }
}

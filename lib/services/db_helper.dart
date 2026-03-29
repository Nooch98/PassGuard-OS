/*
|--------------------------------------------------------------------------
| PassGuard OS - DBHelper
|--------------------------------------------------------------------------
| Description:
|   SQLite database manager for PassGuard OS.
|
| Responsibilities:
|   - Initialize database
|   - Manage schema versions
|   - Handle migrations
|   - Provide shared database instance
|
| Security Notes:
|   - All sensitive fields are encrypted before storage
|   - Database file contains ciphertext only
|--------------------------------------------------------------------------
*/

import 'package:passguard/models/password_model.dart';
import 'package:passguard/models/recovery_code_model.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

class DBHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'passguard_v2.db');
    
    return await openDatabase(
      path,
      version: 8,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
      Future<void> safeAddColumn(String table, String column, String type) async {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
          print("DATABASE: Column $column added to $table.");
        } catch (e) {
          print("DATABASE: Column $column already exists in $table, skipping...");
        }
      }

      if (oldVersion < 2) {
        await safeAddColumn('accounts', 'created_at', 'TEXT');
        await safeAddColumn('accounts', 'updated_at', 'TEXT');
        await safeAddColumn('accounts', 'last_used', 'TEXT');
        await safeAddColumn('accounts', 'notes', 'TEXT');
        await safeAddColumn('accounts', 'is_favorite', 'INTEGER DEFAULT 0');
        await safeAddColumn('accounts', 'password_history', 'TEXT');
      }

      if (oldVersion < 3) {
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS identities (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              type TEXT NOT NULL,
              full_name TEXT,
              email TEXT,
              phone TEXT,
              is_favorite INTEGER DEFAULT 0,
              created_at TEXT,
              updated_at TEXT
              -- ... (el resto de tus campos de identidad)
            )
          ''');
        } catch (e) { print("Identities table check: $e"); }
      }

      if (oldVersion < 4) await safeAddColumn('accounts', 'password_fp', 'TEXT');
      if (oldVersion < 5) await safeAddColumn('accounts', 'otp_meta', 'TEXT');
      if (oldVersion < 6) await safeAddColumn('accounts', 'origin', 'TEXT');
      if (oldVersion < 7) await safeAddColumn('accounts', 'is_excluded', 'INTEGER DEFAULT 0');
      if (oldVersion < 8) await safeAddColumn('accounts', 'audit_cache', 'TEXT');
    },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        platform TEXT NOT NULL,
        origin TEXT,
        username TEXT,
        password TEXT NOT NULL,
        password_fp TEXT,
        otp_seed TEXT,
        category TEXT DEFAULT 'PERSONAL',
        created_at TEXT,
        updated_at TEXT,
        last_used TEXT,
        notes TEXT,
        is_favorite INTEGER DEFAULT 0,
        password_history TEXT,
        otp_meta TEXT,
        is_excluded INTEGER DEFAULT 0,
        audit_cache TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE recovery_codes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        is_used INTEGER DEFAULT 0,
        created_at TEXT,
        FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE file_vault(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        encrypted_path TEXT NOT NULL,
        file_size INTEGER,
        created_at TEXT,
        mime_type TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE identities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        full_name TEXT,
        first_name TEXT,
        middle_name TEXT,
        last_name TEXT,
        email TEXT,
        phone TEXT,
        date_of_birth TEXT,
        gender TEXT,
        address1 TEXT,
        address2 TEXT,
        city TEXT,
        state TEXT,
        zip_code TEXT,
        country TEXT,
        card_number TEXT,
        card_holder TEXT,
        expiration_date TEXT,
        cvv TEXT,
        card_type TEXT,
        document_number TEXT,
        issuing_authority TEXT,
        issue_date TEXT,
        expiry_date TEXT,
        notes TEXT,
        is_favorite INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
  }

  static Future<Map<String, dynamic>> handleSaveSuggestion(Map<String, dynamic> data) async {
    final db = await database;
    String origin = data['origin'] ?? "";
    String platform = data['platform'] ?? "";

    if (origin.isEmpty || platform.isEmpty) return {"status": "INVALID_DATA"};
    List<Map<String, dynamic>> results = await db.query(
      'accounts',
      where: 'platform LIKE ? OR platform = ?',
      whereArgs: ['%$platform%', platform]
    );

    if (results.isNotEmpty) {
      var account = results.first;

      if (account['origin'] == origin) {
        return {"status": "ALREADY_LINKED"};
      }

      return {
        "status": "NEED_CONFIRMATION",
        "account_id": account['id'],
        "platform": account['platform'],
        "new_origin": origin
      };
    } 

    return {"status": "NOT_FOUND"};
  }

  static Future<int> insertPassword(PasswordModel password) async {
    final db = await database;
    return await db.insert(
      'accounts',
      password.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<int> insertRecoveryCode(RecoveryCodeModel code) async {
    final db = await database;
    return await db.insert(
      'recovery_codes',
      code.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<bool> checkIfPasswordExists(String platform, String? username) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'accounts',
      where: 'platform = ? AND username = ?',
      whereArgs: [platform, username],
    );
    return results.isNotEmpty;
  }

  static Future<List<PasswordModel>> getAllPasswords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');
    return List.generate(maps.length, (i) => PasswordModel.fromMap(maps[i]));
  }

  static Future<List<Map<String, dynamic>>> getRawAccounts() async {
    final db = await database;
    return await db.query('accounts');
  }

  static Future<void> forceLinkOrigin(int accountId, String origin) async {
    final db = await database;
    await db.update(
      'accounts',
      {'origin': origin},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  static Future<void> updateLastUsed(int accountId) async {
    final db = await database;
    await db.update(
      'accounts',
      {'last_used': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

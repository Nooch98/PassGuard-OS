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
      version: 5,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE accounts ADD COLUMN created_at TEXT'
          );
          await db.execute(
            'ALTER TABLE accounts ADD COLUMN updated_at TEXT'
          );
          await db.execute(
            'ALTER TABLE accounts ADD COLUMN last_used TEXT'
          );
          await db.execute(
            'ALTER TABLE accounts ADD COLUMN notes TEXT'
          );
          await db.execute(
            'ALTER TABLE accounts ADD COLUMN is_favorite INTEGER DEFAULT 0'
          );
          await db.execute(
            'ALTER TABLE accounts ADD COLUMN password_history TEXT'
          );
        }
        if (oldVersion < 3) {
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
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE accounts ADD COLUMN password_fp TEXT');
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE accounts ADD COLUMN otp_meta TEXT');
        }
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        platform TEXT NOT NULL,
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
        otp_meta TEXT
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


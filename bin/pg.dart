import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'package:otp/otp.dart';
import 'package:passguard/services/encryption_service.dart'; 

class PassGuardCLI {
  static Database? _db;

  static File get _configFile {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ".";
    return File(p.join(home, '.passguard_cli_config'));
  }

  static String _getSavedDbPath() {
    if (_configFile.existsSync()) {
      return _configFile.readAsStringSync().trim();
    }
    
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (Platform.isWindows) {
      return p.join(Platform.environment['APPDATA']!, 'com.example.passguard', 'databases', 'passguard_v2.db');
    } else if (Platform.isMacOS) {
      return p.join(home!, 'Library', 'Application Support', 'com.example.passguard', 'passguard_v2.db');
    } else {
      return p.join(home!, '.local/share/com.example.passguard/passguard_v2.db');
    }
  }

  static Database _getDatabase() {
    if (_db != null) return _db!;
    String dbPath = _getSavedDbPath();

    if (!File(dbPath).existsSync()) {
      print("❌ Error: Vault not found at: $dbPath");
      print("💡 Use 'pg config <path>' to set your database location.");
      exit(1);
    }
    return sqlite3.open(dbPath);
  }

  static void main(List<String> args) {
    if (args.isEmpty) {
      _printUsage();
      return;
    }

    final command = args[0].toLowerCase();

    switch (command) {
      case 'config':
        if (args.length < 2) {
          print("Current DB path: ${_getSavedDbPath()}");
          print("Usage: pg config <absolute_path_to_db>");
        } else {
          _setConfig(args[1]);
        }
        break;
      case 'list':
        _listAccounts();
        break;
      case 'get':
        if (args.length < 2) print("Usage: pg get <name>");
        else _getAndDecryptAccount(args[1]);
        break;
      case '2fa':
        if (args.length < 2) print("Usage: pg 2fa <name>");
        else _getAndDecryptAccount(args[1], onlyOTP: true);
        break;
      case 'add':
        _addAccount();
        break;
      case 'edit':
        if (args.length < 2) print("Usage: pg edit <name>");
        else _editAccount(args[1]);
        break;
      case 'delete':
        if (args.length < 2) print("Usage: pg delete <name>");
        else _deleteAccount(args[1]);
        break;
      default:
        print("Unknown command: $command");
        _printUsage();
    }
  }

  static void _printUsage() {
    print("\n🛡️  PassGuard OS | CLI Mode");
    print("=" * 40);
    print("  pg list            List all accounts");
    print("  pg get <name>      Show details & password");
    print("  pg 2fa <name>      Show only TOTP code");
    print("  pg add             Create a new record");
    print("  pg edit <name>     Modify an existing record");
    print("  pg delete <name>   Remove a record");
    print("  pg config <path>   Set vault (.db) location");
    print("=" * 40);
  }

  static void _setConfig(String newPath) {
    if (File(newPath).existsSync()) {
      _configFile.writeAsStringSync(newPath);
      print("✅ Database path updated.");
    } else {
      print("❌ Error: File not found.");
    }
  }

  static void _listAccounts() {
    final db = _getDatabase();
    final ResultSet results = db.select('SELECT platform, username FROM accounts ORDER BY platform ASC');
    print("\n📦 VAULT CONTENT:");
    print("-" * 45);
    for (final row in results) {
      print("${row['platform'].toString().padRight(20)} | ${row['username'] ?? 'No User'}");
    }
    print("-" * 45);
  }

  static void _getAndDecryptAccount(String searchName, {bool onlyOTP = false}) {
    final db = _getDatabase();
    final results = db.select('SELECT * FROM accounts WHERE platform LIKE ? LIMIT 1', ['%$searchName%']);

    if (results.isEmpty) {
      print("❌ No account found matching: $searchName");
      return;
    }

    final row = results.first;
    if (!onlyOTP) {
      print("\n🔍 Platform: ${row['platform']}");
      print("👤 User: ${row['username']}");
    }

    stdout.write("🔑 Master Password: ");
    stdin.echoMode = false;
    String? masterPass = stdin.readLineSync();
    stdin.echoMode = true;
    print("\n" + "─" * 40);

    if (masterPass == null || masterPass.isEmpty) return;
    final Uint8List masterKeyBytes = Uint8List.fromList(utf8.encode(masterPass));

    try {
      if (!onlyOTP) {
        final pass = EncryptionService.decrypt(combinedText: row['password'], masterKeyBytes: masterKeyBytes);
        if (pass == "ERROR: DECRYPTION_FAILED") { print("❌ Invalid Master Password."); return; }
        print("🔓 Password: $pass");
      }

      if (row['otp_seed'] != null && row['otp_seed'].toString().isNotEmpty) {
        final seed = EncryptionService.decrypt(combinedText: row['otp_seed'], masterKeyBytes: masterKeyBytes);
        if (seed != "ERROR: DECRYPTION_FAILED") {
          final code = OTP.generateTOTPCodeString(seed.toUpperCase().replaceAll(' ', ''), DateTime.now().millisecondsSinceEpoch, isGoogle: true);
          print("🕒 2FA Code: ${code.substring(0, 3)} ${code.substring(3)} (${30 - (DateTime.now().second % 30)}s)");
        }
      }

      if (!onlyOTP && row['notes'] != null && row['notes'].toString().isNotEmpty) {
        final notes = EncryptionService.decrypt(combinedText: row['notes'], masterKeyBytes: masterKeyBytes);
        print("📝 Notes: $notes");
      }
    } catch (e) {
      print("💥 Error: $e");
    } finally {
      masterKeyBytes.fillRange(0, masterKeyBytes.length, 0);
    }
    print("─" * 40);
  }

  static void _addAccount() {
    print("\n➕ NEW ACCOUNT");
    stdout.write("Platform: "); String platform = stdin.readLineSync() ?? "";
    stdout.write("Username: "); String user = stdin.readLineSync() ?? "";
    stdout.write("Password: "); stdin.echoMode = false; String pass = stdin.readLineSync() ?? ""; stdin.echoMode = true;
    print("\n2FA Seed (Optional): "); String seed = stdin.readLineSync() ?? "";
    
    stdout.write("🔑 Master Password to encrypt: ");
    stdin.echoMode = false; String? mp = stdin.readLineSync(); stdin.echoMode = true;
    if (mp == null || mp.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(mp));

    try {
      final db = _getDatabase();
      final now = DateTime.now().toIso8601String();
      db.execute('INSERT INTO accounts (platform, username, password, otp_seed, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [platform, user, EncryptionService.encrypt(pass, mk), seed.isNotEmpty ? EncryptionService.encrypt(seed, mk) : null, now, now]);
      print("\n✅ Saved successfully.");
    } catch (e) { print("❌ Error: $e"); } finally { mk.fillRange(0, mk.length, 0); }
  }

  static void _editAccount(String searchName) {
    final db = _getDatabase();
    final results = db.select('SELECT * FROM accounts WHERE platform LIKE ? LIMIT 1', ['%$searchName%']);
    if (results.isEmpty) { print("❌ Not found."); return; }
    final row = results.first;

    print("\n📝 EDITING: ${row['platform']}");
    stdout.write("New User [${row['username']}]: "); String newUser = stdin.readLineSync() ?? "";
    stdout.write("New Password (blank to keep): "); stdin.echoMode = false; String newPass = stdin.readLineSync() ?? ""; stdin.echoMode = true;

    stdout.write("\n🔑 Master Password: ");
    stdin.echoMode = false; String? mp = stdin.readLineSync(); stdin.echoMode = true;
    if (mp == null || mp.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(mp));

    try {
      String encPass = newPass.isNotEmpty ? EncryptionService.encrypt(newPass, mk) : row['password'];
      db.execute('UPDATE accounts SET username = ?, password = ?, updated_at = ? WHERE id = ?',
        [newUser.isEmpty ? row['username'] : newUser, encPass, DateTime.now().toIso8601String(), row['id']]);
      print("\n✅ Updated.");
    } catch (e) { print("❌ Error: $e"); } finally { mk.fillRange(0, mk.length, 0); }
  }

  static void _deleteAccount(String searchName) {
    final db = _getDatabase();
    final results = db.select('SELECT id, platform FROM accounts WHERE platform LIKE ? LIMIT 1', ['%$searchName%']);
    if (results.isEmpty) { print("❌ Not found."); return; }
    stdout.write("⚠️ Delete '${results.first['platform']}'? (y/N): ");
    if (stdin.readLineSync()?.toLowerCase() == 'y') {
      db.execute('DELETE FROM accounts WHERE id = ?', [results.first['id']]);
      print("🗑️  Deleted.");
    }
  }
}

void main(List<String> args) => PassGuardCLI.main(args);

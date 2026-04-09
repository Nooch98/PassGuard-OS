import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:passguard/services/password_generator_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'package:otp/otp.dart';
import 'package:passguard/services/encryption_service.dart';

class C {
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const green = '\x1B[32m';
  static const cyan = '\x1B[36m';
  static const yellow = '\x1B[33m';
  static const red = '\x1B[31m';
  static const blue = '\x1B[34m';
  static const grey = '\x1B[90m';
  static const clearLine = '\x1B[2K\r';
}

class PassGuardCLI {
  static Database? _db;
  static final _generator = PasswordGeneratorPro();
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
      print("${C.red}${C.bold}❌ Error:${C.reset} Vault not found at: $dbPath");
      print("${C.yellow}💡 Use 'pg config <path>' to set your database location.${C.reset}");
      exit(1);
    }
    return sqlite3.open(dbPath);
  }

  static void main(List<String> args) async {
    if (args.isEmpty) {
      _printUsage();
      return;
    }
    final command = args[0].toLowerCase();
    switch (command) {
      case 'config':
        if (args.length < 2) {
          print("${C.cyan}Current DB path:${C.reset} ${_getSavedDbPath()}");
          print("${C.grey}Usage: pg config <absolute_path_to_db>${C.reset}");
        } else {
          _setConfig(args[1]);
        }
        break;
      case 'list':
        _listAccounts();
        break;
      case 'get':
        if (args.length < 2) print("${C.yellow}Usage: pg get <name>${C.reset}");
        else await _getAndDecryptAccount(args[1]);
        break;
      case '2fa':
        if (args.length < 2) print("${C.yellow}Usage: pg 2fa <name>${C.reset}");
        else await _getAndDecryptAccount(args[1], onlyOTP: true);
        break;
      case 'add':
        _addAccount();
        break;
      case 'edit':
        if (args.length < 2) print("${C.yellow}Usage: pg edit <name>${C.reset}");
        else _editAccount(args[1]);
        break;
      case 'delete':
        if (args.length < 2) print("${C.yellow}Usage: pg delete <name>${C.reset}");
        else _deleteAccount(args[1]);
        break;
      case 'gen':
        _handleGenerator();
        break;
      case 'help':
      case '--help':
        _printDetailedHelp();
        break;
      default:
        print("${C.red}Unknown command: $command${C.reset}");
        _printUsage();
    }
  }

  static void _printDetailedHelp() {
    print("\n${C.blue}${C.bold}🛡️  PASSGUARD OS | CLI Engine Help${C.reset}");
    print("${C.grey}Detailed documentation${C.reset}\n");

    print("${C.yellow}${C.bold}USAGE:${C.reset}");
    print("  pg <command> [arguments]\n");

    print("${C.yellow}${C.bold}CORE COMMANDS:${C.reset}");
    _printCmd("list", "Display all stored accounts in a formatted table.");
    _printCmd("add", "Create a new record. Supports manual input or interactive password generation (Random, PIN, Pronounceable, High Entropy).");
    _printCmd("get <name>", "Retrieve details, decrypt password, and start Live 2FA mode if a seed is present.");
    _printCmd("2fa <name>", "Directly launch Live 2FA TOTP display for a specific account.");
    _printCmd("edit <name>", "Modify username or password of an existing record.");
    _printCmd("delete <name>", "Permanently remove a record from the vault (requires confirmation).");

    print("\n${C.yellow}${C.bold}UTILITIES:${C.reset}");
    _printCmd("gen", "Stand-alone password generator. Provides entropy analysis and crack-time estimates.");
    _printCmd("config <path>", "Link the CLI to your PassGuard database (.db) file. Required for first-time setup.");
    _printCmd("help", "Show this detailed technical documentation.");

    print("\n${C.yellow}${C.bold}GENERATOR MODES (Inside 'gen' or 'add'):${C.reset}");
    print("  ${C.cyan}Random${C.reset}        Full alphanumeric + symbols mix. High security.");
    print("  ${C.cyan}PIN${C.reset}           Numeric only. Ideal for cards or device locks.");
    print("  ${C.cyan}Pronounceable${C.reset} Vowel/Consonant patterns. Easier to memorize.");
    print("  ${C.cyan}High Entropy${C.reset}       Ultra-high entropy (32+ chars) for maximum resistance.");

    print("\n${C.yellow}${C.bold}SECURITY NOTES:${C.reset}");
    print("  - Master Password is never stored; it is used to derive encryption keys in memory.");
    print("  - All sensitive data is encrypted using AES-GCM.");
    print("  - TOTP codes are generated locally and refreshed every 30 seconds.");
    print("${C.grey}${'-' * 60}${C.reset}\n");
  }

  static void _printCmd(String cmd, String desc) {
    print("  ${C.cyan}${cmd.padRight(15)}${C.reset} $desc");
  }

  static void _printUsage() {
    print("\n${C.blue}${C.bold}🛡️  PASSGUARD OS | CLI Engine${C.reset}");
    print("${C.grey}${'-' * 45}${C.reset}");
    print("  ${C.cyan}pg list${C.reset}            List all accounts");
    print("  ${C.cyan}pg get <name>${C.reset}      Show details & password (Live TOTP)");
    print("  ${C.cyan}pg 2fa <name>${C.reset}      Show only TOTP code (Live)");
    print("  ${C.cyan}pg gen${C.reset}             Secure password generator");
    print("  ${C.cyan}pg add${C.reset}             Create a new record");
    print("  ${C.cyan}pg edit <name>${C.reset}     Modify an existing record");
    print("  ${C.cyan}pg delete <name>${C.reset}   Remove a record");
    print("  ${C.cyan}pg config <path>${C.reset}   Set vault (.db) location");
    print("${C.grey}${'-' * 45}${C.reset}");
  }

  static void _handleGenerator() {
    print("\n${C.blue}${C.bold}🔐 PASSGUARD GENERATOR PRO${C.reset}");
    final res = _runGeneratorFlow();
    if (res != null) {
      _printGeneratedResult(res);
    }
  }

  static GeneratedPassword? _runGeneratorFlow() {
    print("\n${C.yellow}🎲 Generator Options:${C.reset}");
    print("  [1] Random  [2] PIN (Numeric)  [3] Pronounceable  [4] High-Entropy");
    stdout.write("Select mode (default 1): ");
    String? choice = stdin.readLineSync();
    GeneratorOptions options;
    if (choice == '2') {
      stdout.write("PIN Length (default 4): ");
      int l = int.tryParse(stdin.readLineSync() ?? "") ?? 4;
      options = GeneratorOptions(
        mode: GeneratorMode.random, 
        length: l,
        digits: true,
        upper: false,
        lower: false,
        symbols: false,
        enforceAllSets: false,
      );
    } else if (choice == '3') {
      stdout.write("Syllables (5): ");
      int s = int.tryParse(stdin.readLineSync() ?? "") ?? 5;
      options = GeneratorOptions(
        mode: GeneratorMode.pronounceable, 
        syllables: s, 
        pronounceableAddNumber: true
      );
    } else if (choice == '4') {
      options = GeneratorOptions(
        mode: GeneratorMode.quantum, 
        length: 32
      );
    } else {
      stdout.write("Length (20): ");
      int l = int.tryParse(stdin.readLineSync() ?? "") ?? 20;
      options = GeneratorOptions(
        mode: GeneratorMode.random, 
        length: l,
        upper: true,
        lower: true,
        digits: true,
        symbols: true
      );
    }
    try {
      final result = _generator.generate(options);
      if (choice == '2') {
        print("${C.grey}Note: PINs have lower entropy than alphanumeric passwords.${C.reset}");
      }
      return result;
    } catch (e) {
      print("${C.red}Error: $e${C.reset}");
      return null;
    }
  }

  static void _printGeneratedResult(GeneratedPassword res) {
    String strengthColor;
    switch (res.strength) {
      case StrengthLevel.weak: strengthColor = C.red; break;
      case StrengthLevel.fair: strengthColor = C.yellow; break;
      case StrengthLevel.good: strengthColor = C.green; break;
      case StrengthLevel.strong: strengthColor = C.cyan; break;
      default: strengthColor = C.blue + C.bold;
    }
    print("\n${C.grey}┌──────────────────────────────────────────────────────────┐${C.reset}");
    print("${C.grey}│${C.reset} ${C.bold}VALUE:${C.reset} ${C.green}${C.bold}${res.value}${C.reset}");
    print("${C.grey}├──────────────────────────────────────────────────────────┤${C.reset}");
    print("${C.grey}│${C.reset} Strength: $strengthColor${res.strength.name.toUpperCase()}${C.reset}");
    print("${C.grey}│${C.reset} Entropy:  ${C.cyan}${res.entropyBits} bits${C.reset}");
    print("${C.grey}│${C.reset} Crack Time: ${C.yellow}${res.crackTime}${C.reset}");
    print("${C.grey}└──────────────────────────────────────────────────────────┘${C.reset}\n");
  }

  static void _setConfig(String newPath) {
    if (File(newPath).existsSync()) {
      _configFile.writeAsStringSync(newPath);
      print("${C.green}✅ Database path updated successfully.${C.reset}");
    } else {
      print("${C.red}❌ Error: File not found.${C.reset}");
    }
  }

  static Row? _selectAccount(String searchName) {
    final db = _getDatabase();
    final results = db.select('SELECT * FROM accounts WHERE platform LIKE ?', ['%$searchName%']);
    if (results.isEmpty) {
      print("${C.red}❌ No account found matching: $searchName${C.reset}");
      return null;
    }
    if (results.length == 1) {
      return results.first;
    }
    print("\n${C.yellow}${C.bold}🤔 Multiple accounts found. Please select one:${C.reset}");
    for (int i = 0; i < results.length; i++) {
      print("  ${C.blue}[${i + 1}]${C.reset} ${C.bold}${results[i]['platform']}${C.reset} ${C.grey}| User:${C.reset} ${results[i]['username'] ?? 'N/A'}");
    }
    stdout.write("\n${C.bold}Enter number (1-${results.length}):${C.reset} ");
    String? choice = stdin.readLineSync();
    int? index = int.tryParse(choice ?? "");
    if (index == null || index < 1 || index > results.length) {
      print("${C.red}❌ Invalid selection.${C.reset}");
      return null;
    }
    return results[index - 1];
  }

  static void _listAccounts() {
    final db = _getDatabase();
    final ResultSet results = db.select('SELECT platform, username FROM accounts ORDER BY platform ASC');
    if (results.isEmpty) {
      print("${C.yellow}Vault is empty.${C.reset}");
      return;
    }
    int maxP = 10;
    int maxU = 10;
    for (final row in results) {
      maxP = max(maxP, row['platform'].toString().length);
      maxU = max(maxU, (row['username'] ?? 'No User').toString().length);
    }
    final top = "┌${'─' * (maxP + 2)}┬${'─' * (maxU + 2)}┐";
    final mid = "├${'─' * (maxP + 2)}┼${'─' * (maxU + 2)}┤";
    final bot = "└${'─' * (maxP + 2)}┴${'─' * (maxU + 2)}┘";
    print("\n${C.blue}${C.bold}📦 VAULT CONTENT:${C.reset}");
    print("${C.grey}$top${C.reset}");
    print("${C.grey}│${C.reset} ${C.bold}${'Platform'.padRight(maxP)}${C.reset} ${C.grey}│${C.reset} ${C.bold}${'Username'.padRight(maxU)}${C.reset} ${C.grey}│${C.reset}");
    print("${C.grey}$mid${C.reset}");
    for (final row in results) {
      String p = row['platform'].toString().padRight(maxP);
      String u = (row['username'] ?? 'No User').toString().padRight(maxU);
      print("${C.grey}│${C.reset} ${C.cyan}$p${C.reset} ${C.grey}│${C.reset} $u ${C.grey}│${C.reset}");
    }
    print("${C.grey}$bot${C.reset}");
  }

  static Future<void> _getAndDecryptAccount(String searchName, {bool onlyOTP = false}) async {
    final row = _selectAccount(searchName);
    if (row == null) return;
    if (!onlyOTP) {
      print("\n${C.blue}${C.bold}══ DETAILS: ${row['platform']} ══${C.reset}");
      print("${C.grey}User:${C.reset} ${row['username']}");
    }
    stdout.write("${C.yellow}🔑 Master Password:${C.reset} ");
    stdin.echoMode = false;
    String? masterPass = stdin.readLineSync();
    stdin.echoMode = true;
    print("");
    if (masterPass == null || masterPass.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(masterPass));
    try {
      print("${C.grey}${'-' * 40}${C.reset}");
      if (!onlyOTP) {
        final pass = EncryptionService.decrypt(combinedText: row['password'], masterKeyBytes: mk);
        if (pass == "ERROR: DECRYPTION_FAILED") throw "Invalid Master Password";
        print("${C.green}${C.bold}🔓 Password:${C.reset} $pass");
      }
      if (row['otp_seed'] != null && row['otp_seed'].toString().isNotEmpty) {
        final seed = EncryptionService.decrypt(combinedText: row['otp_seed'], masterKeyBytes: mk);
        if (seed != "ERROR: DECRYPTION_FAILED") {
          final cleanSeed = seed.toUpperCase().replaceAll(' ', '');
          print("${C.yellow}🕒 2FA Live Mode (Press ENTER to exit)${C.reset}");
          
          bool running = true;
          StreamSubscription? sub;
          sub = stdin.listen((event) {
            running = false;
            sub?.cancel();
          });
          while (running) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final code = OTP.generateTOTPCodeString(cleanSeed, now, isGoogle: true);
            final sec = 30 - (DateTime.now().second % 30);
            
            final bar = "█" * (sec ~/ 3) + "░" * (10 - (sec ~/ 3));
            
            stdout.write("${C.clearLine}${C.cyan}${C.bold}OTP Code: ${code.substring(0, 3)} ${code.substring(3)}${C.reset} ${C.grey}[$bar] ${sec}s${C.reset}");
            
            await Future.delayed(Duration(seconds: 1));
          }
          print("\n${C.grey}Live mode ended.${C.reset}");
        }
      }
      if (!onlyOTP) {
        if (row['notes'] != null && row['notes'].isNotEmpty) {
          final notes = EncryptionService.decrypt(combinedText: row['notes'], masterKeyBytes: mk);
          print("${C.grey}📝 Notes:${C.reset} $notes");
        }
      }
    } catch (e) {
      print("${C.red}💥 Error: $e${C.reset}");
    } finally {
      mk.fillRange(0, mk.length, 0);
    }
    print("${C.grey}${'-' * 40}${C.reset}");
  }

  static void _addAccount() {
    print("\n${C.blue}${C.bold}➕ ADD NEW RECORD${C.reset}");
    stdout.write("Platform: "); String platform = stdin.readLineSync() ?? "";
    stdout.write("Username: "); String user = stdin.readLineSync() ?? "";
    stdout.write("Password (Leave empty to use GENERATOR): ");
    stdin.echoMode = false;
    String inputPass = stdin.readLineSync() ?? "";
    stdin.echoMode = true;
    print("");
    String finalPass = inputPass;
    if (inputPass.isEmpty) {
      final res = _runGeneratorFlow();
      if (res == null) {
        print("${C.red}❌ Generation failed. Operation aborted.${C.reset}");
        return;
      }
      finalPass = res.value;
      print("${C.green}✅ Using generated: ${C.bold}$finalPass${C.reset}");
    }
    stdout.write("2FA Seed (Optional): "); String seed = stdin.readLineSync() ?? "";
    stdout.write("\n${C.yellow}🔑 Master Password to encrypt:${C.reset} ");
    stdin.echoMode = false; String? mp = stdin.readLineSync(); stdin.echoMode = true;
    print("");
    if (mp == null || mp.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(mp));
    try {
      final db = _getDatabase();
      final now = DateTime.now().toIso8601String();
      db.execute('INSERT INTO accounts (platform, username, password, otp_seed, created_at, updated_at, category) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [platform, user, EncryptionService.encrypt(finalPass, mk), seed.isNotEmpty ? EncryptionService.encrypt(seed, mk) : null, now, now, 'PERSONAL']);
      print("\n${C.green}✅ Saved successfully.${C.reset}");
    } catch (e) { print("${C.red}❌ Error: $e${C.reset}"); } finally { mk.fillRange(0, mk.length, 0); }
  }

  static void _editAccount(String searchName) {
    final row = _selectAccount(searchName);
    if (row == null) return;

    print("\n${C.yellow}${C.bold}📝 EDITING: ${row['platform']} (${row['username']})${C.reset}");
    stdout.write("New User [${row['username']}]: "); String newUser = stdin.readLineSync() ?? "";
    stdout.write("New Password (blank to keep): "); stdin.echoMode = false; String newPass = stdin.readLineSync() ?? ""; stdin.echoMode = true;

    stdout.write("\n${C.yellow}🔑 Master Password to confirm:${C.reset} ");
    stdin.echoMode = false; String? mp = stdin.readLineSync(); stdin.echoMode = true;
    if (mp == null || mp.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(mp));
    try {
      String encPass = newPass.isNotEmpty ? EncryptionService.encrypt(newPass, mk) : row['password'];
      _getDatabase().execute('UPDATE accounts SET username = ?, password = ?, updated_at = ? WHERE id = ?',
        [newUser.isEmpty ? row['username'] : newUser, encPass, DateTime.now().toIso8601String(), row['id']]);
      print("\n${C.green}✅ Updated successfully.${C.reset}");
    } catch (e) { print("${C.red}❌ Error: $e${C.reset}"); } finally { mk.fillRange(0, mk.length, 0); }
  }

  static void _deleteAccount(String searchName) {
    final row = _selectAccount(searchName);
    if (row == null) return;
    stdout.write("\n${C.red}${C.bold}⚠️  Delete '${row['platform']}' (${row['username']})? (y/N):${C.reset} ");
    if (stdin.readLineSync()?.toLowerCase() == 'y') {
      _getDatabase().execute('DELETE FROM accounts WHERE id = ?', [row['id']]);
      print("${C.green}🗑️  Deleted successfully.${C.reset}");
    } else {
      print("${C.grey}❌ Action cancelled.${C.reset}");
    }
  }
}

void main(List<String> args) => PassGuardCLI.main(args);

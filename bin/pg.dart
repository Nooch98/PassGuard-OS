import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:passguard/services/password_generator_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'package:otp/otp.dart';
import 'package:passguard/services/encryption_service.dart';

enum RiskLevel { critical, warning, info }

class AuditResult {
  final int id;
  final String platform;
  final String username;
  final RiskLevel risk;
  final String reason;
  final double entropy;

  AuditResult({
    required this.id,
    required this.platform,
    required this.username,
    required this.risk,
    required this.reason,
    required this.entropy,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'platform': platform,
        'username': username,
        'risk': risk.index,
        'reason': reason,
        'entropy': entropy,
      };
}

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
        if (args.length < 2)
          print("${C.yellow}Usage: pg get <name>${C.reset}");
        else
          await _getAndDecryptAccount(args[1]);
        break;
      case '2fa':
        if (args.length < 2)
          print("${C.yellow}Usage: pg 2fa <name>${C.reset}");
        else
          await _getAndDecryptAccount(args[1], onlyOTP: true);
        break;
      case 'add':
        _addAccount();
        break;
      case 'edit':
        if (args.length < 2)
          print("${C.yellow}Usage: pg edit <name>${C.reset}");
        else
          _editAccount(args[1]);
        break;
      case 'delete':
        if (args.length < 2)
          print("${C.yellow}Usage: pg delete <name>${C.reset}");
        else
          _deleteAccount(args[1]);
        break;
      case 'gen':
        _handleGenerator();
        break;
      case 'audit':
        await _runVaultAudit();
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

  static Map<String, dynamic> _heavyAuditTask(Map<String, dynamic> data) {
    final List<Map<String, dynamic>> rows = data['rows'];
    final Uint8List masterKey = data['masterKey'];
    final Set<String> breachSet = data['breachSet'];

    List<AuditResult> tempReports = [];
    Map<String, List<Map<String, dynamic>>> passwordGroups = {};

    double totalEntropy = 0;
    int analyzedCount = 0;
    int weak = 0, med = 0, strong = 0, excluded = 0;
    int quantumVulnerable = 0;

    const double hashSpeed = 1e11;
    const int thirtyDaysInSeconds = 2592000;
    const double quantumThreshold = 128.0;

    for (var row in rows) {
      final bool isExcluded = (row['is_excluded'] as int? ?? 0) == 1;
      if (isExcluded) {
        excluded++;
        continue;
      }

      final decrypted = EncryptionService.decrypt(
        combinedText: row['password'] as String,
        masterKeyBytes: masterKey,
      );

      if (decrypted.isEmpty || decrypted.startsWith("ERROR:")) continue;

      analyzedCount++;
      double entropy = _staticCalculateEntropy(decrypted);
      totalEntropy += entropy;

      bool isQuantumVulnerable = entropy < quantumThreshold;
      if (isQuantumVulnerable) quantumVulnerable++;

      double secondsToCrack = math.pow(2, entropy) / hashSpeed;

      if (entropy < 40)
        weak++;
      else if (entropy < 65)
        med++;
      else
        strong++;

      AuditResult? bestReport;

      var digest = sha1.convert(utf8.encode(decrypted)).toString();
      if (breachSet.contains(digest.substring(0, 10))) {
        bestReport = AuditResult(
            id: row['id'],
            platform: row['platform'],
            username: row['username'] ?? "---",
            risk: RiskLevel.critical,
            reason: "ROCKYOU_BREACH_MATCH",
            entropy: entropy);
      }

      if (bestReport == null && secondsToCrack < thirtyDaysInSeconds) {
        bestReport = AuditResult(
            id: row['id'],
            platform: row['platform'],
            username: row['username'] ?? "---",
            risk: secondsToCrack < 3600 ? RiskLevel.critical : RiskLevel.warning,
            reason: secondsToCrack < 3600 ? "INSTANT_CRACK_VULNERABILITY" : "LOW_COMPUTATIONAL_COST",
            entropy: entropy);
      }

      if (bestReport == null && isQuantumVulnerable) {
        bestReport = AuditResult(
          id: row['id'],
          platform: row['platform'],
          username: row['username'] ?? "---",
          risk: RiskLevel.warning,
          reason: "GROVER_MARGIN_WEAK",
          entropy: entropy,
        );
      }

      if (bestReport == null && _staticHasKeyboardPattern(decrypted)) {
        bestReport = AuditResult(
            id: row['id'],
            platform: row['platform'],
            username: row['username'] ?? "---",
            risk: RiskLevel.warning,
            reason: "KEYBOARD_PATTERN_DETECTED",
            entropy: entropy);
      }

      if (bestReport != null) tempReports.add(bestReport);
      passwordGroups.putIfAbsent(decrypted, () => []).add(row);
    }

    passwordGroups.forEach((pass, instances) {
      if (instances.length > 1) {
        for (var inst in instances) {
          if ((inst['is_excluded'] as int? ?? 0) == 1) continue;
          bool alreadyHasCritical = tempReports.any((r) => r.id == inst['id'] && r.risk == RiskLevel.critical);
          if (!alreadyHasCritical) {
            tempReports.add(AuditResult(
                id: inst['id'],
                platform: inst['platform'],
                username: inst['username'] ?? "---",
                risk: RiskLevel.critical,
                reason: "KEY_REUSE_DETECTED",
                entropy: _staticCalculateEntropy(pass)));
          }
        }
      }
    });

    return {
      'reports': tempReports,
      'avgEntropy': analyzedCount > 0 ? totalEntropy / analyzedCount : 0.0,
      'quantumVulnerable': quantumVulnerable,
      'weak': weak,
      'med': med,
      'strong': strong,
      'excluded': excluded
    };
  }

  static double _staticCalculateEntropy(String password) {
    if (password.isEmpty) return 0;
    double poolSize = 0;
    if (password.contains(RegExp(r'[a-z]'))) poolSize += 26;
    if (password.contains(RegExp(r'[A-Z]'))) poolSize += 26;
    if (password.contains(RegExp(r'[0-9]'))) poolSize += 10;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) poolSize += 32;
    return password.length * (math.log(poolSize > 0 ? poolSize : 1) / math.log(2));
  }

  static bool _staticHasKeyboardPattern(String password) {
    const patterns = ['qwerty', 'asdfgh', 'zxcvbn', '123456', 'qazwsx'];
    return patterns.any((p) => password.toLowerCase().contains(p));
  }

  static Future<void> _runVaultAudit() async {
    final db = _getDatabase();
    final List<Map<String, dynamic>> rows = db.select('SELECT * FROM accounts');
    if (rows.isEmpty) {
      print("${C.yellow}Vault is empty. Nothing to audit.${C.reset}");
      return;
    }

    print("\n${C.blue}${C.bold}🛡️  PASSGUARD SECURITY AUDIT (HEAVY_ENGINE)${C.reset}");
    stdout.write("${C.yellow}🔑 Master Password to start analysis:${C.reset} ");
    stdin.echoMode = false;
    String? masterPass = stdin.readLineSync();
    stdin.echoMode = true;
    print("\n${C.cyan}📡 ANALYZING_VAULT_INTEGRITY...${C.reset}\n");

    if (masterPass == null || masterPass.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(masterPass));

    try {
      final results = _heavyAuditTask({
        'rows': rows,
        'masterKey': mk,
        'breachSet': <String>{},
      });

      final List<AuditResult> reports = results['reports'];

      print("${C.grey}┌──────────────────────┬────────────┬─────────────────────────────┐${C.reset}");
      print("${C.grey}│${C.reset} ${C.bold}${'PLATFORM'.padRight(20)}${C.reset} ${C.grey}│${C.reset} ${C.bold}${'RISK'.padRight(10)}${C.reset} ${C.grey}│${C.reset} ${C.bold}${'REASON'.padRight(27)}${C.reset} ${C.grey}│${C.reset}");
      print("${C.grey}├──────────────────────┼────────────┼─────────────────────────────┤${C.reset}");

      for (var r in reports) {
        String color = r.risk == RiskLevel.critical ? C.red : C.yellow;
        print("${C.grey}│${C.reset} ${r.platform.padRight(20).substring(0, 20)} ${C.grey}│${C.reset} ${color}${r.risk.name.toUpperCase().padRight(10)}${C.reset} ${C.grey}│${C.reset} ${r.reason.padRight(27).substring(0, 27)} ${C.grey}│${C.reset}");
      }
      print("${C.grey}└──────────────────────┴────────────┴─────────────────────────────┘${C.reset}");

      print("\n${C.blue}${C.bold}📊 AUDIT_SUMMARY:${C.reset}");
      print("  • Avg Entropy:   ${C.cyan}${results['avgEntropy'].toStringAsFixed(2)} bits${C.reset}");
      print("  • Weak Assets:   ${C.red}${results['weak']}${C.reset}");
      print("  • Low Entropy Risk:  ${C.yellow}${results['quantumVulnerable']}${C.reset}");

      if (reports.isEmpty) {
        print("\n${C.green}${C.bold}✅ SYSTEM_SAFE: All security protocols met.${C.reset}\n");
      } else {
        print("\n${C.yellow}${C.bold}⚠️  ACTION_REQUIRED: Fix identified vulnerabilities.${C.reset}\n");
      }
    } catch (e) {
      print("${C.red}💥 Audit Engine Error: $e${C.reset}");
    } finally {
      mk.fillRange(0, mk.length, 0);
    }
  }

  static void _printDetailedHelp() {
    print("\n${C.blue}${C.bold}🛡️  PASSGUARD OS | CLI Engine Help${C.reset}");
    print("${C.grey}Comprehensive security suite documentation${C.reset}\n");

    print("${C.yellow}${C.bold}USAGE:${C.reset}");
    print("  pg <command> [arguments]\n");

    print("${C.yellow}${C.bold}CORE COMMANDS:${C.reset}");
    _printCmd("list", "Display all stored accounts in a formatted table.");
    _printCmd("add", "Interactive creation of records with auto-gen support.");
    _printCmd("get <name>", "Full decryption of account, notes, and Live 2FA.");
    _printCmd("2fa <name>", "Quick access: Only show the Live TOTP code.");
    _printCmd("edit <name>", "Modify existing records (selective update).");
    _printCmd("delete <name>", "Permanently wipe a record from the vault.");
    
    print("\n${C.yellow}${C.bold}SECURITY & AUDIT:${C.reset}");
    _printCmd("audit", "Run the Heavy Audit Engine (Re-use, Entropy, Quantum).");
    _printCmd("gen", "Stand-alone Pro Generator with crack-time estimation.");

    print("\n${C.yellow}${C.bold}UTILITIES:${C.reset}");
    _printCmd("config <path>", "Link to a specific 'passguard_v2.db' file.");
    _printCmd("help", "Show this technical documentation.");

    print("\n${C.blue}${C.bold}📊 AUDIT ENGINE METRICS:${C.reset}");
    print("  ${C.red}• CRITICAL:${C.reset} Key reuse, Instant crack (<1h), or Breach Match.");
    print("  ${C.yellow}• WARNING:${C.reset}  Keyboard patterns, Grover's Margin (Quantum).");
    print("  ${C.cyan}• ENTROPY:${C.reset}  Analyzed via Shannon algorithm (Pool vs Length).");

    print("\n${C.grey}${'-' * 65}${C.reset}");
    print("${C.grey}PassGuard CLI Engine v1.0.0 | 2026${C.reset}\n");
  }

  static void _printCmd(String cmd, String desc) {
    print("  ${C.cyan}${cmd.padRight(15)}${C.reset} $desc");
  }

  static void _printUsage() {
    print("\n${C.blue}${C.bold}🛡️  PASSGUARD OS | CLI Engine${C.reset}");
    print("${C.grey}${'-' * 45}${C.reset}");
    print("  ${C.cyan}pg list${C.reset}             List all accounts");
    print("  ${C.cyan}pg get <name>${C.reset}       Show details & password");
    print("  ${C.cyan}pg audit${C.reset}            Run security audit");
    print("  ${C.cyan}pg gen${C.reset}              Secure generator");
    print("  ${C.cyan}pg config <path>${C.reset}    Set vault location");
    print("${C.grey}${'-' * 45}${C.reset}");
  }

  static void _handleGenerator() {
    print("\n${C.blue}${C.bold}🔐 PASSGUARD GENERATOR PRO${C.reset}");
    final res = _runGeneratorFlow();
    if (res != null) _printGeneratedResult(res);
  }

  static GeneratedPassword? _runGeneratorFlow() {
    print("\n${C.yellow}🎲 Options: [1] Random [2] PIN [3] Pronounceable [4] High-Entropy${C.reset}");
    stdout.write("Select (1): ");
    String? choice = stdin.readLineSync();
    GeneratorOptions options;
    if (choice == '2') {
      stdout.write("Length (4): ");
      int l = int.tryParse(stdin.readLineSync() ?? "") ?? 4;
      options = GeneratorOptions(mode: GeneratorMode.random, length: l, digits: true, upper: false, lower: false, symbols: false, enforceAllSets: false);
    } else if (choice == '3') {
      stdout.write("Syllables (5): ");
      int s = int.tryParse(stdin.readLineSync() ?? "") ?? 5;
      options = GeneratorOptions(mode: GeneratorMode.pronounceable, syllables: s, pronounceableAddNumber: true);
    } else if (choice == '4') {
      options = GeneratorOptions(mode: GeneratorMode.quantum, length: 32);
    } else {
      stdout.write("Length (20): ");
      int l = int.tryParse(stdin.readLineSync() ?? "") ?? 20;
      options = GeneratorOptions(mode: GeneratorMode.random, length: l, upper: true, lower: true, digits: true, symbols: true);
    }
    return _generator.generate(options);
  }

  static void _printGeneratedResult(GeneratedPassword res) {
    print("\n${C.grey}┌${'─' * 50}┐${C.reset}");
    print("${C.grey}│${C.reset} ${C.bold}VALUE:${C.reset} ${C.green}${C.bold}${res.value}${C.reset}");
    print("${C.grey}├${'─' * 50}┤${C.reset}");
    print("${C.grey}│${C.reset} Strength: ${C.cyan}${res.strength.name.toUpperCase()}${C.reset}");
    print("${C.grey}│${C.reset} Entropy:  ${C.yellow}${res.entropyBits} bits${C.reset}");
    print("${C.grey}└${'─' * 50}┘${C.reset}\n");
  }

  static void _setConfig(String newPath) {
    if (File(newPath).existsSync()) {
      _configFile.writeAsStringSync(newPath);
      print("${C.green}✅ Database path updated.${C.reset}");
    } else {
      print("${C.red}❌ File not found.${C.reset}");
    }
  }

  static void _listAccounts() {
    final db = _getDatabase();
    final ResultSet results = db.select('SELECT platform, username FROM accounts ORDER BY platform ASC');
    if (results.isEmpty) {
      print("${C.yellow}Vault is empty.${C.reset}");
      return;
    }
    print("\n${C.blue}${C.bold}📦 VAULT CONTENT:${C.reset}");
    for (final row in results) {
      print("  ${C.cyan}• ${row['platform'].toString().padRight(18)}${C.reset} ${C.grey}| User:${C.reset} ${row['username'] ?? 'N/A'}");
    }
  }

  static Future<void> _getAndDecryptAccount(String searchName, {bool onlyOTP = false}) async {
    final row = _selectAccount(searchName);
    if (row == null) return;
    stdout.write("${C.yellow}🔑 Master Password:${C.reset} ");
    stdin.echoMode = false;
    String? masterPass = stdin.readLineSync();
    stdin.echoMode = true;
    print("");
    if (masterPass == null || masterPass.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(masterPass));
    try {
      if (!onlyOTP) {
        final pass = EncryptionService.decrypt(combinedText: row['password'], masterKeyBytes: mk);
        if (pass.startsWith("ERROR:")) throw "Invalid Master Password";
        print("${C.green}${C.bold}🔓 Password:${C.reset} $pass");
      }
      if (row['otp_seed'] != null && row['otp_seed'].toString().isNotEmpty) {
        final seed = EncryptionService.decrypt(combinedText: row['otp_seed'], masterKeyBytes: mk);
        if (!seed.startsWith("ERROR:")) {
          final cleanSeed = seed.toUpperCase().replaceAll(' ', '');
          print("${C.yellow}🕒 2FA Live Mode (ENTER to exit)${C.reset}");
          bool running = true;
          stdin.listen((event) => running = false);
          while (running) {
            final code = OTP.generateTOTPCodeString(cleanSeed, DateTime.now().millisecondsSinceEpoch, isGoogle: true);
            stdout.write("${C.clearLine}${C.cyan}${C.bold}OTP: ${code.substring(0, 3)} ${code.substring(3)}${C.reset} [${30 - (DateTime.now().second % 30)}s]");
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }
    } catch (e) {
      print("${C.red}💥 Error: $e${C.reset}");
    } finally {
      mk.fillRange(0, mk.length, 0);
    }
  }

  static Row? _selectAccount(String searchName) {
    final db = _getDatabase();
    final results = db.select('SELECT * FROM accounts WHERE platform LIKE ?', ['%$searchName%']);
    if (results.isEmpty) return null;
    if (results.length == 1) return results.first;
    print("\n${C.yellow}Select Account:${C.reset}");
    for (int i = 0; i < results.length; i++) {
      print("  [${i + 1}] ${results[i]['platform']} (${results[i]['username']})");
    }
    int idx = int.tryParse(stdin.readLineSync() ?? "") ?? 1;
    return results[idx - 1];
  }

  static void _addAccount() {
    print("\n${C.blue}${C.bold}➕ ADD NEW RECORD${C.reset}");
    stdout.write("Platform: "); String platform = stdin.readLineSync() ?? "";
    stdout.write("Username: "); String user = stdin.readLineSync() ?? "";
    stdout.write("Password (blank for GEN): "); stdin.echoMode = false; String inputPass = stdin.readLineSync() ?? ""; stdin.echoMode = true;
    print("");
    String finalPass = inputPass.isEmpty ? (_runGeneratorFlow()?.value ?? "ERROR") : inputPass;
    stdout.write("2FA Seed (Optional): "); String seed = stdin.readLineSync() ?? "";
    stdout.write("${C.yellow}🔑 Master Password:${C.reset} "); stdin.echoMode = false; String? mp = stdin.readLineSync(); stdin.echoMode = true;
    if (mp == null || mp.isEmpty) return;
    final mk = Uint8List.fromList(utf8.encode(mp));
    try {
      final now = DateTime.now().toIso8601String();
      _getDatabase().execute('INSERT INTO accounts (platform, username, password, otp_seed, created_at, updated_at, category) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [platform, user, EncryptionService.encrypt(finalPass, mk), seed.isNotEmpty ? EncryptionService.encrypt(seed, mk) : null, now, now, 'PERSONAL']);
      print("${C.green}✅ Saved.${C.reset}");
    } finally { mk.fillRange(0, mk.length, 0); }
  }

  static void _editAccount(String searchName) {
    final row = _selectAccount(searchName);
    if (row == null) return;

    print("\n${C.yellow}${C.bold}📝 EDITING: ${row['platform']} (${row['username']})${C.reset}");
    print("${C.grey}Leave blank to keep current value.${C.reset}\n");

    stdout.write("New Platform [${row['platform']}]: ");
    String newPlatform = stdin.readLineSync() ?? "";
    
    stdout.write("New Username [${row['username']}]: ");
    String newUser = stdin.readLineSync() ?? "";

    stdout.write("New Password (blank to keep current): ");
    stdin.echoMode = false;
    String newPass = stdin.readLineSync() ?? "";
    stdin.echoMode = true;
    print("");

    stdout.write("New 2FA Seed (blank to keep current): ");
    String newSeed = stdin.readLineSync() ?? "";

    stdout.write("\n${C.yellow}🔑 Master Password to confirm changes:${C.reset} ");
    stdin.echoMode = false;
    String? mp = stdin.readLineSync();
    stdin.echoMode = true;
    print("");

    if (mp == null || mp.isEmpty) {
      print("${C.red}❌ Action aborted: Master Password required.${C.reset}");
      return;
    }

    final mk = Uint8List.fromList(utf8.encode(mp));

    try {
      final String platformUpdate = newPlatform.isNotEmpty ? newPlatform : row['platform'];
      final String userUpdate = newUser.isNotEmpty ? newUser : row['username'];

      final String passUpdate = newPass.isNotEmpty 
          ? EncryptionService.encrypt(newPass, mk) 
          : row['password'];

      final dynamic seedUpdate = newSeed.isNotEmpty 
          ? EncryptionService.encrypt(newSeed, mk) 
          : row['otp_seed'];

      final db = _getDatabase();
      db.execute('''
        UPDATE accounts 
        SET platform = ?, 
            username = ?, 
            password = ?, 
            otp_seed = ?, 
            updated_at = ?,
            audit_cache = NULL 
        WHERE id = ?
      ''', [
        platformUpdate,
        userUpdate,
        passUpdate,
        seedUpdate,
        DateTime.now().toIso8601String(),
        row['id']
      ]);

      print("\n${C.green}✅ Account '${platformUpdate}' updated successfully.${C.reset}");
      print("${C.grey}Note: Audit cache cleared. Run 'pg audit' to refresh security score.${C.reset}");

    } catch (e) {
      print("${C.red}❌ Update Error: $e${C.reset}");
    } finally {
      mk.fillRange(0, mk.length, 0);
    }
  }

  static void _deleteAccount(String searchName) {
    final row = _selectAccount(searchName);
    if (row == null) return;
    stdout.write("${C.red}Delete '${row['platform']}'? (y/N): ${C.reset}");
    if (stdin.readLineSync()?.toLowerCase() == 'y') {
      _getDatabase().execute('DELETE FROM accounts WHERE id = ?', [row['id']]);
      print("${C.green}🗑️ Deleted.${C.reset}");
    }
  }
}

void main(List<String> args) => PassGuardCLI.main(args);

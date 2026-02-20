import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:otp/otp.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../services/auth_service.dart';
import '../services/compression_service.dart';
import '../services/db_helper.dart';
import '../services/encryption_service.dart';
import '../services/file_service.dart';
import '../services/filevaultscreen.dart';
import '../services/sync_service.dart';
import '../services/session_manager.dart';
import '../services/security_analyzer.dart';
import '../models/password_model.dart';
import '../services/SteganographyService.dart';
import '../widgets/password_generator_dialog.dart';
import '../models/recovery_code_model.dart';

Timer? _clipboardTimer;

class HomePage extends StatefulWidget {
  final Uint8List masterKey;
  const HomePage({super.key, required this.masterKey});
  
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<PasswordModel> _passwords = [];
  bool _isSearching = false;
  final _searchController = TextEditingController();
  List<PasswordModel> _filteredPasswords = [];
  Timer? _otpRefreshTimer;
  double _currentHealthScore = 0;
  int _selectedIndex = 0;

  String _sortBy = 'platform';
  bool _sortAscending = true;

  String? _filterCategory;
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPasswords();

    SessionManager().initialize(
      onTimeout: _handleSessionTimeout,
      timeout: Duration(minutes: 5),
    );
    
    _otpRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
    
    _applyScreenshotProtection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _otpRefreshTimer?.cancel();
    _searchController.dispose();
    _clipboardTimer?.cancel();
    SessionManager().dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      SessionManager().resetTimer();
    } else if (state == AppLifecycleState.resumed) {
      SessionManager().resetTimer();
    }
  }

  Future<void> _applyScreenshotProtection() async {
    if (Platform.isAndroid) {
      bool enabled = await AuthService.getScreenshotProtection();
      if (enabled) {
        try {
          await FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
        } catch (e) {
          debugPrint('Screenshot protection not available: $e');
        }
      }
    }
  }

  void _handleSessionTimeout() {
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SESSION_EXPIRED: VAULT_LOCKED'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _onUserInteraction() {
    SessionManager().resetTimer();
  }

  Future<void> _loadPasswords({String? query}) async {
    final db = await DBHelper.database;

    String? whereClause;
    List<dynamic>? whereArgs;

    if (query != null && query.isNotEmpty) {
      whereClause = 'platform LIKE ? OR username LIKE ?';
      whereArgs = ['%$query%', '%$query%'];
    }

    if (_filterCategory != null) {
      if (whereClause != null) {
        whereClause += ' AND category = ?';
        whereArgs!.add(_filterCategory);
      } else {
        whereClause = 'category = ?';
        whereArgs = [_filterCategory];
      }
    }

    if (_showFavoritesOnly) {
      if (whereClause != null) {
        whereClause += ' AND is_favorite = 1';
      } else {
        whereClause = 'is_favorite = 1';
      }
    }

    String orderBy;
    switch (_sortBy) {
      case 'created':
        orderBy = 'created_at ${_sortAscending ? 'ASC' : 'DESC'}';
        break;
      case 'lastUsed':
        orderBy = 'last_used ${_sortAscending ? 'DESC' : 'ASC'} NULLS LAST';
        break;
      case 'favorite':
        orderBy = 'is_favorite ${_sortAscending ? 'DESC' : 'ASC'}, platform ASC';
        break;
      default:
        orderBy = 'platform ${_sortAscending ? 'ASC' : 'DESC'}';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'accounts',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );

    setState(() {
      _passwords = maps.map((m) => PasswordModel.fromMap(m)).toList();
      _currentHealthScore = _calculateHealthScore();
    });
  }

  double _calculateHealthScore() {
    if (_passwords.isEmpty) return 100;
    final result = SecurityAnalyzer.analyze(_passwords);
    return result.overallScore;
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      shape: const Border(top: BorderSide(color: Color(0xFF00FBFF), width: 2)),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const Text(
              '> SORT_OPTIONS',
              style: TextStyle(color: Color(0xFF00FBFF), fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            _buildSortOption('ALPHABETICAL', 'platform', Icons.sort_by_alpha),
            _buildSortOption('DATE_CREATED', 'created', Icons.calendar_today),
            _buildSortOption('LAST_USED', 'lastUsed', Icons.access_time),
            _buildSortOption('FAVORITES_FIRST', 'favorite', Icons.star),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String label, String sortKey, IconData icon) {
    final bool isSelected = _sortBy == sortKey;
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFF00FBFF) : Colors.white54),
      title: Text(label, style: TextStyle(color: isSelected ? const Color(0xFF00FBFF) : Colors.white)),
      trailing: isSelected
          ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, 
                 color: const Color(0xFF00FBFF), size: 18)
          : null,
      onTap: () {
        setState(() {
          if (_sortBy == sortKey) {
            _sortAscending = !_sortAscending;
          } else {
            _sortBy = sortKey;
            _sortAscending = true;
          }
        });
        _loadPasswords();
        Navigator.pop(context);
      },
    );
  }

  void _showFilterMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      shape: const Border(top: BorderSide(color: Color(0xFF00FBFF), width: 2)),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const Text(
              '> FILTER_OPTIONS',
              style: TextStyle(color: Color(0xFF00FBFF), fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            SwitchListTile(
              title: const Text('FAVORITES_ONLY', style: TextStyle(color: Colors.white)),
              value: _showFavoritesOnly,
              activeColor: const Color(0xFF00FBFF),
              onChanged: (val) {
                setState(() => _showFavoritesOnly = val);
                _loadPasswords();
                Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('CATEGORY:', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            _buildFilterOption('ALL', null, Icons.all_inclusive),
            _buildFilterOption('PERSONAL', 'PERSONAL', Icons.person),
            _buildFilterOption('WORK', 'WORK', Icons.business_center),
            _buildFilterOption('FINANCE', 'FINANCE', Icons.account_balance_wallet),
            _buildFilterOption('SOCIAL', 'SOCIAL', Icons.public),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(String label, String? category, IconData icon) {
    final bool isSelected = _filterCategory == category;
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFFFF00FF) : Colors.white54),
      title: Text(label, style: TextStyle(color: isSelected ? const Color(0xFFFF00FF) : Colors.white)),
      trailing: isSelected ? const Icon(Icons.check, color: Color(0xFFFF00FF)) : null,
      onTap: () {
        setState(() => _filterCategory = category);
        _loadPasswords();
        Navigator.pop(context);
      },
    );
  }

  Future<void> _toggleFavorite(PasswordModel password) async {
    final db = await DBHelper.database;
    await db.update(
      'accounts',
      {'is_favorite': password.isFavorite ? 0 : 1},
      where: 'id = ?',
      whereArgs: [password.id],
    );
    _loadPasswords();
    HapticFeedback.lightImpact();
  }

  void _showSecurityAuditDetailed() {
    final result = SecurityAnalyzer.analyze(_passwords);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _getHealthColor(result.overallScore), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        title: Text(
          '> DETAILED_SECURITY_AUDIT',
          style: TextStyle(color: _getHealthColor(result.overallScore), fontFamily: 'monospace', fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAuditRow('TOTAL_ACCOUNTS', result.totalPasswords.toString(), Colors.white),
              _buildAuditRow('2FA_PROTECTED', '${result.twoFactorEnabled}', const Color(0xFF00FBFF)),
              _buildAuditRow('WEAK_PASSWORDS', '${result.weakPasswords}', 
                             result.weakPasswords > 0 ? Colors.red : Colors.green),
              _buildAuditRow('REUSED_PASSWORDS', '${result.reusedPasswords}', 
                             result.reusedPasswords > 0 ? Colors.red : Colors.green),
              _buildAuditRow('OLD_PASSWORDS_90D+', '${result.oldPasswords}', 
                             result.oldPasswords > 0 ? Colors.orange : Colors.green),
              
              const SizedBox(height: 25),
              const Text('OVERALL_SECURITY:', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: result.overallScore / 100,
                backgroundColor: Colors.white10,
                color: _getHealthColor(result.overallScore),
                minHeight: 12,
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  '${result.overallScore.toInt()}%',
                  style: TextStyle(
                    color: _getHealthColor(result.overallScore),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  SecurityAnalyzer.getRecommendation(result),
                  style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 11, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
              
              if (result.weakPasswordsList.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('WEAK_ACCOUNTS:', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...result.weakPasswordsList.take(5).map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${p.platform}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                )),
              ],
              
              if (result.oldPasswordsList.isNotEmpty) ...[
                const SizedBox(height: 15),
                const Text('OLD_ACCOUNTS:', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...result.oldPasswordsList.take(5).map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${p.platform}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ACKNOWLEDGE', style: TextStyle(color: _getHealthColor(result.overallScore))),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditRow(String label, String value, Color valColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('> $label', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(value, style: TextStyle(color: valColor, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Color _getHealthColor(double score) {
    if (score >= 80) return const Color(0xFF00FF00);
    if (score >= 60) return const Color(0xFF00FBFF);
    if (score >= 40) return const Color(0xFFFFFF00);
    return Colors.red;
  }

  String _getHealthStatusText(double score) {
    if (score >= 90) return "CORE_STABLE";
    if (score >= 70) return "SECURE_MARGIN";
    if (score >= 50) return "WEAK_POINTS";
    if (score > 0) return "THREAT_DETECTED";
    return "BUNKER_EMPTY";
  }

  Future<void> _handleImageInjection() async {
    final security = SecurityController();

    try {
      security.pauseLocking();

      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
      security.resumeLocking();
      if (pickedFile == null) return;

      String encryptedData = await _prepareEncryptedDataStream();

      Uint8List imageBytes = await pickedFile.readAsBytes();

      final stegoService = SteganographyService();
      Uint8List ghostImage = await stegoService.hideVaultInImage(imageBytes, encryptedData);

      if (!mounted) return;

      await _saveImageToGallery(ghostImage);

      _showSuccessSnackBar("GHOST_IMAGE_CREATED: INJECTION_SUCCESSFUL");

    } catch (e) {
      security.resumeLocking();
      _showErrorSnackBar("INJECTION_FAILED: ${e.toString()}");
    }
  }

  Future<void> _handleImageExtraction() async {
    final security = SecurityController();

    try {
      security.pauseLocking();
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

      security.resumeLocking();
      if (pickedFile == null) return;

      Uint8List imageBytes = await pickedFile.readAsBytes();
      final stegoService = SteganographyService();

      String extractedData = await stegoService.extractVaultFromImage(imageBytes);
      if (!mounted) return;
      await _processImportedData(extractedData);

    } catch (e) {
      security.resumeLocking();

      if (mounted) {
        _showErrorSnackBar("EXTRACTION_FAILED: INVALID_OR_EMPTY_GHOST_IMAGE");
      }
    }
  }

  Future<String> _prepareEncryptedDataStream() async {
    final db = await DBHelper.database;

    final List<Map<String, dynamic>> accountsRows = await db.query('accounts');

    final List<Map<String, dynamic>> recoveryCodesRows = await db.query('recovery_codes');

    final Map<String, dynamic> vaultData = {
      'accounts': accountsRows,
      'recovery_codes': recoveryCodesRows,
      'exported_at': DateTime.now().toIso8601String(),
      'version': '2.0',
    };
    
    String jsonData = jsonEncode(vaultData);

    return EncryptionService.encrypt(
      jsonData,
      String.fromCharCodes(widget.masterKey)
    );
  }

  Future<void> _processImportedData(String encryptedData) async {
    try {
      final String decryptedJson = EncryptionService.decrypt(
        encryptedData,
        widget.masterKey
      );

      final Map<String, dynamic> vaultData = jsonDecode(decryptedJson);

      List<dynamic> accounts;
      List<dynamic> recoveryCodes = [];
      
      if (vaultData.containsKey('accounts')) {
        accounts = vaultData['accounts'] as List<dynamic>;
        if (vaultData.containsKey('recovery_codes')) {
          recoveryCodes = vaultData['recovery_codes'] as List<dynamic>;
        }
      } else {
        accounts = vaultData as List<dynamic>;
      }
      
      final db = await DBHelper.database;
      final batch = db.batch();

      for (var item in accounts) {
        batch.insert(
          'accounts',
          item,
          conflictAlgorithm: ConflictAlgorithm.replace
        );
      }

      for (var code in recoveryCodes) {
        batch.insert(
          'recovery_codes',
          code,
          conflictAlgorithm: ConflictAlgorithm.replace
        );
      }

      await batch.commit();

      _loadPasswords();
      
      String message = "IMPORT_SUCCESS: ${accounts.length} ACCOUNTS";
      if (recoveryCodes.isNotEmpty) {
        message += " + ${recoveryCodes.length} RECOVERY_CODES";
      }
      _showSuccessSnackBar(message);
      
    } catch (e) {
      _showErrorSnackBar("DECRYPTION_FAILED: WRONG_KEY_OR_CORRUPT_DATA");
    }
  }

  Future<void> _saveImageToGallery(Uint8List imageBytes) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'SAVE_GHOST_VAULT_IMAGE',
        fileName: 'GHOST_VAULT_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(imageBytes);
        _showSuccessSnackBar("FILE_EXPORTED_SUCCESSFULLY");
      }
    } else {
      final directory = await getTemporaryDirectory();
      final String fileName = "GHOST_VAULT_${DateTime.now().millisecondsSinceEpoch}.png";
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(imageBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'PassGuard OS: Cold Backup');
    }
  }

  void _showSystemMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      isScrollControlled: true,
      shape: const Border(top: BorderSide(color: Color(0xFF00FBFF), width: 2)),
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text("> SYSTEM_CORE_SETTINGS",
                    style: TextStyle(
                        color: Color(0xFF00FBFF),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
                const SizedBox(height: 20),

                // BIOMETRIC
                ListTile(
                  leading: const Icon(Icons.fingerprint, color: Color(0xFF00FBFF)),
                  title: const Text("LINK_BIOMETRIC_VAULT"),
                  onTap: () async {
                    Navigator.pop(context);
                    await AuthService.saveMasterKeyForBio(utf8.decode(widget.masterKey));
                    _showSuccessSnackBar("BIO_LINK_SUCCESS: ENCRYPTED_IN_HARDWARE");
                  },
                ),

                // STEALTH CODE
                /*ListTile(
                  leading: const Icon(Icons.dialpad, color: Color(0xFF00FBFF)),
                  title: const Text("CHANGE_STEALTH_CODE"),
                  onTap: () { Navigator.pop(context); _showStealthCodeDialog(); },
                ),*/

                const Divider(color: Colors.white10),

                // SESSION TIMEOUT
                ListTile(
                  leading: const Icon(Icons.timer, color: Color(0xFFFF00FF)),
                  title: const Text("SESSION_TIMEOUT"),
                  subtitle: FutureBuilder<int>(
                    future: AuthService.getSessionTimeout(),
                    builder: (context, snapshot) {
                      return Text(
                        '${snapshot.data ?? 5} minutes',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      );
                    },
                  ),
                  onTap: () { Navigator.pop(context); _showSessionTimeoutDialog(); },
                ),

                // AUTO LOCK
                FutureBuilder<bool>(
                  future: AuthService.getAutoLockEnabled(),
                  builder: (context, snapshot) {
                    return SwitchListTile(
                      secondary: const Icon(Icons.lock_clock, color: Color(0xFFFF00FF)),
                      title: const Text("AUTO_LOCK_ON_MINIMIZE"),
                      subtitle: const Text('Lock vault when app is minimized', 
                                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                      value: snapshot.data ?? true,
                      activeColor: const Color(0xFF00FBFF),
                      onChanged: (val) async {
                        await AuthService.setAutoLockEnabled(val);
                        setState(() {});
                      },
                    );
                  },
                ),

                // SCREENSHOT PROTECTION
                if (Platform.isAndroid)
                  FutureBuilder<bool>(
                    future: AuthService.getScreenshotProtection(),
                    builder: (context, snapshot) {
                      return SwitchListTile(
                        secondary: const Icon(Icons.screenshot, color: Color(0xFFFF00FF)),
                        title: const Text("SCREENSHOT_PROTECTION"),
                        subtitle: const Text('Prevent screenshots (requires restart)', 
                                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                        value: snapshot.data ?? true,
                        activeColor: const Color(0xFF00FBFF),
                        onChanged: (val) async {
                          await AuthService.setScreenshotProtection(val);
                          setState(() {});
                          _showSuccessSnackBar("RESTART_APP_TO_APPLY");
                        },
                      );
                    },
                  ),

                const Divider(color: Colors.white10),

                // QR TRANSFER
                ListTile(
                  leading: const Icon(Icons.qr_code_2, color: Color(0xFFFF00FF)),
                  title: const Text("GENERATE_TRANSMISSION_QR"),
                  onTap: () { Navigator.pop(context); _showQRGenerator(); },
                ),

                ListTile(
                  leading: const Icon(Icons.qr_code_scanner, color: Color(0xFFFF00FF)),
                  title: const Text("RECEIVE_DATA_STREAM"),
                  onTap: () { Navigator.pop(context); _showScanner(); },
                ),

                const Divider(color: Colors.white10),

                // COLD STORAGE
                ListTile(
                  leading: const Icon(Icons.ac_unit, color: Color(0xFF00FBFF)),
                  title: const Text("COLD_STORAGE_PROTOCOLS"),
                  subtitle: const Text("Steganographic image injection",
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                  onTap: () { Navigator.pop(context); _showColdStorageDialog(); },
                ),

                // SECURITY AUDIT
                ListTile(
                  leading: const Icon(Icons.analytics_outlined, color: Color(0xFF00FBFF)),
                  title: const Text("CORE_SECURITY_AUDIT"),
                  subtitle: const Text("Analyze bunker integrity and password health",
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    _showSecurityAuditDetailed();
                  },
                ),

                // EXPORT DATA
                ListTile(
                  leading: const Icon(Icons.file_download, color: Color(0xFF00FBFF)),
                  title: const Text("EXPORT_VAULT_CSV"),
                  subtitle: const Text("Export passwords to encrypted CSV",
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                  onTap: () { Navigator.pop(context); _exportToCSV(); },
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSessionTimeoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text('> SESSION_TIMEOUT', 
                          style: TextStyle(color: Color(0xFF00FBFF), fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select inactivity timeout:', 
                       style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 20),
            _buildTimeoutOption('1 MINUTE', 1),
            _buildTimeoutOption('5 MINUTES', 5),
            _buildTimeoutOption('15 MINUTES', 15),
            _buildTimeoutOption('30 MINUTES', 30),
            _buildTimeoutOption('NEVER', 0),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutOption(String label, int minutes) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      onTap: () async {
        await AuthService.setSessionTimeout(minutes);
        if (minutes > 0) {
          SessionManager().setTimeoutDuration(Duration(minutes: minutes));
          SessionManager().setEnabled(true);
        } else {
          SessionManager().setEnabled(false);
        }
        Navigator.pop(context);
        _showSuccessSnackBar('TIMEOUT_SET: $label');
      },
    );
  }

  void _showColdStorageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
        title: const Text("> COLD_STORAGE_MENU",
            style: TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace', fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTerminalButton(
              icon: Icons.photo_library,
              label: "INJECT_INTO_IMAGE",
              onPressed: () { Navigator.pop(context); _handleImageInjection(); },
            ),
            const SizedBox(height: 15),
            _buildTerminalButton(
              icon: Icons.visibility,
              label: "EXTRACT_FROM_IMAGE",
              onPressed: () { Navigator.pop(context); _handleImageExtraction(); },
            ),
          ],
        ),
      ),
    );
  }

  void _showStealthCodeDialog() {
    final codeC = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text("> SET_NEW_STEALTH_CODE", 
                          style: TextStyle(color: Color(0xFF00FBFF), fontSize: 16)),
        content: TextField(
          controller: codeC,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: "Example: 5566",
            hintStyle: TextStyle(color: Colors.white24),
          ),
          style: const TextStyle(letterSpacing: 5, color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FBFF),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (codeC.text.isNotEmpty) {
                await AuthService.setStealthCode(codeC.text);
                Navigator.pop(context);
                _showSuccessSnackBar("STEALTH_CODE_UPDATED");
              }
            },
            child: const Text("UPDATE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showQRGenerator() {
    try {
      _generateAndShowQR();
    } catch (e) {
      _showErrorSnackBar("EXPORT_FAILED: ENCRYPTION_ERROR");
    }
  }

  Future<void> _generateAndShowQR() async {
    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Color(0xFF00FBFF)),
          ),
        );
      }

      final String rawData = await SyncService.exportToPackage(_passwords);

      final String encryptedData = EncryptionService.encrypt(
          rawData,
          utf8.decode(widget.masterKey)
      );
      
      final String compressedData = CompressionService.compressForQR(encryptedData);

      final bool fitsInQR = CompressionService.fitsInQR(compressedData);
      final double sizeKB = CompressionService.getSizeKB(compressedData);

      if (mounted) Navigator.pop(context);

      if (!fitsInQR) {
        if (!mounted) return;

        final int avgSizePerPassword = compressedData.length ~/ _passwords.length;
        final int maxPasswords = 2900 ~/ avgSizePerPassword;
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF0A0A0E),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Colors.red, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red),
                SizedBox(width: 10),
                Text('QR_TOO_LARGE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your vault is too large for a single QR code.',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        _buildStatRow('Current size:', '${sizeKB.toStringAsFixed(1)} KB', Colors.red),
                        _buildStatRow('QR limit:', '2.8 KB', Colors.white54),
                        const Divider(color: Colors.white10, height: 20),
                        _buildStatRow('Your passwords:', '${_passwords.length}', Colors.white70),
                        _buildStatRow('Estimated max:', '~$maxPasswords', Colors.orange),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Recommended alternatives:',
                    style: TextStyle(color: Color(0xFF00FBFF), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildAlternativeOption(
                    icon: Icons.image,
                    label: 'Use Steganography',
                    description: 'Hide vault in an image (unlimited size)',
                  ),
                  const SizedBox(height: 8),
                  _buildAlternativeOption(
                    icon: Icons.file_download,
                    label: 'Export to CSV',
                    description: 'Export and transfer manually',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FBFF)),
                icon: const Icon(Icons.image, color: Colors.black, size: 18),
                label: const Text('USE_STEGANOGRAPHY', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(context);
                  _showColdStorageDialog();
                },
              ),
            ],
          ),
        );
        return;
      }

      final compressionBytes = base64Url.decode(compressedData);
      final double compressionRatio = CompressionService.getCompressionRatio(
        encryptedData, 
        Uint8List.fromList(compressionBytes)
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0E),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF00FBFF), width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          title: const Row(
            children: [
              Icon(Icons.qr_code_2, color: Color(0xFF00FBFF)),
              SizedBox(width: 10),
              Text("DATA_STREAM_READY", style: TextStyle(color: Color(0xFF00FBFF), fontSize: 14, fontFamily: 'monospace')),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00FBFF).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      _buildStatRow('ACCOUNTS:', '${_passwords.length}', const Color(0xFF00FBFF)),
                      _buildStatRow('SIZE:', '${sizeKB.toStringAsFixed(2)} KB', const Color(0xFF00FBFF)),
                      _buildStatRow('COMPRESSION:', '${compressionRatio.toStringAsFixed(0)}%', const Color(0xFF00FF00)),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  "SCAN WITH DESTINATION DEVICE",
                  style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: compressedData,
                    version: QrVersions.auto,
                    size: 240.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Scan carefully. QR is dense.',
                          style: TextStyle(color: Colors.orange, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showErrorSnackBar("EXPORT_FAILED: ${e.toString()}");
    }
  }

  Widget _buildStatRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildAlternativeOption({
    required IconData icon,
    required String label,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00FBFF), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showScanner() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _showErrorSnackBar("SCANNER_NOT_SUPPORTED_ON_DESKTOP");
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0A0E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFFFF00FF), width: 1),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: const Text("> SCANNING_DATA_FLUX...",
                  style: TextStyle(color: Color(0xFFFF00FF), fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) async {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    try {
                      final String compressedData = barcodes.first.rawValue!;

                      String decryptedJson;
                      try {
                        final String encryptedStr = CompressionService.decompressFromQR(compressedData);

                        decryptedJson = EncryptionService.decrypt(
                            encryptedStr,
                            widget.masterKey
                        );
                      } catch (e) {
                        decryptedJson = EncryptionService.decrypt(
                            compressedData,
                            widget.masterKey
                        );
                      }

                      final result = SyncService.importFromPackage(decryptedJson);
                      
                      if (!result.success) {
                        _showErrorSnackBar("IMPORT_FAILED: ${result.error}");
                        return;
                      }

                      final db = await DBHelper.database;
                      final batch = db.batch();

                      for (var item in result.passwords) {
                        batch.insert(
                            'accounts',
                            item.toMap(),
                            conflictAlgorithm: ConflictAlgorithm.replace
                        );
                      }

                      for (var code in result.recoveryCodes) {
                        batch.insert(
                            'recovery_codes',
                            code.toMap(),
                            conflictAlgorithm: ConflictAlgorithm.replace
                        );
                      }
                      
                      await batch.commit();

                      if (mounted) {
                        Navigator.pop(context);
                        _loadPasswords();
                        
                        String message = "SYNC_SUCCESS: ${result.passwords.length} ACCOUNTS";
                        if (result.recoveryCodes.isNotEmpty) {
                          message += " + ${result.recoveryCodes.length} RECOVERY_CODES";
                        }
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(message),
                              backgroundColor: const Color(0xFF00FBFF),
                              behavior: SnackBarBehavior.floating,
                            )
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        _showErrorSnackBar("IMPORT_FAILED: ${e.toString()}");
                      }
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToCSV() async {
    try {
      final StringBuffer csv = StringBuffer();
      csv.writeln('Platform,Username,Password,Category,Notes,Created At');
      
      for (var password in _passwords) {
        final decryptedPass = EncryptionService.decrypt(password.password, widget.masterKey);
        final decryptedNotes = password.notes != null 
          ? EncryptionService.decrypt(password.notes!, widget.masterKey)
          : '';
        
        csv.writeln(
          '"${password.platform}",'
          '"${password.username}",'
          '"$decryptedPass",'
          '"${password.category}",'
          '"$decryptedNotes",'
          '"${password.createdAt?.toIso8601String() ?? ''}"'
        );
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'SAVE_VAULT_EXPORT',
          fileName: 'passguard_export_${DateTime.now().millisecondsSinceEpoch}.csv',
          type: FileType.custom,
          allowedExtensions: ['csv'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(csv.toString());
          _showSuccessSnackBar("CSV_EXPORTED_SUCCESSFULLY");
        }
      } else {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/passguard_export_${DateTime.now().millisecondsSinceEpoch}.csv');
        await file.writeAsString(csv.toString());
        await Share.shareXFiles([XFile(file.path)], text: 'PassGuard Export');
      }
    } catch (e) {
      _showErrorSnackBar("EXPORT_FAILED: $e");
    }
  }

  void _showForm({PasswordModel? existingPassword}) {
    final platformC = TextEditingController(text: existingPassword?.platform ?? '');
    final userC = TextEditingController(text: existingPassword?.username ?? '');
    final passC = TextEditingController(
      text: existingPassword != null 
        ? EncryptionService.decrypt(existingPassword.password, widget.masterKey)
        : ''
    );
    final notesC = TextEditingController(
      text: existingPassword?.notes != null
        ? EncryptionService.decrypt(existingPassword!.notes!, widget.masterKey)
        : ''
    );

    String localSelectedCategory = existingPassword?.category ?? 'PERSONAL';

    final List<Map<String, dynamic>> categories = [
      {'name': 'PERSONAL', 'icon': Icons.person, 'color': const Color(0xFF00FBFF)},
      {'name': 'WORK', 'icon': Icons.business_center, 'color': const Color(0xFFFF00FF)},
      {'name': 'FINANCE', 'icon': Icons.account_balance_wallet, 'color': const Color(0xFF00FF00)},
      {'name': 'SOCIAL', 'icon': Icons.public, 'color': const Color(0xFFFFFF00)},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      isScrollControlled: true,
      shape: const Border(top: BorderSide(color: Color(0xFF00FBFF), width: 2)),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20, left: 20, right: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  existingPassword == null ? "> NEW_ENTRY_NODE" : "> EDIT_NODE",
                  style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 18, letterSpacing: 2),
                ),
              ),
              const SizedBox(height: 20),
              
              TextField(
                controller: platformC,
                decoration: const InputDecoration(labelText: "PLATFORM"),
                style: const TextStyle(color: Colors.white),
              ),
              
              TextField(
                controller: userC,
                decoration: const InputDecoration(labelText: "USER_ID"),
                style: const TextStyle(color: Colors.white),
              ),
              
              TextField(
                controller: passC,
                decoration: InputDecoration(
                  labelText: "CREDENTIALS",
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.auto_fix_high, color: Color(0xFFFF00FF)),
                        tooltip: "ADVANCED_GENERATOR",
                        onPressed: () async {
                          final result = await showDialog<String>(
                            context: context,
                            builder: (context) => const PasswordGeneratorDialog(),
                          );
                          if (result != null) {
                            passC.text = result;
                          }
                        },
                      ),
                    ],
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              
              const SizedBox(height: 15),
              
              TextField(
                controller: notesC,
                decoration: const InputDecoration(
                  labelText: "NOTES (Optional, Encrypted)",
                  hintText: "Security questions, backup codes, etc.",
                  hintStyle: TextStyle(fontSize: 10, color: Colors.white24),
                ),
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
              ),
              
              const SizedBox(height: 25),
              const Text("> NODE_CLASSIFICATION:",
                  style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
              const SizedBox(height: 10),
              
              StatefulBuilder(
                builder: (context, setModalState) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((cat) {
                      final bool isSelected = localSelectedCategory == cat['name'];
                      return ChoiceChip(
                        label: Text(cat['name'],
                            style: TextStyle(
                                color: isSelected ? Colors.black : cat['color'],
                                fontSize: 10,
                                fontWeight: FontWeight.bold
                            )),
                        selected: isSelected,
                        selectedColor: cat['color'],
                        backgroundColor: Colors.transparent,
                        side: BorderSide(color: cat['color']),
                        showCheckmark: false,
                        onSelected: (bool selected) {
                          setModalState(() {
                            localSelectedCategory = cat['name'];
                          });
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              
              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FBFF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))
                  ),
                  onPressed: () async {
                    if (platformC.text.isNotEmpty && passC.text.isNotEmpty) {
                      final db = await DBHelper.database;
                      final String masterKeyAsString = String.fromCharCodes(widget.masterKey);

                      final encryptedPass = EncryptionService.encrypt(passC.text, masterKeyAsString);
                      final encryptedNotes = notesC.text.isNotEmpty 
                        ? EncryptionService.encrypt(notesC.text, masterKeyAsString)
                        : null;

                      if (existingPassword == null) {
                        // Create new
                        await db.insert('accounts', PasswordModel(
                          platform: platformC.text,
                          username: userC.text,
                          password: encryptedPass,
                          category: localSelectedCategory,
                          notes: encryptedNotes,
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        ).toMap());
                      } else {
                        // Update existing
                        List<String>? history = existingPassword.passwordHistory ?? [];
                        if (encryptedPass != existingPassword.password) {
                          history.add(existingPassword.password);
                          if (history.length > 5) history.removeAt(0); // Keep last 5
                        }
                        
                        await db.update(
                          'accounts',
                          PasswordModel(
                            id: existingPassword.id,
                            platform: platformC.text,
                            username: userC.text,
                            password: encryptedPass,
                            category: localSelectedCategory,
                            notes: encryptedNotes,
                            createdAt: existingPassword.createdAt,
                            updatedAt: DateTime.now(),
                            otpSeed: existingPassword.otpSeed,
                            isFavorite: existingPassword.isFavorite,
                            passwordHistory: history,
                          ).toMap(),
                          where: 'id = ?',
                          whereArgs: [existingPassword.id],
                        );
                      }

                      if (mounted) {
                        Navigator.pop(context);
                        _loadPasswords();
                        _showSuccessSnackBar(
                          existingPassword == null ? "NODE_CREATED" : "NODE_UPDATED"
                        );
                      }
                    }
                  },
                  child: Text(
                    existingPassword == null ? "UPLOAD_TO_CORE" : "UPDATE_NODE",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _scanQR2FA() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _showErrorSnackBar("ERROR: SCANNER_NOT_SUPPORTED_ON_DESKTOP");
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: const Text(
                '> SCANNING_2FA_QR_CODE',
                style: TextStyle(color: Color(0xFF00FBFF), fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) async {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    final String? code = barcode.rawValue;
                    if (code != null && code.contains("otpauth://")) {
                      final uri = Uri.parse(code);
                      final String? secret = uri.queryParameters['secret'];

                      if (secret != null) {
                        Navigator.pop(context);
                        _showAssignOTPDialog(secret);
                        return;
                      }
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignOTPDialog(String secret) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text("SELECT_ACCOUNT_FOR_2FA", 
                          style: TextStyle(color: Color(0xFF00FBFF), fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _passwords.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(_passwords[i].platform, style: const TextStyle(color: Colors.white)),
              subtitle: Text(_passwords[i].username, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () async {
                String cleanSecret = secret.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
                final db = await DBHelper.database;
                await db.update(
                    'accounts',
                    {'otp_seed': cleanSecret},
                    where: 'id = ?',
                    whereArgs: [_passwords[i].id]
                );

                if (mounted) {
                  Navigator.pop(context);
                  _loadPasswords();
                  _showSuccessSnackBar("2FA_LINKED_TO_${_passwords[i].platform}");
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white10),
            color: Colors.white.withOpacity(0.05),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFFF00FF), size: 18),
              const SizedBox(width: 15),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 1)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFileForVault() async {
    final security = SecurityController();

    try {
      security.pauseLocking();

      FilePickerResult? result = await FilePicker.platform.pickFiles();
      security.resumeLocking();

      if (result == null || result.files.single.path == null) return;

      File selectedFile = File(result.files.single.path!);
      _showSuccessSnackBar("ENCRYPTING_FILE...");
      
      await FileService.importAndEncryptFile(selectedFile, widget.masterKey);

      if (!mounted) return;
      _showSuccessSnackBar("FILE_SUCCESSFULLY_VAULTED");
      setState(() {});

    } catch (e) {
      security.resumeLocking();
      debugPrint("VAULT_ERROR: $e");
      if (mounted) {
        _showErrorSnackBar("VAULT_ERROR: $e");
      }
    }
  }

  void _showSuccessSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF00FBFF),
          behavior: SnackBarBehavior.floating,
        )
    );
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        )
    );
  }

  void _showRecoveryManager(int accountId, String platform) async {
    final db = await DBHelper.database;

    Future<List<Map<String, dynamic>>> loadCodes() async {
      return await db.query('recovery_codes', where: 'account_id = ?', whereArgs: [accountId]);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: Color(0xFFFF00FF), width: 1),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("> EMERGENCY_CODES: $platform",
                    style: const TextStyle(color: Color(0xFFFF00FF), fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                const Divider(color: Colors.white10, height: 20),

                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: loadCodes(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text("NO_CODES_IMPORTED", 
                                     style: TextStyle(color: Colors.white24, fontSize: 10))
                        );
                      }
                      return ListView.builder(
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, i) {
                          final code = snapshot.data![i];
                          bool isUsed = code['is_used'] == 1;
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              code['code'],
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: isUsed ? Colors.white24 : Colors.white,
                                  decoration: isUsed ? TextDecoration.lineThrough : null
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                    activeColor: const Color(0xFFFF00FF),
                                    checkColor: Colors.black,
                                    value: isUsed,
                                    onChanged: (val) async {
                                      await db.update(
                                          'recovery_codes',
                                          {'is_used': val! ? 1 : 0},
                                          where: 'id = ?',
                                          whereArgs: [code['id']]
                                      );
                                      setModalState(() {});
                                    }
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  tooltip: "DELETE_NODE",
                                  onPressed: () async {
                                    await db.delete(
                                        'recovery_codes',
                                        where: 'id = ?',
                                        whereArgs: [code['id']]
                                    );
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16161D),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.file_upload, color: Color(0xFF00FBFF)),
                    label: const Text("IMPORT_TXT_FROM_STORAGE", 
                                     style: TextStyle(color: Colors.white, fontSize: 11)),
                    onPressed: () async {
                      final security = SecurityController();
                      security.pauseLocking();

                      try {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['txt'],
                        );

                        security.resumeLocking();

                        if (result != null && result.files.single.path != null) {
                          final file = File(result.files.single.path!);
                          final List<String> lines = await file.readAsLines();
                          List<String> codes = [];

                          for (String line in lines) {
                            String cleanLine = line.trim();
                            if (cleanLine.isEmpty ||
                                cleanLine.contains("==") ||
                                cleanLine.toLowerCase().contains("backup codes") ||
                                cleanLine.toLowerCase().contains("generated:") ||
                                cleanLine.toLowerCase().contains("keep these") ||
                                cleanLine.toLowerCase().contains("used once")) {
                              continue;
                            }
                            if (cleanLine.length >= 6 && !cleanLine.contains(" ")) {
                              codes.add(cleanLine);
                            }
                          }

                          if (codes.isNotEmpty) {
                            bool? confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF0A0A0E),
                                title: const Text("> NODES_DETECTED", 
                                               style: TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace')),
                                content: SingleChildScrollView(
                                  child: Text(codes.join("\n"), 
                                             style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false), 
                                    child: const Text("CANCEL")
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true), 
                                    child: const Text("CONFIRM_IMPORT")
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              final db = await DBHelper.database;
                              for (var codeStr in codes) {
                                await db.insert('recovery_codes', {
                                  'account_id': accountId,
                                  'code': codeStr,
                                  'is_used': 0,
                                  'created_at': DateTime.now().toIso8601String(),
                                });
                              }
                              if (await file.exists()) await file.delete();
                              setModalState(() {});
                              _showSuccessSnackBar("> ${codes.length} CODES_SECURED");
                            }
                          }
                        }
                      } catch (e) {
                        security.resumeLocking();
                        _showErrorSnackBar("> SYSTEM_ERROR: $e");
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPasswordHistory(PasswordModel password) async {
    if (password.passwordHistory == null || password.passwordHistory!.isEmpty) {
      _showErrorSnackBar("NO_PASSWORD_HISTORY_AVAILABLE");
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        title: Text('> PASSWORD_HISTORY: ${password.platform}',
                    style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: password.passwordHistory!.length,
            itemBuilder: (context, index) {
              final encryptedOldPass = password.passwordHistory![index];
              final decryptedOldPass = EncryptionService.decrypt(encryptedOldPass, widget.masterKey);
              
              return ListTile(
                dense: true,
                leading: const Icon(Icons.history, color: Colors.white54, size: 16),
                title: Text(
                  '••••••••',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.visibility, color: Color(0xFF00FBFF), size: 16),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF0A0A0E),
                        title: const Text('OLD_PASSWORD', style: TextStyle(color: Color(0xFF00FBFF))),
                        content: SelectableText(
                          decryptedOldPass,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: decryptedOldPass));
                              Navigator.pop(context);
                              _showSuccessSnackBar("COPIED_TO_CLIPBOARD");
                            },
                            child: const Text('COPY'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onUserInteraction,
      onPanUpdate: (_) => _onUserInteraction(),
      child: Scaffold(
        backgroundColor: const Color(0xFF050505),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: _isSearching
              ? TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: "SCANNING_NODES...",
              hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
              border: InputBorder.none,
            ),
            onChanged: (v) => _loadPasswords(query: v),
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("VAULT_INTERFACE",
                  style: TextStyle(color: Color(0xFF00FBFF), fontSize: 13, letterSpacing: 1, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: LinearProgressIndicator(
                        value: _currentHealthScore / 100,
                        backgroundColor: Colors.white10,
                        color: _getHealthColor(_currentHealthScore),
                        minHeight: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getHealthStatusText(_currentHealthScore),
                    style: TextStyle(
                        color: _getHealthColor(_currentHealthScore),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "${_currentHealthScore.toInt()}%",
                    style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search, color: const Color(0xFF00FBFF)),
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchController.clear();
                      _loadPasswords();
                    }
                  });
                }),
            IconButton(
              icon: const Icon(Icons.filter_list, color: Color(0xFFFF00FF)),
              onPressed: _showFilterMenu,
            ),
            IconButton(
              icon: const Icon(Icons.sort, color: Color(0xFFFF00FF)),
              onPressed: _showSortMenu,
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Color(0xFFFF00FF)),
              onPressed: _showSystemMenu,
            ),
          ],
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildPasswordList(),
            FileVaultScreen(masterKey: widget.masterKey),
          ],
        ),

        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: const Color(0xFF00FBFF).withOpacity(0.2), width: 1)),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() => _selectedIndex = index);
              _onUserInteraction();
            },
            backgroundColor: const Color(0xFF0A0A0E),
            selectedItemColor: const Color(0xFF00FBFF),
            unselectedItemColor: Colors.white24,
            selectedLabelStyle: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.key), label: "KEYS"),
              BottomNavigationBarItem(icon: Icon(Icons.folder_special), label: "FILES"),
            ],
          ),
        ),

        floatingActionButton: _selectedIndex == 0
            ? _buildFabPasswords()
            : FloatingActionButton(
          backgroundColor: const Color(0xFFFF00FF),
          child: const Icon(Icons.upload_file, color: Colors.white),
          onPressed: () {
            _onUserInteraction();
            _pickFileForVault();
          },
        ),
      ),
    );
  }

  Widget _buildPasswordList() {
    if (_passwords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_open, size: 80, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 20),
            const Text("> NO_DATA_DETECTED", 
                       style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 1)),
            const SizedBox(height: 10),
            const Text("TAP + TO ADD YOUR FIRST PASSWORD", 
                       style: TextStyle(color: Colors.white24, fontSize: 10)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _passwords.length,
      itemBuilder: (context, index) {
        final item = _passwords[index];
        int secondsPassed = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;
        double progress = (30 - secondsPassed) / 30;
        Color progressColor = progress > 0.3 ? const Color(0xFF00FBFF) : Colors.red;

        Color categoryColor = const Color(0xFF00FBFF);
        switch (item.category) {
          case 'WORK':
            categoryColor = const Color(0xFFFF00FF);
            break;
          case 'FINANCE':
            categoryColor = const Color(0xFF00FF00);
            break;
          case 'SOCIAL':
            categoryColor = const Color(0xFFFFFF00);
            break;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF16161D),
            border: Border(left: BorderSide(color: categoryColor, width: 4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.isFavorite)
                  const Icon(Icons.star, color: Color(0xFFFFFF00), size: 16),
                Icon(
                  _getCategoryIcon(item.category),
                  color: categoryColor,
                  size: 24,
                ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    item.platform.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (item.passwordHistory != null && item.passwordHistory!.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white54, size: 16),
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showPasswordHistory(item),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.username, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                if (item.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Created: ${_formatDate(item.createdAt!)}',
                    style: const TextStyle(color: Colors.white24, fontSize: 9),
                  ),
                ],
                if (item.otpSeed != null && item.otpSeed!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FBFF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF00FBFF).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.security, size: 12, color: Color(0xFF00FBFF)),
                        const SizedBox(width: 6),
                        Text(
                              () {
                            try {
                              if (item.otpSeed == null || item.otpSeed!.isEmpty) return "000 000";
                              return OTP.generateTOTPCodeString(
                                  item.otpSeed!,
                                  DateTime.now().millisecondsSinceEpoch,
                                  interval: 30,
                                  length: 6,
                                  algorithm: Algorithm.SHA1,
                                  isGoogle: true
                              ).replaceAllMapped(RegExp(r".{3}"), (match) => "${match.group(0)} ");
                            } catch (e) {
                              return "OTP_ERR";
                            }
                          }(),
                          style: const TextStyle(
                              color: Color(0xFF00FBFF),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 2),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 40,
                          height: 2,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
              ],
            ),
            trailing: SizedBox(
              width: 200,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: Icon(
                        item.isFavorite ? Icons.star : Icons.star_border,
                        color: item.isFavorite ? const Color(0xFFFFFF00) : Colors.white54,
                        size: 18,
                      ),
                      tooltip: "FAVORITE",
                      onPressed: () => _toggleFavorite(item)),
                  IconButton(
                      icon: const Icon(Icons.emergency, color: Color(0xFFFF00FF), size: 18),
                      tooltip: "RECOVERY_CODES",
                      onPressed: () => _showRecoveryManager(item.id!, item.platform)),
                  IconButton(
                      icon: const Icon(Icons.remove_red_eye, color: Color(0xFF00FBFF), size: 18),
                      tooltip: "VIEW_PASSWORD",
                      onPressed: () async {
                        String dec = EncryptionService.decrypt(item.password, widget.masterKey);
                        await DBHelper.updateLastUsed(item.id!);
                        _onUserInteraction();
                        
                        showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFF0A0A0E),
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              title: Text("> ${item.platform}", 
                                         style: const TextStyle(color: Colors.white, fontSize: 16)),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('USERNAME:', 
                                           style: TextStyle(color: Colors.white54, fontSize: 10)),
                                  SelectableText(item.username,
                                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                  const SizedBox(height: 15),
                                  const Text('PASSWORD:', 
                                           style: TextStyle(color: Colors.white54, fontSize: 10)),
                                  SelectableText(dec,
                                      style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 18, fontFamily: 'monospace')),
                                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                                    const SizedBox(height: 15),
                                    const Text('NOTES:', 
                                             style: TextStyle(color: Colors.white54, fontSize: 10)),
                                    SelectableText(
                                      EncryptionService.decrypt(item.notes!, widget.masterKey),
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('CLOSE'),
                                ),
                              ],
                            ));
                      }),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Color(0xFFFF00FF), size: 18),
                    tooltip: "COPY_PASSWORD",
                    onPressed: () async {
                      String dec = EncryptionService.decrypt(item.password, widget.masterKey);
                      await Clipboard.setData(ClipboardData(text: dec));
                      await DBHelper.updateLastUsed(item.id!);
                      _onUserInteraction();
                      
                      _clipboardTimer?.cancel();
                      _showSuccessSnackBar("DATA_COPIED: 30s AUTO_CLEAR");
                      
                      _clipboardTimer = Timer(const Duration(seconds: 30), () async {
                        await Clipboard.setData(const ClipboardData(text: ""));
                      });
                    },
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
                    color: const Color(0xFF16161D),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        _showForm(existingPassword: item);
                      } else if (value == 'delete') {
                        bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF0A0A0E),
                            title: const Text('> CONFIRM_DELETE', 
                                             style: TextStyle(color: Colors.red)),
                            content: Text('Delete ${item.platform}?',
                                         style: const TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('CANCEL'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('DELETE'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          final db = await DBHelper.database;
                          await db.delete('accounts', where: 'id = ?', whereArgs: [item.id]);
                          _loadPasswords();
                          _showSuccessSnackBar("NODE_DELETED");
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Color(0xFF00FBFF), size: 16),
                            SizedBox(width: 8),
                            Text('EDIT', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, color: Colors.red, size: 16),
                            SizedBox(width: 8),
                            Text('DELETE', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'WORK':
        return Icons.business_center;
      case 'FINANCE':
        return Icons.account_balance_wallet;
      case 'SOCIAL':
        return Icons.public;
      default:
        return Icons.person;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
    return '${(diff.inDays / 365).floor()} years ago';
  }

  Widget _buildFabPasswords() {
    return FloatingActionButton(
      backgroundColor: const Color(0xFF00FBFF),
      child: const Icon(Icons.add, color: Colors.black),
      onPressed: () {
        _onUserInteraction();
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF0A0A0E),
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            side: BorderSide(color: Color(0xFF00FBFF), width: 1),
          ),
          builder: (context) => SafeArea(
            child: Container(
              padding: EdgeInsets.only(top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 10),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.password, color: Color(0xFF00FBFF)),
                      title: const Text("ADD_NEW_PASSWORD", 
                                       style: TextStyle(color: Colors.white, letterSpacing: 1)),
                      onTap: () { Navigator.pop(context); _showForm(); },
                    ),
                    const Divider(color: Colors.white10),
                    ListTile(
                      leading: const Icon(Icons.qr_code_scanner, color: Color(0xFFFF00FF)),
                      title: const Text("SCAN_QR_2FA", 
                                       style: TextStyle(color: Colors.white, letterSpacing: 1)),
                      onTap: () { Navigator.pop(context); _scanQR2FA(); },
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SecurityController {
  static final SecurityController _instance = SecurityController._internal();
  factory SecurityController() => _instance;
  SecurityController._internal();

  bool shouldLockOnLeave = true;

  void pauseLocking() => shouldLockOnLeave = false;
  void resumeLocking() => shouldLockOnLeave = true;
}

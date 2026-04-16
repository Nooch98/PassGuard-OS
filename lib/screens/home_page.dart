/*
|--------------------------------------------------------------------------
| PassGuard OS - HomePage
|--------------------------------------------------------------------------
| Description:
|   Main application interface displaying stored accounts.
|
| Responsibilities:
|   - Render password list
|   - Display TOTP codes
|   - Trigger security audit
|   - Handle user interactions
|
| Performance Notes:
|   - Sensitive data is decrypted lazily
|   - TOTP secrets are cached in memory only
|--------------------------------------------------------------------------
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:passguard/screens/dashboard.dart';
import 'package:passguard/screens/identities_vault_screen.dart';
import 'package:passguard/services/WarpController.dart';
import 'package:passguard/services/security_controller.dart';
import 'package:passguard/widgets/cybertype_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:otp/otp.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:image/image.dart' as img;

import '../services/auth_service.dart';
import '../services/compression_service.dart';
import '../services/db_helper.dart';
import '../services/encryption_service.dart';
import '../services/file_service.dart';
import '../services/filevaultscreen.dart';
import '../services/password_fingerprint.dart';
import '../services/sync_service.dart';
import '../services/session_manager.dart';
import '../services/security_analyzer.dart';
import '../models/password_model.dart';
import '../services/SteganographyService.dart';
import '../services/topt_meta.dart';
import '../widgets/password_generator_dialog.dart';

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
  Timer? _totpTimer;
  int _totpNowMs = DateTime.now().millisecondsSinceEpoch;
  double _currentHealthScore = 0;
  int _selectedIndex = 0;

  String _sortBy = 'platform';
  bool _sortAscending = true;

  String? _filterCategory;
  bool _showFavoritesOnly = false;
  String _warpStatus = "IDLE";
  late PageController _pageController;

  final Map<int, String?> _totpSecretCache = {};
  final GlobalKey<IdentitiesVaultScreenState> _identitiesKey = GlobalKey<IdentitiesVaultScreenState>();
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey<DashboardScreenState>();
  final WarpController _warpController = WarpController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    WidgetsBinding.instance.addObserver(this);
    _loadPasswords();

    _migrateRecoveryCodesToEncrypted();

    SessionManager().activity();
    
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _totpNowMs = DateTime.now().millisecondsSinceEpoch);
    });

    _applyScreenshotProtection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _totpSecretCache.clear();
    _totpTimer?.cancel();
    _searchController.dispose();
    _clipboardTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SessionManager().activity();
    }
  }

  Future<void> _migrateRecoveryCodesToEncrypted() async {
    try {
      final db = await DBHelper.database;
      final masterKeyString = widget.masterKey;

      final List<Map<String, dynamic>> codes = await db.query('recovery_codes');
      
      if (codes.isEmpty) {
        return;
      }
      
      int migratedCount = 0;
      int alreadyEncrypted = 0;
      int errors = 0;
      
      for (var code in codes) {
        final rawCode = code['code'];
        
        if (rawCode == null || rawCode is! String) {
          errors++;
          continue;
        }

        bool looksEncrypted = rawCode.contains('U2FsdGVk') || 
                              rawCode.length > 50 ||
                              !RegExp(r'^[A-Za-z0-9\-]+$').hasMatch(rawCode);
        
        if (looksEncrypted) {
          alreadyEncrypted++;
          continue;
        }

        try {
          final encrypted = EncryptionService.encrypt(rawCode, masterKeyString);
          
          await db.update(
            'recovery_codes',
            {'code': encrypted},
            where: 'id = ?',
            whereArgs: [code['id']],
          );
          
          migratedCount++;
        } catch (encryptError) {
          errors++;
        }
      }
      
      if (migratedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔒 SECURITY_UPGRADE: $migratedCount recovery codes encrypted'),
            backgroundColor: const Color(0xFF00FF00),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MIGRATION_ERROR: $e'),
          backgroundColor: const Color(0xFFFF0000),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _applyScreenshotProtection() async {
    if (Platform.isAndroid || Platform.isIOS) {
      bool enabled = await AuthService.getScreenshotProtection();
      
      try {
        if (enabled) {
          await ScreenProtector.preventScreenshotOn();
        } else {
          await ScreenProtector.preventScreenshotOff();
        }
      } catch (e) {
        //
      }
    }
  }

  void _onUserInteraction() {
    SessionManager().activity();
  }

  Future<void> _loadPasswords({String? query}) async {
    final db = await DBHelper.database;
    bool travelModeActive = await AuthService.getTravelModeEnabled();

    String? whereClause;
    List<dynamic> whereArgs = [];

    if (travelModeActive) {
      whereClause = 'is_travel_safe = 1';
    }

    if (query != null && query.isNotEmpty) {
      String searchClause = '(platform LIKE ? OR username LIKE ?)';
      whereClause = whereClause == null ? searchClause : '$whereClause AND $searchClause';
      whereArgs.addAll(['%$query%', '%$query%']);
    }

    if (_filterCategory != null) {
      String catClause = 'category = ?';
      whereClause = whereClause == null ? catClause : '$whereClause AND $catClause';
      whereArgs.add(_filterCategory);
    }

    if (travelModeActive) {
      whereClause = 'is_travel_safe = 0';
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
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
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

  Widget _buildCapacityIndicator(StegoCheckResult result) {
    Color color = Colors.green;
    String advice = "SAFE: Low visual impact.";
    
    if (result.usagePercentage > 50) {
      color = Colors.orange;
      advice = "WARNING: Medium visual noise.";
    }
    if (result.usagePercentage > 85) {
      color = Colors.red;
      advice = "CRITICAL: High risk of detection/artifacts.";
    }

    return Column(
      children: [
        LinearProgressIndicator(
          value: result.usagePercentage / 100,
          backgroundColor: Colors.white10,
          color: color,
        ),
        const SizedBox(height: 8),
        Text("${result.usagePercentage.toStringAsFixed(1)}% Capacity Used", 
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        Text(advice, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
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

  Future<void> _handleImageInjection() async {
    final security = SecurityController();
    final stegoService = SteganographyService(repeatFactor: 1);

    try {
      security.pauseLocking();
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
      security.resumeLocking();
      
      if (pickedFile == null) return;

      String encryptedData = await _prepareEncryptedDataStream();
      Uint8List imageBytes = await pickedFile.readAsBytes();
      final imageInfo = img.decodeImage(imageBytes);
      
      if (imageInfo == null) throw "INVALID_IMAGE_FORMAT";

      final check = stegoService.checkCapacity(imageInfo.width, imageInfo.height, encryptedData);

      if (!mounted) return;

      bool confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0E),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: check.fits ? const Color(0xFF00FBFF) : const Color(0xFFFF3131), 
              width: 1
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Icon(
                check.fits ? Icons.biotech : Icons.report_problem, 
                color: check.fits ? const Color(0xFF00FBFF) : const Color(0xFFFF3131),
                size: 20,
              ),
              const SizedBox(width: 10),
              const Text(
                "INJECTION_ANALYSIS", 
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: 14, 
                  fontFamily: 'monospace', 
                  fontWeight: FontWeight.bold
                )
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    _buildTerminalRow("CARRIER_DIM:", "${imageInfo.width}x${imageInfo.height}px"),
                    _buildTerminalRow("STATUS:", check.fits ? "CAPACITY_OPTIMAL" : "BUFFER_OVERFLOW", 
                      color: check.fits ? const Color(0xFF00FF41) : const Color(0xFFFF3131)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "STORAGE_CAPACITY_MAP", 
                style: TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace')
              ),
              const SizedBox(height: 8),
              _buildCapacityIndicator(check),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false), 
              child: const Text(
                "ABORT", 
                style: TextStyle(color: Colors.white30, fontFamily: 'monospace', fontSize: 12)
              )
            ),
            if (check.fits)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FBFF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context, true);
                },
                icon: const Icon(Icons.layers, size: 18),
                label: const Text(
                  "START_INJECTION", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')
                ),
              ),
          ],
        ),
      ) ?? false;

      if (!confirm) return;

      Uint8List ghostImage = await stegoService.hideVaultInImage(imageBytes, encryptedData);
      await _saveImageToGallery(ghostImage);

      _showSuccessSnackBar("GHOST_IMAGE_CREATED: INJECTION_SUCCESSFUL");

    } catch (e) {
      security.resumeLocking();
      _showErrorSnackBar("INJECTION_FAILED: ${e.toString()}");
    }
  }

  Widget _buildTerminalRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
          Text(value, style: TextStyle(color: color ?? Colors.white70, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ],
      ),
    );
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
      widget.masterKey
    );
  }

  Future<void> _processImportedData(String encryptedData) async {
    try {
      final String decryptedJson = EncryptionService.decrypt(
        combinedText: encryptedData,
        masterKeyBytes: widget.masterKey
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

  Future<void> _saveAsFile(String encryptedContent) async {
    try {
      HapticFeedback.selectionClick();
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String fileName = "PG_BACKUP_$timestamp.pgvault";

      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'SELECT_EXPORT_DIRECTORY',
      );

      if (selectedDirectory == null) {
        _showErrorSnackBar("EXPORT_ABORTED: NO_DIRECTORY_SELECTED");
        return;
      }

      final String fullPath = "$selectedDirectory${Platform.pathSeparator}$fileName";
      final File file = File(fullPath);
      await file.writeAsString(encryptedContent);
      _showSuccessSnackBar("FILE_COMMITTED: ${fileName.toUpperCase()}");

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF0A0A0E),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Text("> EXPORT_LOG", style: TextStyle(color: Color(0xFF00FBFF), fontSize: 14, fontFamily: 'monospace')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow("FILENAME:", fileName, Colors.white70),
                _buildStatRow("PATH:", selectedDirectory, const Color(0xFF00FBFF).withOpacity(0.5)),
                _buildStatRow("STATUS:", "VERIFIED_ON_DISK", const Color(0xFF00FF41)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("ACKNOWLEDGE", style: TextStyle(color: Color(0xFF00FBFF), fontSize: 10)),
              )
            ],
          ),
        );
      }

    } catch (e) {
      _showErrorSnackBar("IO_ACCESS_DENIED: ${e.toString()}");
    }
  }

  Future<void> _initiateImportFlow() async {
    final security = SecurityController();

    try {
      security.pauseLocking();

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
        dialogTitle: "SELECT_ENCRYPTED_BUNDLE",
      );

      security.resumeLocking();

      if (result != null && result.files.isNotEmpty) {
        String encryptedData = "";
        PlatformFile file = result.files.first;

        if (file.bytes != null) {
          encryptedData = utf8.decode(file.bytes!);
        } else if (file.path != null) {
          encryptedData = await File(file.path!).readAsString();
        }

        if (encryptedData.isEmpty) throw "EMPTY_OR_UNREADABLE_FILE";

        if (!mounted) return;

        HapticFeedback.mediumImpact();
        _showSuccessSnackBar("DECRYPT_STREAM_OPENED: ${file.name}");
        
        _showPasswordEntryDialog(isExport: false, dataToImport: encryptedData);
      }
    } catch (e) {
      security.resumeLocking();
      if (mounted) {
        _showErrorSnackBar("IMPORT_CRITICAL_FAILURE: SYSTEM_I/O_DENIED");
        debugPrint("Error detalle: $e");
      }
    }
  }

  Future<void> _handleImportResult(SyncImportResult result) async {
    if (!result.success) return;

    final localKey = widget.masterKey;
    int importedCount = 0;

    for (var p in result.passwords) {
      String finalPassword;
      String? finalOtp;
      
      if (p.password.startsWith("v5.")) {
        finalPassword = p.password;
        finalOtp = p.otpSeed;
      } else {
        finalPassword = EncryptionService.encrypt(p.password, localKey);
        finalOtp = (p.otpSeed != null && p.otpSeed!.isNotEmpty)
            ? EncryptionService.encrypt(p.otpSeed!, localKey)
            : p.otpSeed;
      }

      final readyToSave = p.copyWith(
        password: finalPassword,
        otpSeed: finalOtp,
      );

      bool exists = await DBHelper.checkIfPasswordExists(readyToSave.platform, readyToSave.username);
      if (!exists) {
        await DBHelper.insertPassword(readyToSave);
        importedCount++;
      }
    }
    
    _loadPasswords();
    _showSuccessSnackBar("IMPORT_SYNC_COMPLETE: $importedCount new entries");
  }

  void _showSecureBundleManager() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF1A1A1E), width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            const Icon(Icons.settings_input_antenna, color: Color(0xFF00FBFF), size: 18),
            const SizedBox(width: 12),
            const Text(
              "BUNDLE_TRANSCEIVER_v5",
              style: TextStyle(
                color: Color(0xFF00FBFF),
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Protocol: Argon2id + AES-GCM 256-bit",
              style: TextStyle(color: Colors.white30, fontSize: 9, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context);
                _showPasswordEntryDialog(isExport: true);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FBFF).withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00FBFF).withOpacity(0.15), width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FBFF).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.upload_file, color: Color(0xFF00FBFF), size: 20),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("EXPORT_BUNDLE",
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          SizedBox(height: 2),
                          Text("SECURE_OUTBOUND_ENCRYPTION",
                            style: TextStyle(color: Color(0x8000FBFF), fontSize: 9, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0x4D00FBFF), size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context);
                _initiateImportFlow();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF00FF).withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF00FF).withOpacity(0.15), width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF00FF).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.download_for_offline, color: Color(0xFFFF00FF), size: 20),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("IMPORT_BUNDLE",
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          SizedBox(height: 2),
                          Text("RESTORE_VAULT_DECODING",
                            style: TextStyle(color: Color(0x80FF00FF), fontSize: 9, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0x4DFF00FF), size: 16),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 10),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "TERMINATE_SESSION",
                style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPasswordEntryDialog({required bool isExport, String? dataToImport}) {
    final Color accentColor = isExport ? const Color(0xFF00FBFF) : const Color(0xFFFF00FF);
    final String title = isExport ? "> INITIATE_EXPORT_SEQUENCE" : "> INITIATE_IMPORT_SEQUENCE";
    final IconData actionIcon = isExport ? Icons.ios_share : Icons.system_update_alt;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accentColor.withOpacity(0.5), width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(actionIcon, color: accentColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor, Colors.transparent],
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: accentColor.withOpacity(0.7), size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isExport
                          ? "The export will preserve all encryption integrity, including sensitive TOTP seeds and metadata."
                          : "The import will merge the external bundle into your current vault. Ensure the source is trusted.",
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Text(
              isExport ? "READY_FOR_ENCRYPTION_STREAM" : "READY_FOR_DECRYPTION_STREAM",
              style: TextStyle(
                color: accentColor.withOpacity(0.4),
                fontSize: 9,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "ABORT",
              style: TextStyle(color: Colors.white24, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              elevation: 0,
            ),
            onPressed: () async {
              HapticFeedback.heavyImpact();
              Navigator.pop(context);

              if (isExport) {
                String bundle = await SyncService.exportSecurePackage(_passwords, widget.masterKey);
                await _saveAsFile(bundle);
              } else {
                final result = await SyncService.importSecurePackage(dataToImport!, widget.masterKey);
                if (result.success) {
                  _handleImportResult(result);
                } else {
                  _showErrorSnackBar("IMPORT_FAILED: KEY_MISMATCH_OR_CORRUPT");
                }
              }
            },
            icon: Icon(isExport ? Icons.lock_outline : Icons.lock_open, size: 16),
            label: Text(
              isExport ? "CONFIRM_EXPORT" : "CONFIRM_IMPORT",
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showSystemMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF00FBFF), width: 1.5),
      ),
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text("> ", style: TextStyle(color: Color(0xFF00FBFF), fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("SYSTEM_CORE_SETTINGS",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildSystemGroup(
                        label: "ACCESS_CONTROL",
                        items: [
                          ListTile(
                            leading: const Icon(Icons.security_update_good, color: Color(0xFF00FBFF)),
                            title: const Text("MAINTAIN_BUNKER_INTEGRITY", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Sync to latest crypto standard", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            onTap: () { Navigator.pop(context); _showUniversalUpgradeConfirmation(); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.fingerprint, color: Color(0xFF00FBFF)),
                            title: const Text("LINK_BIOMETRIC_VAULT", style: TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () async {
                              Navigator.pop(context);
                              await AuthService.saveMasterKeyForBio(utf8.decode(widget.masterKey));
                              _showSuccessSnackBar("BIO_LINK_SUCCESS");
                            },
                          ),
                          /*ListTile(
                            leading: const Icon(Icons.dialpad, color: Color(0xFF00FBFF)),
                            title: const Text("CHANGE_STEALTH_CODE", style: TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () { Navigator.pop(context); _showStealthCodeDialog(); },
                          ),*/
                        ],
                      ),

                      _buildSystemGroup(
                        label: "AUTO_PROTECTION_PROTOCOLS",
                        items: [
                          ListTile(
                            leading: const Icon(Icons.timer, color: Color(0xFFFF00FF)),
                            title: const Text("SESSION_TIMEOUT", style: TextStyle(color: Colors.white, fontSize: 13)),
                            trailing: FutureBuilder<int>(
                              future: AuthService.getSessionTimeout(),
                              builder: (context, snapshot) => Text('${snapshot.data ?? 5}m', style: const TextStyle(color: Color(0xFFFF00FF))),
                            ),
                            onTap: () { Navigator.pop(context); _showSessionTimeoutDialog(); },
                          ),
                          FutureBuilder<bool>(
                            future: AuthService.getAutoLockEnabled(),
                            builder: (context, snapshot) => SwitchListTile(
                              secondary: const Icon(Icons.lock_clock, color: Color(0xFFFF00FF)),
                              title: const Text("AUTO_LOCK_ON_MINIMIZE", style: TextStyle(color: Colors.white, fontSize: 13)),
                              value: snapshot.data ?? true,
                              activeColor: const Color(0xFF00FBFF),
                              onChanged: (val) async {
                                await AuthService.setAutoLockEnabled(val);
                                setState(() {});
                              },
                            ),
                          ),
                          if (Platform.isAndroid)
                            FutureBuilder<bool>(
                              future: AuthService.getScreenshotProtection(),
                              builder: (context, snapshot) => SwitchListTile(
                                secondary: const Icon(Icons.screenshot, color: Color(0xFFFF00FF)),
                                title: const Text("SCREENSHOT_PROTECTION", style: TextStyle(color: Colors.white, fontSize: 13)),
                                value: snapshot.data ?? true,
                                activeColor: const Color(0xFF00FBFF),
                                onChanged: (val) async {
                                  await AuthService.setScreenshotProtection(val);
                                  setState(() {});
                                  _showSuccessSnackBar("RESTART_REQUIRED");
                                },
                              ),
                            ),
                        ],
                      ),

                      _buildSystemGroup(
                        label: "DATA_TRANSMISSION",
                        items: [
                          ListTile(
                            leading: const Icon(Icons.bolt, color: Color(0xFF00FBFF)),
                            title: const Text("INITIALIZE_WARP_SYNC_HOST", 
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            subtitle: const Text("Broadcast vault to local network nodes", 
                              style: TextStyle(fontSize: 10, color: Colors.grey)),
                            onTap: () { 
                              Navigator.pop(context); 
                              _showWarpSyncInterface(isHost: true); 
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.hub_outlined, color: Color(0xFF00FBFF)),
                            title: const Text("JOIN_WARP_DATA_STREAM", 
                              style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Receive and re-encrypt from active host", 
                              style: TextStyle(fontSize: 10, color: Colors.grey)),
                            onTap: () { 
                              Navigator.pop(context); 
                              _showWarpSyncInterface(isHost: false); 
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(color: Colors.white10, height: 1),
                          ),
                          ListTile(
                            leading: const Icon(Icons.qr_code_2, color: Color(0xFF00FBFF)),
                            title: const Text("GENERATE_TRANSMISSION_QR", style: TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () { Navigator.pop(context); _showQRGenerator(); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.qr_code_scanner, color: Color(0xFF00FBFF)),
                            title: const Text("RECEIVE_DATA_STREAM", style: TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () { Navigator.pop(context); _showScanner(); },
                          ),
                          FutureBuilder<bool>(
                            future: AuthService.getTravelModeEnabled(),
                            builder: (context, snapshot) {
                              bool isActive = snapshot.data ?? false;
                              return SwitchListTile(
                                secondary: Icon(Icons.flight_takeoff, color: isActive ? Colors.yellow : const Color(0xFFFF00FF)),
                                title: const Text("TRAVEL_MODE_PROTOCOL", style: TextStyle(color: Colors.white, fontSize: 13)),
                                value: isActive,
                                activeColor: const Color(0xFF00FBFF),
                                onChanged: (val) async {
                                  if (!val) {
                                    bool canProceed = await _showTravelDeactivationCheck();
                                    if (!canProceed) return;
                                  }
                                  await AuthService.setTravelModeEnabled(val);
                                  Navigator.pop(context);
                                  setState(() { _loadPasswords(); });
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      _buildSystemGroup(
                        label: "ARCHIVE_PROTOCOLS",
                        items: [
                          ListTile(
                            leading: const Icon(Icons.ac_unit, color: Color(0xFF00FBFF)),
                            title: const Text("COLD_STORAGE_PROTOCOLS", style: TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: const Text("Steganographic injection", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            onTap: () { Navigator.pop(context); _showColdStorageDialog(); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.inventory_2, color: Color(0xFF00FBFF)),
                            title: const Text("ENCRYPTED_JSON_BUNDLE", style: TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () { Navigator.pop(context); _showSecureBundleManager(); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.file_download, color: Color(0xFF00FBFF)),
                            title: const Text("EXPORT_VAULT_CSV", style: TextStyle(color: Colors.white, fontSize: 13)),
                            onTap: () { Navigator.pop(context); _exportToCSV(); },
                          ),
                        ],
                      ),

                      _buildSystemGroup(
                        label: "EXTERNAL_SECURITY_NODES",
                        items: [
                          ListTile(
                            leading: const Icon(Icons.sd_storage, color: Color(0xFF00FBFF)),
                            title: const Text("EXPLORE_NULLFILES_HYBRID_VAULT", 
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            subtitle: const Text("Portable privacy for external media", 
                              style: TextStyle(fontSize: 10, color: Colors.grey)),
                            trailing: const Icon(Icons.open_in_new, size: 14, color: Colors.white24),
                            onTap: () { 
                              Navigator.pop(context); 
                              _showNullFilesInfoDialog(context); 
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNullFilesInfoDialog(BuildContext context) {
    const String repoUrl = "https://github.com/Nooch98/NullFiles";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
        ),
        title: Row(
          children: [
            const Icon(Icons.sd_storage_outlined, color: Color(0xFF00FBFF)),
            const SizedBox(width: 10),
            const Text("NULLFILES_HYBRID_VAULT", 
              style: TextStyle(color: Colors.white, letterSpacing: 1.5, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Portable privacy tool for external storage using a hybrid security model.",
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                
                _buildTechSection("CORE_FUNCTIONS", [
                  "FAST_MODE: Instant relocation to stealth vault.",
                  "DEEP_MODE: Recursive AES-256-GCM encryption.",
                  "METADATA_LOCK: Argon2id + Encrypted SQLite mapping.",
                ]),
                
                const SizedBox(height: 12),
                
                _buildTechSection("DESIGN_PHILOSOPHY", [
                  "Zero write amplification on flash media.",
                  "Optimized for large portable archives.",
                  "No installation / Full portability.",
                ]),

                const SizedBox(height: 16),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),
                
                const Text(
                  "NOTICE: To maintain bunker-level trust, NullFiles is only provided as source code. Manual auditing and self-compiling is required.",
                  style: TextStyle(color: Color(0xFFFF00FF), fontSize: 11, fontStyle: FontStyle.italic),
                ),

                const SizedBox(height: 12),
                
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          repoUrl,
                          style: TextStyle(color: Color(0xFF00FBFF), fontSize: 10, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("EXIT", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FBFF).withOpacity(0.1),
              side: const BorderSide(color: Color(0xFF00FBFF)),
            ),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: repoUrl));
              // Aquí puedes llamar a tu snackbar de éxito:
              _showSuccessSnackBar("URL_COPIED_TO_CLIPBOARD");
            },
            icon: const Icon(Icons.copy, size: 18, color: Color(0xFF00FBFF)),
            label: const Text("COPY_REPO_URL", style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTechSection(String title, List<String> points) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...points.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text("• $p", style: const TextStyle(color: Colors.white70, fontSize: 11)),
        )),
      ],
    );
  }

  void _showWarpSyncInterface({required bool isHost}) {
    final security = SecurityController();
    String localIp = "0.0.0.0";
    TextEditingController ipManualController = TextEditingController(text: "192.168.");
    security.pauseLocking();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "WARP_SYNC",
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (_warpStatus == "IDLE" && isHost) {
              setModalState(() => _warpStatus = "FETCHING_LOCAL_IP...");
              _getLocalIp().then((ip) {
                setModalState(() {
                  localIp = ip;
                  _warpStatus = "WAITING_FOR_NODE...";
                });
                _warpController.startHost(
                  passwords: _passwords,
                  masterKey: widget.masterKey,
                  onStatusUpdate: (s) => setModalState(() => _warpStatus = s),
                  onFinished: (success) {
                    security.resumeLocking();
                    if (success) _showSuccessSnackBar("TRANSMISSION_SUCCESSFUL");
                    Navigator.pop(context);
                  },
                );
              });
            }

            return Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00FBFF), width: 1.5),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isHost ? Icons.sensors : Icons.hub_outlined, color: const Color(0xFF00FBFF), size: 42),
                        const SizedBox(height: 12),
                        Text(isHost ? "WARP_BROADCAST_ACTIVE" : "WARP_RECEIVER_MODE",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 14)),
                        const SizedBox(height: 24),
                        if (isHost) ...[
                          if (localIp != "0.0.0.0") ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                              child: QrImageView(data: "PASSGUARD_WARP:$localIp", version: QrVersions.auto, size: 160.0),
                            ),
                            const SizedBox(height: 16),
                            Text("LOCAL_IP: $localIp", style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
                          ] else ...[
                            const CircularProgressIndicator(color: Color(0xFF00FBFF)),
                          ],
                        ] else ...[
                          if (_warpStatus == "IDLE" || _warpStatus.contains("READY") || _warpStatus.contains("ERROR")) ...[
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00FBFF),
                                foregroundColor: Colors.black,
                                minimumSize: const Size(double.infinity, 45),
                              ),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text("SCAN_WARP_QR"),
                              onPressed: () => _handleWarpScanning(setModalState),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Text("— OR MANUAL ENTRY —", style: TextStyle(color: Colors.white24, fontSize: 9)),
                            ),
                            TextField(
                              controller: ipManualController,
                              style: const TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace', fontSize: 13),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.black,
                                hintText: "192.168.1.XX",
                                hintStyle: const TextStyle(color: Colors.white10),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.bolt, color: Color(0xFF00FBFF)),
                                  onPressed: () {
                                    _startManualConnection(ipManualController.text, setModalState);
                                  },
                                ),
                                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00FBFF))),
                              ),
                            ),
                          ],
                        ],

                        const SizedBox(height: 24),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)),
                          child: Text("> $_warpStatus", style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 10, fontFamily: 'monospace')),
                        ),

                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: () {
                            security.resumeLocking();
                            _warpController.stop();
                            _warpStatus = "IDLE";
                            Navigator.pop(context);
                          },
                          child: Text(isHost ? "ABORT_BROADCAST" : "TERMINATE_SESSION", 
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        );
      },
    );
  }

  void _startManualConnection(String ip, Function setModalState) {
    final security = SecurityController();
    if (ip.trim().length < 7) {
      setModalState(() => _warpStatus = "ERROR: INVALID_IP");
      return;
    }
    
    _warpController.startClient(
      hostIp: ip.trim(),
      myMasterKey: widget.masterKey,
      onStatusUpdate: (s) => setModalState(() => _warpStatus = s),
      onDataReceived: (result) {
        if (result.success) {
          security.resumeLocking();
          _handleImportResult(result);
          Navigator.pop(this.context);
        }
      },
    );
  }

  void _handleWarpScanning(Function setModalState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: MobileScanner(
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final String code = barcode.rawValue ?? "";
              if (code.startsWith("PASSGUARD_WARP:")) {
                final String extractedIp = code.split(":")[1];
                Navigator.pop(context);
                _startManualConnection(extractedIp, setModalState);
              }
            }
          },
        ),
      ),
    );
  }

  Future<String> _getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      return "127.0.0.1";
    }
    return "0.0.0.0";
  }

  Widget _buildNetworkStatusIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 15, height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FBFF)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LOCAL_IP: 192.168.1.XX", style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace')),
                Text("STATUS: LISTENING_ON_PORT_8888", style: TextStyle(color: const Color(0xFF00FBFF).withOpacity(0.7), fontSize: 9, fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemGroup({required String label, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8, top: 12),
          child: Text(label, style: const TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(children: items),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<bool> _showTravelDeactivationCheck() async {
    bool confirmed = false;
    final TextEditingController _passController = TextEditingController();
    bool _isObscured = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0E),
          shape: const Border(left: BorderSide(color: Color(0xFFFF00FF), width: 4)),
          title: const Text(
            "⚠️ DEACTIVATE_TRAVEL_PROTOCOL",
            style: TextStyle(
              color: Color(0xFFFF00FF), 
              fontSize: 16, 
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Identity verification required. Enter MASTER_PASSWORD to expose sensitive nodes:",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passController,
                obscureText: _isObscured,
                autofocus: true,
                style: const TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: "ENTER_MASTER_KEY",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00FBFF)),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off, color: Colors.white24, size: 18),
                    onPressed: () => setStateDialog(() => _isObscured = !_isObscured),
                  ),
                ),
                onSubmitted: (_) async {
                  if (_passController.text.isNotEmpty) {
                    await _attemptUnlock(context, _passController.text, (val) => confirmed = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ABORT", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                side: const BorderSide(color: Color(0xFF00FBFF)),
              ),
              onPressed: () async {
                bool isValid = await AuthService.verifyPassword(_passController.text);

                if (isValid) {
                  confirmed = true;
                  if (context.mounted) Navigator.pop(context);
                } else {
                  _passController.clear();
                  _showErrorSnackBar("INVALID_MASTER_KEY: ACCESS_DENIED");
                }
              },
              child: const Text("UNLOCK", style: TextStyle(color: Color(0xFF00FBFF))),
            ),
          ],
        ),
      ),
    );
    
    Future.delayed(const Duration(milliseconds: 200), () {
      _passController.dispose();
    });
    return confirmed;
  }

  Future<void> _attemptUnlock(BuildContext context, String input, Function(bool) setConfirmed) async {
    bool isValid = await AuthService.verifyPassword(input);
    if (isValid) {
      setConfirmed(true);
      if (context.mounted) Navigator.pop(context);
    } else {
      _showErrorSnackBar("INVALID_MASTER_KEY: ACCESS_DENIED");
    }
  }

  void _showUniversalUpgradeConfirmation() {
    final String latestPrefix = EncryptionService.currentVersionPrefix;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        title: Text("> CRYPTO_SYNC: $latestPrefix",
            style: const TextStyle(
                color: Color(0xFF00FBFF), fontFamily: 'monospace')),
        content: Text(
          "All vault records (Passwords, OTP, History, Identities, and Notes) will be migrated to the $latestPrefix standard.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FBFF)),
            onPressed: () async {
              Navigator.pop(dialogContext);

              _showProcessingOverlay();

              try {
                final db = await DBHelper.database;
                final batch = db.batch();
                int totalMigrated = 0;

                final List<Map<String, dynamic>> accounts = await db.query('accounts');
                for (var row in accounts) {
                  Map<String, dynamic> updates = {};
                  bool needsUpdate = false;

                  String currentPass = row['password'] ?? "";
                  if (currentPass.isNotEmpty && !currentPass.startsWith(latestPrefix)) {
                    String decrypted = EncryptionService.decrypt(
                        combinedText: currentPass, masterKeyBytes: widget.masterKey);
                    updates['password'] = EncryptionService.encrypt(decrypted, widget.masterKey);
                    needsUpdate = true;
                  }

                  String? currentOtp = row['otp_seed'];
                  if (currentOtp != null && currentOtp.isNotEmpty && !currentOtp.startsWith(latestPrefix)) {
                    String decrypted = EncryptionService.decrypt(
                        combinedText: currentOtp, masterKeyBytes: widget.masterKey);
                    updates['otp_seed'] = EncryptionService.encrypt(decrypted, widget.masterKey);
                    needsUpdate = true;
                  }

                  String? historyStr = row['password_history'];
                  if (historyStr != null && historyStr.isNotEmpty) {
                    List<String> historyList = historyStr.split(',');
                    List<String> upgradedHistory = [];
                    bool historyChanged = false;
                    for (var oldEntry in historyList) {
                      if (oldEntry.isNotEmpty && !oldEntry.startsWith(latestPrefix)) {
                        try {
                          String decrypted = EncryptionService.decrypt(
                              combinedText: oldEntry, masterKeyBytes: widget.masterKey);
                          upgradedHistory.add(EncryptionService.encrypt(decrypted, widget.masterKey));
                          historyChanged = true;
                        } catch (e) {
                          upgradedHistory.add(oldEntry);
                        }
                      } else {
                        upgradedHistory.add(oldEntry);
                      }
                    }
                    if (historyChanged) {
                      updates['password_history'] = upgradedHistory.join(',');
                      needsUpdate = true;
                    }
                  }

                  String? notesContent = row['notes']; 
                    if (notesContent != null && notesContent.isNotEmpty && !notesContent.startsWith(latestPrefix)) {
                      try {
                        String decrypted = EncryptionService.decrypt(combinedText: notesContent, masterKeyBytes: widget.masterKey);
                        updates['notes'] = EncryptionService.encrypt(decrypted, widget.masterKey);
                        needsUpdate = true;
                      } catch (e) {
                        //
                      }
                    }

                  if (needsUpdate) {
                    updates['updated_at'] = DateTime.now().toIso8601String();
                    batch.update('accounts', updates, where: 'id = ?', whereArgs: [row['id']]);
                    totalMigrated++;
                  }
                }

                final List<Map<String, dynamic>> identities = await db.query('identities');
                for (var row in identities) {
                  Map<String, dynamic> updates = {};
                  bool needsUpdate = false;
                  final sensitiveFields = [
                    'full_name', 'email', 'phone', 'address1', 'city', 'state', 
                    'zip_code', 'country', 'card_number', 'cvv', 'document_number', 'notes'
                  ];
                  for (var field in sensitiveFields) {
                    String? val = row[field];
                    if (val != null && val.isNotEmpty && val.contains('.') && !val.startsWith(latestPrefix)) {
                      try {
                        String decrypted = EncryptionService.decrypt(
                            combinedText: val, masterKeyBytes: widget.masterKey);
                        updates[field] = EncryptionService.encrypt(decrypted, widget.masterKey);
                        needsUpdate = true;
                      } catch (e) {
                        //
                      }
                    }
                  }
                  if (needsUpdate) {
                    updates['updated_at'] = DateTime.now().toIso8601String();
                    batch.update('identities', updates, where: 'id = ?', whereArgs: [row['id']]);
                    totalMigrated++;
                  }
                }

                await batch.commit(noResult: true);

                if (!mounted) return;

                Navigator.of(context).pop();

                _showSuccessSnackBar("SYNC_COMPLETE: $totalMigrated ENTRIES_UPGRADED");
                
                setState(() {});

              } catch (e) {
                //
                if (mounted) {
                  Navigator.of(context).pop();
                  _showErrorSnackBar("SYNC_FAILED: CORE_ENGINE_ERROR");
                }
              }
            },
            child:
                const Text("START_SYNC", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showProcessingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF00FBFF)),
              const SizedBox(height: 20),
              const Text("RE-ENCRYPTING_DATABASE...",
                  style: TextStyle(
                      color: Color(0xFF00FBFF),
                      fontFamily: 'monospace',
                      decoration: TextDecoration.none,
                      fontSize: 12)),
            ],
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
        contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '> SESSION_TIMEOUT_CONFIG', 
              style: TextStyle(
                color: Color(0xFF00FBFF), 
                fontSize: 14, 
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold
              )
            ),
            const SizedBox(height: 8),
            const Text(
              'Select inactivity threshold:', 
              style: TextStyle(color: Colors.white38, fontSize: 11)
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 10),
              _buildTimeoutOption('1 MINUTE', 1),
              _buildTimeoutOption('5 MINUTES', 5),
              _buildTimeoutOption('15 MINUTES', 15),
              _buildTimeoutOption('30 MINUTES', 30),
              _buildTimeoutOption('NEVER (UNSAFE)', 0),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ABORT', style: TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeoutOption(String label, int minutes) {
    IconData optionIcon = minutes == 0 ? Icons.all_inclusive : Icons.timer_outlined;
    Color labelColor = minutes == 0 ? const Color(0xFFFF3131) : Colors.white70;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () async {
          await AuthService.setSessionTimeout(minutes);
          if (minutes > 0) {
            SessionManager().setTimeoutDuration(Duration(minutes: minutes));
            SessionManager().setEnabled(true);
          } else {
            SessionManager().setEnabled(false);
          }
          if (mounted) Navigator.pop(context);
          _showSuccessSnackBar('TIMEOUT_SET: $label');
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Icon(optionIcon, size: 16, color: labelColor.withOpacity(0.5)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label, 
                  style: TextStyle(
                    color: labelColor, 
                    fontSize: 12, 
                    fontFamily: 'monospace',
                    letterSpacing: 1
                  )
                ),
              ),
              const Icon(Icons.chevron_right, size: 14, color: Colors.white10),
            ],
          ),
        ),
      ),
    );
  }

  void _showColdStorageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D12),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.ac_unit_rounded, color: Color(0xFF00FBFF), size: 20),
            const SizedBox(width: 12),
            const Text(
              "COLD_STORAGE",
              style: TextStyle(
                color: Color(0xFF00FBFF), 
                fontFamily: 'monospace', 
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Protocol for steganographic data injection and extraction.",
              style: TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace'),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 25),

            InkWell(
              onTap: () { Navigator.pop(context); _handleImageInjection(); },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FBFF).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00FBFF).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.drive_folder_upload_rounded, color: Color(0xFF00FBFF)),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("INJECT_PAYLOAD", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text("Hide data inside image pixels", style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: const Color(0xFF00FBFF).withOpacity(0.3), size: 14),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 12),

            InkWell(
              onTap: () { Navigator.pop(context); _handleImageExtraction(); },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF00FF).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF00FF).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.biotech_sharp, color: Color(0xFFFF00FF)),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("EXTRACT_DATA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text("Retrieve nodes from carrier file", style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: const Color(0xFFFF00FF).withOpacity(0.3), size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE_INTERFACE", 
              style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
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
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF0A0A0E),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40, height: 40,
                  child: CircularProgressIndicator(color: Color(0xFF00FBFF), strokeWidth: 2),
                ),
                const SizedBox(height: 20),
                const Text("ENCRYPTING_PACKAGE...", 
                  style: TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        );
      }

      final String encryptedData = await SyncService.exportSecurePackage(_passwords, widget.masterKey);
      final String compressedData = CompressionService.compressForQR(encryptedData);
      final bool fitsInQR = CompressionService.fitsInQR(compressedData);
      final double sizeKB = CompressionService.getSizeKB(compressedData);

      if (mounted) Navigator.pop(context);

      if (!fitsInQR) {
        HapticFeedback.vibrate(); 
        if (!mounted) return;

        final int avgSizePerPassword = compressedData.length ~/ _passwords.length;
        final int maxPasswords = 2900 ~/ avgSizePerPassword;
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF0A0A0E),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFFF3131), width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Row(
              children: [
                Icon(Icons.gpp_maybe, color: Color(0xFFFF3131)),
                SizedBox(width: 10),
                Text('BUFFER_OVERFLOW', style: TextStyle(color: Color(0xFFFF3131), fontFamily: 'monospace', fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('The vault size exceeds QR standard capacity.', 
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      _buildStatRow('CURRENT_PAYLOAD:', '${sizeKB.toStringAsFixed(1)} KB', const Color(0xFFFF3131)),
                      _buildStatRow('HARD_LIMIT:', '2.8 KB', Colors.white30),
                      const Divider(color: Colors.white10),
                      _buildStatRow('MAX_CAPACITY:', '~$maxPasswords ACCOUNTS', Colors.orange),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ALTERNATIVE_PROTOCOLS:', 
                    style: TextStyle(color: Color(0xFF00FBFF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
                const SizedBox(height: 10),
                _buildAlternativeOption(
                  icon: Icons.blur_on,
                  label: 'Cold Storage (Image)',
                  description: 'Use steganography for large vaults.',
                  onTap: () { Navigator.pop(context); _showColdStorageDialog(); }
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ABORT', style: TextStyle(color: Colors.white30, fontFamily: 'monospace')),
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

      HapticFeedback.heavyImpact();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0E),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("QR_STREAM_ACTIVE", style: TextStyle(color: Color(0xFF00FBFF), fontSize: 12, fontFamily: 'monospace')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF00FF41).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: const Text("ENCRYPTED", style: TextStyle(color: Color(0xFF00FF41), fontSize: 8)),
              )
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCompactStat("ACCOUNTS", "${_passwords.length}"),
                      _buildCompactStat("SIZE", "${sizeKB.toStringAsFixed(2)}K"),
                      _buildCompactStat("RATIO", "${compressionRatio.toStringAsFixed(0)}%"),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF00FBFF).withOpacity(0.2), blurRadius: 15, spreadRadius: 2)
                        ]
                      ),
                      child: QrImageView(
                        data: compressedData,
                        version: QrVersions.auto,
                        size: 200.0,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text("ALINE SOURCE SCANNER WITH THIS CODE", 
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.5)),
              ],
            ),
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('DISCONNECT_STREAM', style: TextStyle(color: Color(0xFF00FBFF), fontSize: 11, fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      _showErrorSnackBar("SYSTEM_CRITICAL_ERROR: ${e.toString()}");
    }
  }

  Widget _buildCompactStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8, fontFamily: 'monospace')),
        Text(value, style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildAlternativeOption({required IconData icon, required String label, required String description, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(4),
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
                  Text(description, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white12, size: 16),
          ],
        ),
      ),
    );
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
                            combinedText: encryptedStr,
                            masterKeyBytes: widget.masterKey
                        );
                      } catch (e) {
                        decryptedJson = EncryptionService.decrypt(
                            combinedText: compressedData,
                            masterKeyBytes: widget.masterKey
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
        final decryptedPass = EncryptionService.decrypt(combinedText: password.password, masterKeyBytes: widget.masterKey);
        final decryptedNotes = password.notes != null 
          ? EncryptionService.decrypt(combinedText: password.notes!, masterKeyBytes: widget.masterKey)
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

  double _calculateLiveEntropy(String password) {
    if (password.isEmpty) return 0.0;
    
    Set<String> charset = {};
    if (password.contains(RegExp(r'[a-z]'))) charset.addAll("abcdefghijklmnopqrstuvwxyz".split(''));
    if (password.contains(RegExp(r'[A-Z]'))) charset.addAll("ABCDEFGHIJKLMNOPQRSTUVWXYZ".split(''));
    if (password.contains(RegExp(r'[0-9]'))) charset.addAll("0123456789".split(''));
    if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) charset.addAll("!@#\$%^&*()_+".split(''));

    if (charset.isEmpty) return 0.0;
    return password.length * (log(charset.length) / log(2));
  }

  void _showForm({PasswordModel? existingPassword}) {
    final platformC = TextEditingController(text: existingPassword?.platform ?? '');
    final userC = TextEditingController(text: existingPassword?.username ?? '');
    
    final String initialPass = existingPassword != null 
        ? EncryptionService.decrypt(combinedText: existingPassword.password, masterKeyBytes: widget.masterKey)
        : '';
    final passC = TextEditingController(text: initialPass);

    final notesC = TextEditingController(
      text: existingPassword?.notes != null
        ? EncryptionService.decrypt(combinedText: existingPassword!.notes!, masterKeyBytes: widget.masterKey)
        : ''
    );

    double localEntropy = _calculateLiveEntropy(initialPass);
    String localSelectedCategory = existingPassword?.category ?? 'PERSONAL';

    final List<Map<String, dynamic>> categories = [
      {'name': 'PERSONAL', 'icon': Icons.person_rounded, 'color': const Color(0xFF00FBFF)},
      {'name': 'WORK', 'icon': Icons.business_center_rounded, 'color': const Color(0xFFFF00FF)},
      {'name': 'FINANCE', 'icon': Icons.account_balance_wallet_rounded, 'color': const Color(0xFF00FF00)},
      {'name': 'SOCIAL', 'icon': Icons.public_rounded, 'color': const Color(0xFFFFFF00)},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D12),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF00FBFF), width: 1),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              top: 15, left: 24, right: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      existingPassword == null ? "> INITIALIZE_NEW_NODE" : "> MODIFY_NODE_DATA",
                      style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 14, letterSpacing: 2, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    ),
                    Icon(Icons.terminal, color: Colors.white.withOpacity(0.1), size: 18),
                  ],
                ),
                const SizedBox(height: 25),

                _buildCyberInput(controller: platformC, label: "PLATFORM_ID", icon: Icons.language_rounded),
                const SizedBox(height: 16),
                _buildCyberInput(controller: userC, label: "USER_IDENTIFIER", icon: Icons.alternate_email_rounded),
                const SizedBox(height: 16),

                _buildCyberInput(
                  controller: passC, 
                  label: "ACCESS_CREDENTIAL", 
                  icon: Icons.lock_outline_rounded,
                  isPassword: true,
                  onChanged: (value) {
                    setModalState(() {
                      localEntropy = _calculateLiveEntropy(value);
                    });
                  },
                  suffix: IconButton(
                    icon: const Icon(Icons.auto_fix_high, color: Color(0xFFFF00FF), size: 20),
                    onPressed: () async {
                      final result = await showDialog<String>(
                        context: context,
                        builder: (context) => const PasswordGeneratorDialog(),
                      );
                      if (result != null) {
                        setModalState(() {
                          passC.text = result;
                          localEntropy = _calculateLiveEntropy(result);
                        });
                      }
                    },
                  ),
                ),
                
                const SizedBox(height: 12),
                _buildEntropyBar(localEntropy),
                const SizedBox(height: 20),

                _buildCyberInput(controller: notesC, label: "ENCRYPTED_NOTES", icon: Icons.description_outlined, maxLines: 2),
                
                const SizedBox(height: 25),

                const Text("CLASSIFICATION_TAG:",
                    style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontFamily: 'monospace')),
                const SizedBox(height: 12),
                
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final bool isSelected = localSelectedCategory == cat['name'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Row(
                            children: [
                              Icon(cat['icon'], size: 14, color: isSelected ? Colors.black : cat['color']),
                              const SizedBox(width: 6),
                              Text(cat['name'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          selected: isSelected,
                          selectedColor: cat['color'],
                          backgroundColor: const Color(0xFF16161D),
                          side: BorderSide(color: isSelected ? Colors.transparent : cat['color'].withOpacity(0.3)),
                          showCheckmark: false,
                          labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70),
                          onSelected: (selected) {
                            setModalState(() => localSelectedCategory = cat['name']);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
                const SizedBox(height: 35),

                GestureDetector(
                  onTap: () async {
                    if (platformC.text.isNotEmpty && passC.text.isNotEmpty) {
                      final db = await DBHelper.database;
                      final encryptedPass = EncryptionService.encrypt(passC.text, widget.masterKey);
                      final encryptedNotes = notesC.text.isNotEmpty 
                          ? EncryptionService.encrypt(notesC.text, widget.masterKey) 
                          : null;

                      final pepper = derivePepper(widget.masterKey);
                      final passwordFp = passwordFingerprintBase64(
                        passwordPlaintext: passC.text,
                        pepper: pepper,
                      );

                      if (existingPassword == null) {
                        await db.insert('accounts', PasswordModel(
                          platform: platformC.text,
                          username: userC.text,
                          password: encryptedPass,
                          passwordFingerprint: passwordFp,
                          category: localSelectedCategory,
                          notes: encryptedNotes,
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        ).toMap());
                      } else {
                        List<String> history = existingPassword.passwordHistory ?? [];
                        if (encryptedPass != existingPassword.password) {
                          history.add(existingPassword.password);
                          if (history.length > 5) history.removeAt(0);
                        }
                        await db.update('accounts', PasswordModel(
                          id: existingPassword.id,
                          platform: platformC.text,
                          username: userC.text,
                          password: encryptedPass,
                          passwordFingerprint: passwordFp,
                          category: localSelectedCategory,
                          notes: encryptedNotes,
                          createdAt: existingPassword.createdAt,
                          updatedAt: DateTime.now(),
                          otpSeed: existingPassword.otpSeed,
                          isFavorite: existingPassword.isFavorite,
                          passwordHistory: history,
                        ).toMap(), where: 'id = ?', whereArgs: [existingPassword.id]);
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        _loadPasswords();
                        _showSuccessSnackBar(existingPassword == null ? "NODE_SECURED" : "NODE_UPDATED");
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF00FBFF), Color(0xFF00A2FF)]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00FBFF).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))
                      ],
                    ),
                    child: Center(
                      child: Text(
                        existingPassword == null ? "UPLOAD_TO_ENCRYPTED_CORE" : "COMMIT_CHANGES",
                        style: const TextStyle(color: Colors.black, fontSize: 13, letterSpacing: 1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntropyBar(double entropy) {
    Color color;
    String label;
    double progress = (entropy / 128).clamp(0.0, 1.0);

    if (entropy < 45) {
      color = const Color(0xFFFF4545);
      label = "VULNERABLE_NODE";
    } else if (entropy < 75) {
      color = const Color(0xFFFFB344);
      label = "STANDARD_ENCRYPTION";
    } else if (entropy < 128) {
      color = const Color(0xFF00FBFF);
      label = "HIGH_SECURED";
    } else {
      color = const Color(0xFF00FF00);
      label = "HIGH_ENTROPY_SECURED";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1)),
            Text("${entropy.toStringAsFixed(1)} BITS", style: TextStyle(color: color.withOpacity(0.5), fontSize: 9, fontFamily: 'monospace')),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(
              width: double.infinity,
              height: 2,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              width: (MediaQuery.of(context).size.width - 48) * progress,
              height: 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, spreadRadius: 1)],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCyberInput({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    int maxLines = 1,
    bool isPassword = false,
    Widget? suffix,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      obscureText: isPassword,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF00FBFF).withOpacity(0.5), size: 20),
        suffixIcon: suffix,
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white30, fontSize: 12, letterSpacing: 1),
        filled: true,
        fillColor: const Color(0xFF16161D),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00FBFF), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

                      if (secret != null && secret.isNotEmpty) {
                        Navigator.pop(context);
                        _showAssignOTPDialog(code);
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

  void _showAssignOTPDialog(String otpauthRaw) {
    final parsed = parseOtpauthUri(otpauthRaw);
    if (parsed == null) {
      _showErrorSnackBar("ERROR: INVALID_OTP_QR");
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
        title: const Text(
          "SELECT_ACCOUNT_FOR_2FA",
          style: TextStyle(color: Color(0xFF00FBFF), fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _passwords.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(_passwords[i].platform, style: const TextStyle(color: Colors.white)),
              subtitle: Text(_passwords[i].username, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () async {
                String cleanSecret = parsed.secret.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z2-7=]'), '');
                cleanSecret = cleanSecret.replaceAll('=', '');

                final db = await DBHelper.database;

                final masterKeyString = widget.masterKey;
                final encryptedSeed = EncryptionService.encrypt(cleanSecret, masterKeyString);

                final metaJson = jsonEncode(parsed.meta.toJson());
                final encryptedMeta = EncryptionService.encrypt(metaJson, masterKeyString);

                await db.update(
                  'accounts',
                  {
                    'otp_seed': encryptedSeed,
                    'otp_meta': encryptedMeta,
                    'updated_at': DateTime.now().toIso8601String(),
                  },
                  where: 'id = ?',
                  whereArgs: [_passwords[i].id],
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

  String _normalizeTotpSecret(String input) {
    var s = input.trim();

    if (s.startsWith('otpauth://')) {
      final uri = Uri.tryParse(s);
      final secret = uri?.queryParameters['secret'];
      if (secret != null && secret.isNotEmpty) s = secret;
    }

    s = s.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7=]'), '');
    s = s.replaceAll('=', '');

    return s;
  }

  bool _looksLikeBase32Secret(String s) {
    return RegExp(r'^[A-Z2-7]+$').hasMatch(s) && s.length >= 16;
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
    final masterKeyBytes = widget.masterKey;

    Future<List<Map<String, dynamic>>> loadCodes() async {
      return await db.query('recovery_codes', 
        where: 'account_id = ?', 
        whereArgs: [accountId],
        orderBy: 'is_used ASC, created_at DESC'
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: const Color(0xFFFF00FF).withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(color: const Color(0xFFFF00FF).withOpacity(0.1), blurRadius: 30, spreadRadius: 5),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF00FF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF00FF).withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.security, color: Color(0xFFFF00FF), size: 22),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("ENCRYPTED_VAULT", 
                              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, letterSpacing: 2, fontFamily: 'monospace')),
                            Text(platform.toUpperCase(), 
                              style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: "RE-ENCRYPT_ALL",
                        icon: const Icon(Icons.sync_lock_rounded, color: Color(0xFF00FBFF)),
                        onPressed: () async {
                          final allCodes = await loadCodes();
                          int count = 0;
                          for (var c in allCodes) {
                            if (!(c['code'] as String).contains('.')) {
                              final enc = EncryptionService.encrypt(c['code'], widget.masterKey);
                              await db.update('recovery_codes', {'code': enc}, where: 'id = ?', whereArgs: [c['id']]);
                              count++;
                            }
                          }
                          setModalState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("> $count NODES_SECURED"), backgroundColor: const Color(0xFF00FBFF), behavior: SnackBarBehavior.floating)
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: loadCodes(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.terminal_rounded, color: Colors.white.withOpacity(0.03), size: 80),
                                const Text("NO_RECOVERY_DATA_DETECTED", style: TextStyle(color: Colors.white24, fontFamily: 'monospace', fontSize: 12)),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: snapshot.data!.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final item = snapshot.data![i];
                            final String raw = item['code'] ?? "";
                            final bool isUsed = item['is_used'] == 1;
                            final bool isEnc = raw.contains('.');
                            
                            String display;
                            bool error = false;
                            if (isEnc) {
                              try {
                                display = EncryptionService.decrypt(combinedText: raw, masterKeyBytes: masterKeyBytes);
                              } catch (e) { display = "DECRYPT_ERROR"; error = true; }
                            } else {
                              display = raw;
                            }

                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF16161D),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isUsed ? Colors.white10 : (error ? Colors.red.withOpacity(0.5) : (isEnc ? const Color(0xFF00FF00).withOpacity(0.2) : Colors.orange.withOpacity(0.3))),
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  isUsed ? Icons.check_circle_outline : (isEnc ? Icons.lock_outline : Icons.no_encryption_gmailerrorred_outlined),
                                  color: isUsed ? Colors.white24 : (error ? Colors.red : (isEnc ? const Color(0xFF00FF00) : Colors.orange)),
                                ),
                                title: Text(
                                  display,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: isUsed ? Colors.white24 : (error ? Colors.red : Colors.white),
                                    decoration: isUsed ? TextDecoration.lineThrough : null,
                                    letterSpacing: 1.1
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!error) IconButton(
                                      icon: const Icon(Icons.copy_all_rounded, color: Color(0xFF00FBFF), size: 20),
                                      onPressed: () => Clipboard.setData(ClipboardData(text: display)),
                                    ),
                                    Checkbox(
                                      activeColor: const Color(0xFFFF00FF),
                                      value: isUsed,
                                      onChanged: (v) async {
                                        await db.update('recovery_codes', {'is_used': v! ? 1 : 0}, where: 'id = ?', whereArgs: [item['id']]);
                                        setModalState(() {});
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                      onPressed: () async {
                                        await db.delete('recovery_codes', where: 'id = ?', whereArgs: [item['id']]);
                                        setModalState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 15),

                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: LinearGradient(
                        colors: [const Color(0xFF00FBFF).withOpacity(0.1), Colors.transparent],
                      ),
                      border: Border.all(color: const Color(0xFF00FBFF).withOpacity(0.4)),
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, color: Color(0xFF00FBFF)),
                      label: const Text("IMPORT_ENCRYPTED_STREAM", 
                        style: TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final security = SecurityController(); 
                        security.pauseLocking();

                        try {
                          FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
                          security.resumeLocking();

                          if (result != null && result.files.single.path != null) {
                            final file = File(result.files.single.path!);
                            final lines = await file.readAsLines();
                            List<String> detectedCodes = [];

                            for (var line in lines) {
                              String clean = line.trim();
                              if (clean.length >= 6 && !clean.contains(" ") && !clean.contains("=")) {
                                detectedCodes.add(clean);
                              }
                            }

                            if (detectedCodes.isNotEmpty && context.mounted) {
                              bool? confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  backgroundColor: const Color(0xFF0D0D12),
                                  shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFF00FBFF)), borderRadius: BorderRadius.circular(15)),
                                  title: const Text("> INCOMING_DATA", style: TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace')),
                                  content: Text("Found ${detectedCodes.length} codes. Import and encrypt now?", style: const TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("ABORT", style: TextStyle(color: Colors.white38))),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FBFF)),
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text("EXECUTE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                for (var code in detectedCodes) {
                                  final encrypted = EncryptionService.encrypt(code, widget.masterKey);
                                  await db.insert('recovery_codes', {
                                    'account_id': accountId,
                                    'code': encrypted,
                                    'is_used': 0,
                                    'created_at': DateTime.now().toIso8601String(),
                                  });
                                }
                                setModalState(() {});
                              }
                            }
                          }
                        } catch (e) {
                          security.resumeLocking();
                        }
                      },
                    ),
                  ),
                ],
              ),
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
              final decryptedOldPass = EncryptionService.decrypt(combinedText: encryptedOldPass, masterKeyBytes: widget.masterKey);
              
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
    final EdgeInsets systemPadding = MediaQuery.of(context).padding;
    return GestureDetector(
      onTap: _onUserInteraction,
      onPanUpdate: (_) => _onUserInteraction(),
      child: Scaffold(
        backgroundColor: const Color(0xFF050505),
        extendBody: false,
        appBar: AppBar(
          backgroundColor: const Color(0xFF050505),
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              height: 1.0,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent, 
                    const Color(0xFF00FBFF).withOpacity(0.3), 
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),
          title: _isSearching
              ? Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FBFF).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00FBFF).withOpacity(0.2)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: Color(0xFF00FBFF), fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: "SCANNING_NODES...",
                      hintStyle: TextStyle(color: Colors.white12, fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (v) => _loadPasswords(query: v),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "VAULT_INTERFACE",
                      style: TextStyle(
                        color: Color(0xFF00FBFF), 
                        fontSize: 10, 
                        letterSpacing: 2, 
                        fontFamily: 'monospace', 
                        fontWeight: FontWeight.bold
                      ),
                    ),
                    ValueListenableBuilder<Duration?>(
                      valueListenable: SessionManager().remainingTimeNotifier,
                      builder: (context, remaining, _) {
                        if (remaining == null) return const SizedBox.shrink();
                        final minutes = remaining.inMinutes;
                        final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
                        final isUrgent = remaining.inSeconds < 60;
                        final timerColor = isUrgent ? const Color(0xFFFF3131) : const Color(0xFF00FF41);

                        return Row(
                          children: [
                            Container(
                              width: 4, height: 4,
                              decoration: BoxDecoration(
                                color: timerColor,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: timerColor, blurRadius: 4)],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "SESSION_EXPIRE: $minutes:$seconds",
                              style: TextStyle(
                                color: timerColor.withOpacity(0.7),
                                fontSize: 9,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
          actions: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(_isSearching ? Icons.close : Icons.search, 
                    color: const Color(0xFF00FBFF), size: 20),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _loadPasswords();
                  }
                });
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.filter_list, color: Color(0xFFFF00FF), size: 20),
              onPressed: _showFilterMenu,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.sort, color: Color(0xFFFF00FF), size: 20),
              onPressed: _showSortMenu,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.tune, color: Color(0xFFFF00FF), size: 20),
              onPressed: _showSystemMenu,
            ),
            const SizedBox(width: 5),
          ],
        ),

        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _selectedIndex = index);
              },
              children: [
                _buildPasswordList(),
                IdentitiesVaultScreen(key: _identitiesKey, masterKey: widget.masterKey),
                DashboardScreen(
                    key: _dashboardKey,
                    masterKey: widget.masterKey,
                    onRepairRequested: (model) => _showForm(existingPassword: model)
                ),
              ],
            ),
          ),
        ),

        bottomNavigationBar: Container(
          padding: EdgeInsets.only(bottom: systemPadding.bottom > 0 ? systemPadding.bottom : 0),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0E).withOpacity(0.95),
            border: const Border(
              top: BorderSide(color: Color(0xFF00FBFF), width: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00FBFF).withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: BottomNavigationBar(
            onTap: (index) {
              HapticFeedback.mediumImpact();
              _onUserInteraction();
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutQuart,
              );
            },
            currentIndex: _selectedIndex,
            elevation: 0,
            backgroundColor: Colors.transparent,
            selectedItemColor: const Color(0xFF00FBFF),
            unselectedItemColor: Colors.white24,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: const TextStyle(
              fontFamily: 'monospace', 
              fontSize: 10, 
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
            unselectedLabelStyle: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.vpn_key_outlined), 
                activeIcon: Icon(Icons.key), 
                label: "KEYS"
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.badge_outlined), 
                activeIcon: Icon(Icons.badge), 
                label: "IDS"
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.terminal_outlined), 
                activeIcon: Icon(Icons.terminal), 
                label: "DASH"
              ),
              //BottomNavigationBarItem(
                //icon: Icon(Icons.folder_special),
                //activeIcon: Icon(Icons.folder),
                //label: "FILES"
              //), 
            ],
          ),
        ),

        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: systemPadding.bottom > 0 ? 0 : 10),
          child: _buildTabSpecificFab(),
        ),
      ),
    );
  }

  Widget? _buildTabSpecificFab() {
    Widget? fab;

    switch (_selectedIndex) {
      case 0:
        fab = _buildFabPasswords();
        break;
      case 1:
        fab = FloatingActionButton(
          key: const ValueKey('fab_id'),
          heroTag: "fab_id",
          backgroundColor: const Color(0xFF00FBFF),
          child: const Icon(Icons.add_moderator, color: Colors.black),
          onPressed: () {
            _onUserInteraction();
            _identitiesKey.currentState?.showIdentityFormExternal();
          },
        );
        break;
      case 2:
        fab = FloatingActionButton(
          key: const ValueKey('fab_dash'),
          heroTag: "fab_dash",
          backgroundColor: const Color(0xFF00FBFF),
          child: const Icon(Icons.refresh_sharp, color: Colors.black),
          onPressed: () {
            _onUserInteraction();
            _dashboardKey.currentState?.performSecurityAudit();
          },
        );
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ScaleTransition(scale: animation, child: child);
      },
      child: fab,
    );
  }

  String? _getTotpSecretPlainCached(PasswordModel item) {
    final id = item.id;
    if (id == null) return null;

    if (_totpSecretCache.containsKey(id)) return _totpSecretCache[id];

    final raw = item.otpSeed;
    if (raw == null || raw.isEmpty) {
      _totpSecretCache[id] = null;
      return null;
    }

    String? plain;

    final isEnc = raw.startsWith('v4.') || raw.startsWith('v3.') || raw.startsWith('v2.') || raw.startsWith('v1.');
    if (isEnc) {
      final dec = EncryptionService.decrypt(combinedText: raw, masterKeyBytes: widget.masterKey);
      if (dec.isNotEmpty && !dec.startsWith('ERROR:')) {
        plain = _normalizeTotpSecret(dec);
        if (!_looksLikeBase32Secret(plain)) plain = null;
      }
    } else {
      final norm = _normalizeTotpSecret(raw);
      plain = _looksLikeBase32Secret(norm) ? norm : null;
    }

    _totpSecretCache[id] = plain;
    return plain;
  }

  TotpMeta _getTotpMetaOrDefault(PasswordModel item) {
    final raw = item.otpMeta;
    if (raw == null || raw.isEmpty) return const TotpMeta();

    if (raw.startsWith('v4.') || raw.startsWith('v3.') || raw.startsWith('v2.') || raw.startsWith('v1.')) {
      final dec = EncryptionService.decrypt(
        combinedText: raw,
        masterKeyBytes: widget.masterKey,
      );
      if (dec.isEmpty || dec.startsWith('ERROR:')) return const TotpMeta();
      try {
        return TotpMeta.fromJson(jsonDecode(dec) as Map<String, dynamic>);
      } catch (_) {
        return const TotpMeta();
      }
    }

    try {
      return TotpMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const TotpMeta();
    }
  }

  Algorithm _mapAlgorithm(String algo) {
    switch (algo.toUpperCase()) {
      case 'SHA256':
        return Algorithm.SHA256;
      case 'SHA512':
        return Algorithm.SHA512;
      default:
        return Algorithm.SHA1;
    }
  }

  Widget _buildPasswordList() {
    if (_passwords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 100, color: Colors.white.withOpacity(0.05)),
            const SizedBox(height: 24),
            const Text("> NO_DATA_DETECTED", 
              style: TextStyle(color: Color(0xFF00FBFF), fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("INITIALIZE_DATABASE_BY_TAPPING_+", 
              style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 100),
      itemCount: _passwords.length,
      itemBuilder: (context, index) {
        final item = _passwords[index];

        final int secondsPassed = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;
        final double progress = (30 - secondsPassed) / 30;
        final Color progressColor = progress > 0.3 ? const Color(0xFF00FBFF) : Colors.redAccent;

        final Map<String, Color> catColors = {
          'WORK': const Color(0xFFFF00FF),
          'FINANCE': const Color(0xFF00FF00),
          'SOCIAL': const Color(0xFFFFFF00),
        };
        final Color categoryColor = catColors[item.category] ?? const Color(0xFF00FBFF);

        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 400 + (index * 60).clamp(0, 500)),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutQuart,
          builder: (context, animValue, child) {
            return Opacity(
              opacity: animValue,
              child: Transform.translate(
                offset: Offset(30 * (1 - animValue), 0),
                child: child,
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: categoryColor.withOpacity(0.15),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: categoryColor.withOpacity(0.2)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          item.faviconUrl,
                          width: 30, height: 30,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(_getCategoryIcon(item.category), color: categoryColor, size: 24),
                        ),
                      ),
                      if (item.isFavorite)
                        const Positioned(
                          top: 2, right: 2,
                          child: Icon(Icons.star, color: Colors.yellow, size: 10),
                        ),
                    ],
                  ),
                ),
                title: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.platform.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      if (item.isTravelSafe)
                        const Icon(Icons.shield_rounded, color: Color(0xFF00FBFF), size: 14),
                    ],
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.username,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontFamily: 'monospace'),
                    ),

                    if (item.otpSeed?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Icon(Icons.fingerprint, size: 12, color: Color(0xFF00FBFF)),
                                Text(
                                  "SECURE_TOKEN",
                                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8, letterSpacing: 1),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Builder(builder: (context) {
                              String code = "------";
                              try {
                                final secret = _getTotpSecretPlainCached(item);
                                final meta = _getTotpMetaOrDefault(item);
                                if (secret != null) {
                                  code = OTP.generateTOTPCodeString(
                                    secret, _totpNowMs,
                                    interval: meta.period,
                                    length: meta.digits,
                                    algorithm: _mapAlgorithm(meta.algorithm),
                                    isGoogle: true,
                                  ).replaceAllMapped(RegExp(r".{3}"), (m) => "${m.group(0)} ");
                                }
                              } catch (_) {}
                              
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                                child: Text(
                                  code,
                                  key: ValueKey(code),
                                  style: const TextStyle(
                                    color: Color(0xFF00FBFF),
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    letterSpacing: 2,
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 2,
                                backgroundColor: Colors.white.withOpacity(0.05),
                                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  color: const Color(0xFF1A1A23),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) async {
                    switch (value) {
                      case 'favorite':
                        _toggleFavorite(item);
                        break;
                        
                      case 'view':
                        String dec = EncryptionService.decrypt(
                          combinedText: item.password,
                          masterKeyBytes: widget.masterKey,
                          onUpgrade: (v4Data) {
                            () async {
                              final db = await DBHelper.database;
                              await db.update(
                                'accounts',
                                {
                                  'password': v4Data,
                                  'updated_at': DateTime.now().toIso8601String(),
                                },
                                where: 'id = ?',
                                whereArgs: [item.id],
                              );
                            }();
                          },
                        );

                        if (item.passwordFingerprint == null || item.passwordFingerprint!.isEmpty) {
                          final pepper = derivePepper(widget.masterKey);
                          final fp = passwordFingerprintBase64(
                            passwordPlaintext: dec,
                            pepper: pepper,
                          );

                          () async {
                            final db = await DBHelper.database;
                            await db.update(
                              'accounts',
                              {
                                'password_fp': fp,
                                'updated_at': DateTime.now().toIso8601String(),
                              },
                              where: 'id = ?',
                              whereArgs: [item.id],
                            );
                          }();
                        }

                        String? decryptedNotes;
                        if (item.notes != null && item.notes!.isNotEmpty) {
                          decryptedNotes = EncryptionService.decrypt(
                            combinedText: item.notes!,
                            masterKeyBytes: widget.masterKey,
                            onUpgrade: (v4Data) {
                              () async {
                                final db = await DBHelper.database;
                                await db.update(
                                  'accounts',
                                  {
                                    'notes': v4Data,
                                    'updated_at': DateTime.now().toIso8601String(),
                                  },
                                  where: 'id = ?',
                                  whereArgs: [item.id],
                                );
                              }();
                            },
                          );
                        }

                        await DBHelper.updateLastUsed(item.id!);
                        _onUserInteraction();

                        if (!mounted) return;

                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: const Color(0xFF0A0A0E),
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(color: Color(0xFF00FBFF), width: 1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            title: Row(
                              children: [
                                const Text("> ", style: TextStyle(color: Color(0xFF00FBFF))),
                                Expanded(
                                  child: Text(
                                    item.platform.toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'monospace'),
                                  ),
                                ),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 1200),
                                  builder: (context, value, _) => LinearProgressIndicator(
                                    value: value,
                                    backgroundColor: Colors.white10,
                                    color: const Color(0xFF00FBFF).withOpacity(0.5),
                                    minHeight: 1,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                const Text('USERNAME:', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                                SelectableText(item.username, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                const SizedBox(height: 20),                        
                                const Text('PASSWORD:', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                                CyberTypewriterText(
                                  text: dec,
                                  style: const TextStyle(
                                    color: Color(0xFF00FBFF),
                                    fontSize: 18,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),

                                if (decryptedNotes != null) ...[
                                  const SizedBox(height: 20),
                                  const Text('SECURE_NOTES:', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                                  CyberTypewriterText(
                                    text: decryptedNotes!,
                                    speed: const Duration(milliseconds: 15),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                ],
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text(
                                  'TERMINATE_SESSION',
                                  style: TextStyle(color: Colors.white30, fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ),
                            ],
                          ),
                        );
                        break;
                        
                      case 'copy':
                        String dec = EncryptionService.decrypt(combinedText: item.password, masterKeyBytes: widget.masterKey);
                        await Clipboard.setData(ClipboardData(text: dec));
                        await DBHelper.updateLastUsed(item.id!);
                        _onUserInteraction();
                        
                        _clipboardTimer?.cancel();
                        _showSuccessSnackBar("DATA_COPIED: 30s AUTO_CLEAR");
                        
                        _clipboardTimer = Timer(const Duration(seconds: 30), () async {
                          await Clipboard.setData(const ClipboardData(text: ""));
                        });
                        break;
                        
                      case 'recovery':
                        _showRecoveryManager(item.id!, item.platform);
                        break;
                        
                      case 'history':
                        _showPasswordHistory(item);
                        break;
                        
                      case 'edit':
                        _showForm(existingPassword: item);
                        break;

                      case 'travel_safe':
                        final db = await DBHelper.database;
                        await db.update(
                          'accounts',
                          {'is_travel_safe': item.isTravelSafe ? 0 : 1},
                          where: 'id = ?',
                          whereArgs: [item.id],
                        );
                        _loadPasswords();
                        _showSuccessSnackBar(item.isTravelSafe ? "NODE_REMOVED_FROM_SAFE_LIST" : "NODE_MARKED_AS_TRAVEL_SAFE");
                        break;
                        
                      case 'delete':
                        bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF0A0A0E),
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(color: Colors.red, width: 1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            title: const Text('> CONFIRM_DELETE', 
                                            style: TextStyle(color: Colors.red, fontFamily: 'monospace', fontSize: 14)),
                            content: Text('Delete ${item.platform}?',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    _buildPopupItem('view', Icons.remove_red_eye_outlined, 'VIEW_PASSWORD', color: const Color(0xFF00FBFF)),
                    _buildPopupItem('copy', Icons.copy_all_rounded, 'COPY_PASSWORD'),
                    const PopupMenuDivider(height: 1),
                    _buildPopupItem(
                      'favorite', 
                      item.isFavorite ? Icons.star : Icons.star_border, 
                      item.isFavorite ? 'REMOVE_FAVORITE' : 'MARK_FAVORITE', 
                      color: item.isFavorite ? Colors.yellow : Colors.white70
                    ),
                    _buildPopupItem(
                      'travel_safe', 
                      Icons.flight_takeoff_rounded, 
                      item.isTravelSafe ? 'DISABLE_TRAVEL_MODE' : 'ENABLE_TRAVEL_MODE',
                      color: item.isTravelSafe ? const Color(0xFF00FBFF) : Colors.white70
                    ),
                    const PopupMenuDivider(height: 1),
                    _buildPopupItem('recovery', Icons.emergency_rounded, 'RECOVERY_CODES', color: const Color(0xFFFF00FF)),
                    if (item.passwordHistory != null && item.passwordHistory!.isNotEmpty)
                      _buildPopupItem('history', Icons.history_rounded, 'VIEW_HISTORY', color: const Color(0xFF00FF00)),
                    const PopupMenuDivider(height: 1),
                    _buildPopupItem('edit', Icons.edit_note_rounded, 'EDIT_ENTRY'),
                    _buildPopupItem('delete', Icons.delete_forever_rounded, 'DELETE_NODE', color: Colors.redAccent),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String text, {Color? color}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.white70, size: 18),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: color ?? Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
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

  Widget _buildFabPasswords() {
    return FloatingActionButton(
      backgroundColor: const Color(0xFF00FBFF),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white24, width: 1),
      ),
      child: const Icon(Icons.add_rounded, color: Colors.black, size: 28),
      onPressed: () {
        _onUserInteraction();
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.all(color: const Color(0xFF00FBFF).withOpacity(0.2), width: 1),
            ),
            padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    const Text("SYSTEM_ACTIONS", 
                      style: TextStyle(color: Color(0xFF00FBFF), fontSize: 12, letterSpacing: 3, fontFamily: 'monospace')),
                    const Spacer(),
                    Icon(Icons.terminal, color: Colors.white.withOpacity(0.2), size: 16),
                  ],
                ),
                const SizedBox(height: 20),

                _buildActionTile(
                  icon: Icons.vpn_key_rounded,
                  label: "ADD_NEW_PASSWORD",
                  description: "Encrypt and store a new credential",
                  color: const Color(0xFF00FBFF),
                  onTap: () { Navigator.pop(context); _showForm(); },
                ),

                const SizedBox(height: 12),

                _buildActionTile(
                  icon: Icons.qr_code_scanner_rounded,
                  label: "SCAN_QR_2FA",
                  description: "Link a new biometric MFA node",
                  color: const Color(0xFFFF00FF),
                  onTap: () { Navigator.pop(context); _scanQR2FA(); },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTile({
    required IconData icon, 
    required String label, 
    required String description, 
    required Color color, 
    required VoidCallback onTap
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
                  Text(description, 
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart'; 
import '../services/db_helper.dart';
import '../services/encryption_service.dart';
import '../models/password_model.dart';

enum RiskLevel { critical, warning, info }

class AuditResult {
  final int id;
  final String platform;
  final String username;
  final String reason;
  final RiskLevel risk;
  final double entropy;

  AuditResult({
    required this.id,
    required this.platform,
    required this.username,
    required this.reason,
    required this.risk,
    this.entropy = 0.0,
  });

  Map<String, dynamic> toMap() => {
    'reason': reason,
    'risk': risk.index,
    'entropy': entropy,
  };
}

class DashboardScreen extends StatefulWidget {
  final Uint8List masterKey;
  final Function(PasswordModel) onRepairRequested;

  const DashboardScreen({
    super.key,
    required this.masterKey,
    required this.onRepairRequested,
  });

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  String _loadingStatus = "INITIALIZING_SYSTEM...";
  int _totalAccounts = 0;
  int _excludedCount = 0;
  double _healthScore = 100.0;
  double _avgEntropy = 0.0;
  List<AuditResult> _auditReports = [];
  Map<String, int> _categoryRisks = {};
  Set<String> _breachHashSet = {};
  RiskLevel? _selectedFilter;

  int _weakCount = 0, _medCount = 0, _strongCount = 0;

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  Future<void> _initDashboard() async {
    await _loadBreachDictionary();
    await performSecurityAudit();
  }

  Future<void> _loadBreachDictionary() async {
    try {
      setState(() => _loadingStatus = "LOADING_THREAT_DATABASE...");
      final data = await rootBundle.loadString('assets/breach_db.txt');
      _breachHashSet = Set.from(data.split('\n').where((s) => s.isNotEmpty));
    } catch (e) {
      debugPrint("Breach DB not found, skipping local check: $e");
    }
  }
  
  Future<void> performSecurityAudit() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingStatus = "SCANNING_VAULT_NODES...";
    });

    try {
      final rows = await DBHelper.getRawAccounts();
      _totalAccounts = rows.length;
      
      final auditData = {
        'rows': rows,
        'masterKey': widget.masterKey,
        'breachSet': _breachHashSet,
      };

      final results = await compute(_heavyAuditTask, auditData);

      if (mounted) {
        setState(() {
          _auditReports = results['reports'];
          _categoryRisks = results['catRisks'];
          _avgEntropy = results['avgEntropy'];
          _weakCount = results['weak'];
          _medCount = results['med'];
          _strongCount = results['strong'];
          _excludedCount = results['excluded'];
          _healthScore = _calculateHealth();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("AUDIT_ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static Map<String, dynamic> _heavyAuditTask(Map<String, dynamic> data) {
    final List<Map<String, dynamic>> rows = data['rows'];
    final Uint8List masterKey = data['masterKey'];
    final Set<String> breachSet = data['breachSet'];

    List<AuditResult> tempReports = [];
    Map<String, int> tempCategoryRisks = {};
    Map<String, List<Map<String, dynamic>>> passwordGroups = {};
    double totalEntropy = 0;
    int analyzedCount = 0;
    int weak = 0, med = 0, strong = 0, excluded = 0;

    for (var row in rows) {
      if ((row['is_excluded'] as int? ?? 0) == 1) {
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

      if (entropy < 35) weak++;
      else if (entropy < 65) med++;
      else strong++;

      var digest = sha1.convert(utf8.encode(decrypted)).toString();
      if (breachSet.contains(digest.substring(0, 10))) {
        tempReports.add(AuditResult(id: row['id'], platform: row['platform'], username: row['username'] ?? "---", risk: RiskLevel.critical, reason: "ROCKYOU_BREACH_MATCH", entropy: entropy));
      }

      if (_staticHasKeyboardPattern(decrypted)) {
        tempReports.add(AuditResult(id: row['id'], platform: row['platform'], username: row['username'] ?? "---", risk: RiskLevel.warning, reason: "KEYBOARD_PATTERN_DETECTED", entropy: entropy));
      }

      if (entropy < 45) {
        tempReports.add(AuditResult(id: row['id'], platform: row['platform'], username: row['username'] ?? "---", risk: entropy < 30 ? RiskLevel.critical : RiskLevel.warning, reason: entropy < 30 ? "CRITICAL_LOW_ENTROPY" : "WEAK_STRUCTURE", entropy: entropy));
      }

      passwordGroups.putIfAbsent(decrypted, () => []).add(row);
    }

    passwordGroups.forEach((pass, instances) {
      if (instances.length > 1) {
        for (var inst in instances) {
          if ((inst['is_excluded'] as int? ?? 0) == 1) continue;
          tempReports.add(AuditResult(id: inst['id'], platform: inst['platform'], username: inst['username'] ?? "---", risk: RiskLevel.critical, reason: "KEY_REUSE_DETECTED", entropy: _staticCalculateEntropy(pass)));
        }
      }
    });

    return {
      'reports': tempReports,
      'catRisks': tempCategoryRisks,
      'avgEntropy': analyzedCount > 0 ? totalEntropy / analyzedCount : 0.0,
      'weak': weak, 'med': med, 'strong': strong, 'excluded': excluded
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

  double _calculateHealth() {
    int activeNodes = _totalAccounts - _excludedCount;
    if (activeNodes <= 0) return 100.0;
    double penalty = 0;
    for (var report in _auditReports) {
      if (report.risk == RiskLevel.critical) penalty += 20.0;
      else if (report.risk == RiskLevel.warning) penalty += 8.0;
      else penalty += 2.0;
    }
    return (100.0 - (penalty / activeNodes * 4)).clamp(0.0, 100.0);
  }

  Future<void> _toggleExclusion(int id, bool status) async {
    final db = await DBHelper.database;
    await db.update('accounts', {'is_excluded': status ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    performSecurityAudit(); 
  }

  List<AuditResult> get _filteredReports {
    if (_selectedFilter == null) return _auditReports;
    return _auditReports.where((r) => r.risk == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingScreen();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: performSecurityAudit,
        color: const Color(0xFF00FBFF),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildSectionTitle("INTEGRITY_INDEX", Icons.analytics_outlined),
            const SizedBox(height: 15),
            _buildAdvancedGauge(),
            const SizedBox(height: 15),
            _buildSecurityDistribution(),
            const SizedBox(height: 15),
            _buildCyberSummary(),
            const SizedBox(height: 20),
            _buildHealthOverview(),
            
            const SizedBox(height: 25),
            _buildSectionTitle("THREAT_LOG", Icons.security),
            const SizedBox(height: 10),
            _buildFilterChips(),
            const SizedBox(height: 10),
            
            if (_filteredReports.isEmpty) 
              _buildNoThreatsCard()
            else 
              ..._filteredReports.map((report) => _buildDetailedReportCard(report)),

            if (_excludedCount > 0) ...[
              const SizedBox(height: 30),
              _buildSectionTitle("VAULT_EXCLUSIONS", Icons.visibility_off_outlined),
              const SizedBox(height: 10),
              _buildExceptionInfoCard(),
            ],
            
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityDistribution() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("STRENGTH_DISTRIBUTION", style: TextStyle(color: Colors.white24, fontSize: 7, fontFamily: 'monospace')),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bar(_weakCount, Colors.redAccent, "WEAK"),
              _bar(_medCount, Colors.orangeAccent, "MED"),
              _bar(_strongCount, Colors.greenAccent, "STRONG"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(int count, Color color, String label) {
    double maxVal = math.max(_weakCount, math.max(_medCount, _strongCount)).toDouble();
    double height = maxVal == 0 ? 2 : (count / maxVal) * 60;
    
    return Expanded(
      child: Column(
        children: [
          Text(count.toString(), style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace')),
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              border: Border(top: BorderSide(color: color, width: 2))
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white24, fontSize: 6)),
        ],
      ),
    );
  }

  Widget _buildAdvancedGauge() {
    Color statusColor = _healthScore > 80 ? const Color(0xFF00FF41) : (_healthScore > 50 ? Colors.orangeAccent : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [statusColor.withOpacity(0.1), Colors.transparent], begin: Alignment.topLeft),
        color: const Color(0xFF0D0D12), 
        border: Border.all(color: statusColor.withOpacity(0.2))
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${_healthScore.toInt()}%", style: TextStyle(color: statusColor, fontSize: 44, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  Text("OVERALL_INTEGRITY_STATUS", style: TextStyle(color: statusColor.withOpacity(0.5), fontSize: 8, letterSpacing: 1)),
                ],
              ),
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(seconds: 2),
                builder: (context, double value, child) => Opacity(
                  opacity: value,
                  child: Icon(Icons.shield_rounded, color: statusColor.withOpacity(0.2), size: 50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LinearProgressIndicator(value: _healthScore / 100, backgroundColor: Colors.white10, color: statusColor, minHeight: 2),
        ],
      ),
    );
  }

  Widget _buildCyberSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), border: Border.all(color: Colors.white10)),
      child: Column(children: [
          _cyberRow("AVG_ENTROPY_SYSTEM", "${_avgEntropy.toStringAsFixed(1)} bits", _avgEntropy > 50 ? Colors.greenAccent : Colors.orangeAccent),
          _cyberRow("BREACH_DICTIONARY", "ROCKYOU_LOCAL_V1", Colors.blueAccent),
          _cyberRow("ANALYSIS_THREAD", "ISOLATE_COMPUTE_MODE", Colors.purpleAccent),
        ],
      ),
    );
  }

  Widget _cyberRow(String label, String val, Color col) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white12, fontSize: 8, fontFamily: 'monospace')),
          Text(val, style: TextStyle(color: col, fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHealthOverview() {
    int healthyNodes = (_totalAccounts - _excludedCount) - _auditReports.where((r) => r.risk == RiskLevel.critical).length;
    return Row(children: [
        _statusIndicator("SECURE", healthyNodes.toString(), Colors.greenAccent),
        const SizedBox(width: 8),
        _statusIndicator("RISKS", _auditReports.length.toString(), Colors.orangeAccent),
        const SizedBox(width: 8),
        _statusIndicator("TOTAL", (_totalAccounts - _excludedCount).toString(), Colors.white24),
      ],
    );
  }

  Widget _statusIndicator(String label, String val, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: col.withOpacity(0.05), border: Border.all(color: col.withOpacity(0.1))),
        child: Column(children: [
            Text(val, style: TextStyle(color: col, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            Text(label, style: const TextStyle(color: Colors.white24, fontSize: 7, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Wrap(spacing: 8, children: [
        _filterChip("ALL", null, const Color(0xFF00FBFF)),
        _filterChip("CRITICAL", RiskLevel.critical, Colors.redAccent),
        _filterChip("WARNING", RiskLevel.warning, Colors.orangeAccent),
      ],
    );
  }

  Widget _filterChip(String label, RiskLevel? level, Color color) {
    bool isSelected = _selectedFilter == level;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 8, color: isSelected ? Colors.black : color, fontFamily: 'monospace')),
      selected: isSelected,
      onSelected: (val) => setState(() => _selectedFilter = val ? level : null),
      selectedColor: color,
      backgroundColor: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: color.withOpacity(0.3))),
      showCheckmark: false,
    );
  }

  Widget _buildDetailedReportCard(AuditResult report) {
    Color riskColor = report.risk == RiskLevel.critical ? Colors.redAccent : (report.risk == RiskLevel.warning ? Colors.orangeAccent : Colors.blueAccent);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: const Color(0xFF111118), border: Border(left: BorderSide(color: riskColor, width: 2))),
      child: ExpansionTile(
        iconColor: riskColor,
        collapsedIconColor: Colors.white24,
        title: Text(report.platform.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        subtitle: Row(children: [
            Icon(Icons.warning_amber_rounded, size: 10, color: riskColor),
            const SizedBox(width: 5),
            Text(report.reason, style: TextStyle(color: riskColor.withOpacity(0.8), fontSize: 8, fontFamily: 'monospace')),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.black26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow("IDENTIFIER", report.username),
                _detailRow("STRENGTH", "${report.entropy.toStringAsFixed(1)} bits (Entropy)"),
                _detailRow("CRACK_EST", _getBruteForceEstimate(report.entropy)),
                const Divider(color: Colors.white10, height: 20),
                Text("SECURITY_ADVISORY:", style: TextStyle(color: riskColor, fontSize: 8, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(_getMitigation(report.reason), style: const TextStyle(color: Colors.white70, fontSize: 9, height: 1.4)),
                const SizedBox(height: 15),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => _toggleExclusion(report.id, true), child: const Text("IGNORE_NODE", style: TextStyle(color: Colors.white24, fontSize: 9))),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.auto_fix_high, size: 12),
                      style: ElevatedButton.styleFrom(backgroundColor: riskColor.withOpacity(0.1), foregroundColor: riskColor, side: BorderSide(color: riskColor.withOpacity(0.3))),
                      onPressed: () async {
                        final db = await DBHelper.database;
                        final maps = await db.query('accounts', where: 'id = ?', whereArgs: [report.id]);
                        if (maps.isNotEmpty) widget.onRepairRequested(PasswordModel.fromMap(maps.first));
                      }, 
                      label: const Text("REPAIR_KEY", style: TextStyle(fontSize: 9)),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  String _getBruteForceEstimate(double entropy) {
    if (entropy < 28) return "SECONDS (INSTANT)";
    if (entropy < 45) return "MINUTES / HOURS";
    if (entropy < 60) return "DAYS / MONTHS";
    if (entropy < 75) return "YEARS / DECADES";
    return "CENTURIES / UNBREAKABLE";
  }

  String _getMitigation(String reason) {
    if (reason == "ROCKYOU_BREACH_MATCH") return "CRITICAL: This key exists in known leak databases. It will be cracked instantly. Generate a new one immediately.";
    if (reason == "KEY_REUSE_DETECTED") return "SECURITY BREACH: You are using the same key for multiple platforms. A single leak will compromise all accounts.";
    if (reason == "KEYBOARD_PATTERN_DETECTED") return "VULNERABILITY: Predictable keyboard sequence detected. Brute-force tools prioritize these patterns.";
    return "IMPROVEMENT: Key structure is basic. Consider adding special characters and increasing length.";
  }

  Widget _buildLoadingScreen() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const SizedBox(width: 60, child: LinearProgressIndicator(color: Color(0xFF00FBFF), backgroundColor: Colors.white10)),
    const SizedBox(height: 20),
    Text(_loadingStatus, style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 9, fontFamily: 'monospace')),
  ]));

  Widget _buildSectionTitle(String title, IconData icon) => Row(children: [
    Icon(icon, color: const Color(0xFF00FBFF), size: 14),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2)),
    const Expanded(child: Divider(indent: 15, color: Colors.white10)),
  ]);

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Text("$label > ", style: const TextStyle(color: Colors.white24, fontSize: 9, fontFamily: 'monospace')),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'))),
    ]),
  );

  Widget _buildCategoryAuditRow() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _categoryRisks.entries.map((e) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFF0D0D12), border: Border.all(color: Colors.white10)),
    child: Text("${e.key}: ${e.value}", style: const TextStyle(color: Colors.redAccent, fontSize: 8, fontFamily: 'monospace')),
  )).toList()));

  Widget _buildNoThreatsCard() => const Center(child: Padding(padding: EdgeInsets.all(40.0), child: Text("SYSTEM_SECURE: ALL_NODES_OPTIMIZED", style: TextStyle(color: Colors.white10, fontSize: 9, fontFamily: 'monospace'))));

  Widget _buildExceptionInfoCard() {
    return InkWell(
      onTap: _showExclusionsModal,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withOpacity(0.05),
          border: Border.all(color: Colors.blueAccent.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$_excludedCount NODES_IN_OMISSION",
                    style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                  const Text(
                    "Accounts excluded from risk analysis due to user or platform policy.",
                    style: TextStyle(color: Colors.white38, fontSize: 8, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF00FBFF), size: 10),
          ],
        ),
      ),
    );
  }

  void _showExclusionsModal() async {
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> excluded = await db.query('accounts', where: 'is_excluded = 1');
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D12),
      shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.white10)),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildSectionTitle("EXCLUSION_MANAGER", Icons.settings_backup_restore),
            const SizedBox(height: 15),
            Expanded(
              child: excluded.isEmpty 
                ? const Center(child: Text("NO_EXCLUSIONS_FOUND", style: TextStyle(color: Colors.white10, fontSize: 9)))
                : ListView.builder(
                    itemCount: excluded.length,
                    itemBuilder: (context, i) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        border: Border.all(color: Colors.white10)
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          excluded[i]['platform'].toString().toUpperCase(), 
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')
                        ),
                        subtitle: Text(
                          excluded[i]['username'] ?? "ID: ${excluded[i]['id']}", 
                          style: const TextStyle(color: Colors.white38, fontSize: 9)
                        ),
                        trailing: TextButton.icon(
                          onPressed: () {
                            _toggleExclusion(excluded[i]['id'], false);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.add_moderator, size: 14, color: Color(0xFF00FBFF)),
                          label: const Text("RESTORE", style: TextStyle(color: Color(0xFF00FBFF), fontSize: 9)),
                        ),
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

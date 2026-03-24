import 'package:flutter/material.dart';
import 'dart:typed_data';
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

  AuditResult({
    required this.id,
    required this.platform,
    required this.username,
    required this.reason,
    required this.risk,
  });
}

class DashboardScreen extends StatefulWidget {
  final Uint8List masterKey;
  final Function(PasswordModel) onRepairRequested; 

  const DashboardScreen({
    super.key, 
    required this.masterKey, 
    required this.onRepairRequested
  });

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  int _totalAccounts = 0;
  int _excludedCount = 0;
  double _healthScore = 100.0;
  List<AuditResult> _auditReports = [];

  @override
  void initState() {
    super.initState();
    performSecurityAudit();
  }

  Future<void> performSecurityAudit() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final db = await DBHelper.database;
      final List<Map<String, dynamic>> rows = await db.query('accounts');
      
      Map<String, List<Map<String, dynamic>>> passwordGroups = {}; 
      List<AuditResult> tempReports = [];
      _totalAccounts = rows.length;
      _excludedCount = 0;

      for (var row in rows) {
        if ((row['is_excluded'] as int? ?? 0) == 1) {
          _excludedCount++;
          continue; 
        }

        final decrypted = EncryptionService.decrypt(
          combinedText: row['password'] as String,
          masterKeyBytes: widget.masterKey,
        );

        if (decrypted.isEmpty || decrypted.startsWith("ERROR:")) continue;

        bool hasUpper = decrypted.contains(RegExp(r'[A-Z]'));
        bool hasDigits = decrypted.contains(RegExp(r'[0-9]'));
        bool hasSpecial = decrypted.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
        
        if (decrypted.length < 12 || !hasUpper || !hasDigits || !hasSpecial) {
          tempReports.add(AuditResult(
            id: row['id'] as int,
            platform: row['platform']?.toString() ?? "UNKNOWN",
            username: row['username']?.toString() ?? "---",
            risk: decrypted.length < 8 ? RiskLevel.critical : RiskLevel.warning,
            reason: decrypted.length < 8 ? "CRITICAL_LENGTH" : (decrypted.length < 12 ? "WEAK_STRUCTURE" : "LOW_ENTROPY"),
          ));
        }
        passwordGroups.putIfAbsent(decrypted, () => []).add(row);
      }

      passwordGroups.forEach((pass, instances) {
        if (instances.length > 1) {
          for (var inst in instances) {
            if ((inst['is_excluded'] as int? ?? 0) == 1) continue;
            tempReports.add(AuditResult(
              id: inst['id'],
              platform: inst['platform'],
              username: inst['username'] ?? "---",
              risk: RiskLevel.critical,
              reason: "KEY_REUSE",
            ));
          }
        }
      });

      setState(() {
        _auditReports = tempReports;
        _healthScore = _calculateHealth();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _calculateHealth() {
    int activeNodes = _totalAccounts - _excludedCount;
    if (activeNodes <= 0) return 100.0;
    double penalty = 0;
    for (var report in _auditReports) {
      penalty += (report.risk == RiskLevel.critical) ? 12.0 : 5.0;
    }
    double score = 100.0 - (penalty / activeNodes * 5);
    return score.clamp(0.0, 100.0);
  }

  Future<void> _toggleExclusion(int id, bool status) async {
    final db = await DBHelper.database;
    await db.update('accounts', {'is_excluded': status ? 1 : 0}, 
      where: 'id = ?', whereArgs: [id]);
    performSecurityAudit(); 
  }

  void _showExclusionsModal() async {
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> excluded = await db.query('accounts', where: 'is_excluded = 1');

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D12),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildSectionTitle("EXCLUSION_VAULT", Icons.visibility_off),
            const SizedBox(height: 15),
            Expanded(
              child: excluded.isEmpty 
                ? const Center(child: Text("NO_ACTIVE_EXCEPTIONS", style: TextStyle(color: Colors.white10, fontSize: 10, fontFamily: 'monospace')))
                : ListView.builder(
                    itemCount: excluded.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(excluded[i]['platform'].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                      subtitle: Text(excluded[i]['username'] ?? "---", style: const TextStyle(color: Colors.white38, fontSize: 9)),
                      trailing: IconButton(
                        icon: const Icon(Icons.settings_backup_restore, color: Color(0xFF00FBFF), size: 18),
                        onPressed: () {
                          _toggleExclusion(excluded[i]['id'], false);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF00FBFF), strokeWidth: 1));

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
            const SizedBox(height: 30),
            
            _buildSectionTitle("THREAT_LOG", Icons.security),
            const SizedBox(height: 10),
            if (_auditReports.isEmpty) _buildNoThreatsCard()
            else ..._auditReports.map((report) => _buildDetailedReportCard(report)),
            
            if (_excludedCount > 0) ...[
              const SizedBox(height: 30),
              _buildSectionTitle("ACTIVE_EXCEPTIONS", Icons.do_not_disturb_on_total_silence),
              const SizedBox(height: 10),
              _buildExceptionInfoCard(),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedGauge() {
    Color statusColor = _healthScore > 80 ? const Color(0xFF00FF41) : (_healthScore > 50 ? Colors.orangeAccent : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF0D0D12), border: Border.all(color: statusColor.withOpacity(0.1))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${_healthScore.toInt()}%", style: TextStyle(color: statusColor, fontSize: 48, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  Text("INTEGRITY_INDEX", style: TextStyle(color: statusColor.withOpacity(0.5), fontSize: 8)),
                ],
              ),
              _infoPoint("MONITORED", "${_totalAccounts - _excludedCount}", Colors.white70),
            ],
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(value: _healthScore / 100, backgroundColor: Colors.white10, color: statusColor, minHeight: 4),
        ],
      ),
    );
  }

  Widget _buildDetailedReportCard(AuditResult report) {
    Color riskColor = report.risk == RiskLevel.critical ? Colors.redAccent : Colors.orangeAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: const Color(0xFF111118), border: Border(left: BorderSide(color: riskColor, width: 2))),
      child: ExpansionTile(
        iconColor: riskColor,
        collapsedIconColor: Colors.white24,
        leading: Icon(Icons.gpp_maybe_outlined, color: riskColor, size: 20),
        title: Text(report.platform.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        subtitle: Text(report.reason, style: TextStyle(color: riskColor.withOpacity(0.8), fontSize: 9, fontFamily: 'monospace')),
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.black26,
            child: Column(
              children: [
                _detailRow("IDENTIFIER", report.username),
                _detailRow("MITIGATION", _getMitigation(report.reason)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _toggleExclusion(report.id, true),
                      icon: const Icon(Icons.visibility_off_outlined, size: 14, color: Colors.blueAccent),
                      label: const Text("IGNORE", style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontFamily: 'monospace')),
                    ),
                    const SizedBox(width: 15),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: riskColor.withOpacity(0.1), side: BorderSide(color: riskColor.withOpacity(0.3))),
                      onPressed: () async {
                        final db = await DBHelper.database;
                        final maps = await db.query('accounts', where: 'id = ?', whereArgs: [report.id]);
                        if (maps.isNotEmpty) {
                          final model = PasswordModel.fromMap(maps.first);
                          widget.onRepairRequested(model);
                          Future.delayed(const Duration(seconds: 1), () => performSecurityAudit());
                        }
                      }, 
                      child: Text("REPAIR", style: TextStyle(fontSize: 10, color: riskColor, fontWeight: FontWeight.bold)),
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

  Widget _buildExceptionInfoCard() {
    return InkWell(
      onTap: _showExclusionsModal,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.05), border: Border.all(color: Colors.blueAccent.withOpacity(0.1))),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
            SizedBox(width: 12),
            Expanded(
              child: Text("Manual exceptions active. System health calculation reflects partial coverage.", 
                style: TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace')),
            ),
            Icon(Icons.arrow_forward_ios, color: Color(0xFF00FBFF), size: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00FBFF), size: 16),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2)),
        const Expanded(child: Divider(indent: 15, color: Colors.white10)),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text("$label > ", style: const TextStyle(color: Colors.white24, fontSize: 9, fontFamily: 'monospace')),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  String _getMitigation(String reason) {
    if (reason == "KEY_REUSE") return "Collision detected. Rotate to unique key.";
    if (reason == "CRITICAL_LENGTH") return "Extreme vulnerability. Increase size.";
    return "Diversity check failed. Inject symbols/numbers.";
  }

  Widget _infoPoint(String label, String val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8, fontFamily: 'monospace')),
        Text(val, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildNoThreatsCard() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40.0),
        child: Text("CORE_STABLE: NO_VULNERABILITIES", style: TextStyle(color: Colors.white10, fontSize: 10, fontFamily: 'monospace')),
      ),
    );
  }
}

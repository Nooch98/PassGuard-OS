/*
|--------------------------------------------------------------------------
| PassGuard OS - PasswordGeneratorDialog
|--------------------------------------------------------------------------
| Description:
|   Cyberpunk-style dialog that provides PassGuard OS "Generator Pro".
|   Generates high-entropy credentials in multiple modes:
|     - Random passwords (configurable charset + rules)
|     - Diceware passphrases (offline wordlist)
|     - PIN codes (pattern-based numeric generation)
|
| Responsibilities:
|   - Render generator UI with mode selection (Password / Passphrase / PIN)
|   - Collect generation settings (length, charset, ambiguity rules, etc.)
|   - Invoke PasswordGeneratorPro with GeneratorOptions
|   - Load the default offline wordlist via WordlistService (Diceware)
|   - Display entropy estimation (bits) and visual strength indicator
|   - Provide user actions: refresh + copy + use generated value
|
| Data & Performance Notes:
|   - Wordlist is loaded from local assets (offline) once per dialog session
|   - Generation is deterministic only per RNG seed; defaults use secure randomness
|   - UI updates are lightweight and triggered on setting changes
|
| Security Notes:
|   - Generated secrets are created locally (100% offline)
|   - No network calls, analytics, or telemetry
|   - Clipboard copy is explicit and user-triggered
|   - Entropy is an estimate (best-effort), not a formal security proof
|
| UI Design:
|   - Neon cyberpunk theme with segmented modes and monospace output
|   - Compact layout designed for mobile and desktop
|
|--------------------------------------------------------------------------
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/password_generator_service.dart';
import '../services/wordlist_service.dart';

class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({super.key});

  @override
  State<PasswordGeneratorDialog> createState() => _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  int _selectedMode = 0;
  
  int _passwordLength = 20;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  bool _excludeAmbiguous = true;
  bool _enforceAllSets = true;

  int _wordCount = 5;
  String _wordSeparator = '-';
  bool _diceCapitalize = true;
  bool _diceAddNumber = true;
  bool _diceAddSymbol = false;
  bool _useSmartLeet = true;

  int _pinLength = 6;

  late final PasswordGeneratorPro _gen;
  GeneratedPassword? _currentResult;

  @override
  void initState() {
    super.initState();
    _gen = PasswordGeneratorPro();
    _initWordlist();
  }

  Future<void> _initWordlist() async {
    final words = await WordlistService.loadDefault();
    PasswordGeneratorPro.setWordlist(words);
    _generatePassword();
  }

  void _generatePassword() {
    try {
      GeneratorOptions opt;
      switch (_selectedMode) {
        case 0:
          opt = GeneratorOptions(
            mode: GeneratorMode.random,
            length: _passwordLength,
            upper: _includeUppercase,
            lower: _includeLowercase,
            digits: _includeNumbers,
            symbols: _includeSymbols,
            avoidAmbiguous: _excludeAmbiguous,
            enforceAllSets: _enforceAllSets,
          );
          break;
        case 1:
          opt = GeneratorOptions(
            mode: GeneratorMode.diceware,
            words: _wordCount,
            wordSeparator: _wordSeparator,
            dicewareCapitalize: _diceCapitalize,
            dicewareAddNumber: _diceAddNumber,
            dicewareAddSymbol: _diceAddSymbol,
            useSmartLeet: _useSmartLeet,
          );
          break;
        case 2:
          opt = GeneratorOptions(
            mode: GeneratorMode.pattern,
            pattern: List.filled(_pinLength, '9').join(),
            digits: true,
            avoidAmbiguous: false,
          );
          break;
        default:
          opt = const GeneratorOptions(mode: GeneratorMode.random);
      }
      final res = _gen.generate(opt);
      setState(() => _currentResult = res);
    } catch (e) {
      debugPrint("Generation Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _currentResult;
    final themeColor = _getStrengthColor(res?.strength);

    return Dialog(
      backgroundColor: const Color(0xFF0D0D12),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: themeColor.withOpacity(0.5), width: 1),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(themeColor),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeSelector(),
                    const SizedBox(height: 20),
                    _buildOutputDisplay(res, themeColor),
                    const SizedBox(height: 25),
                    const Text("CONFIGURATION_PARAMETERS", 
                      style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2, fontFamily: 'monospace')),
                    const SizedBox(height: 15),
                    _buildSettings(),
                  ],
                ),
              ),
            ),
            _buildActionButtons(res, themeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(Icons.hub_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PASS_GEN_PRO_V3', 
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'monospace')),
              const Text('HIGH_ENTROPY_GENERATOR', style: TextStyle(color: Colors.white24, fontSize: 9)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('OFFLINE', style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('RANDOM'), icon: Icon(Icons.shuffle, size: 14)),
          ButtonSegment(value: 1, label: Text('PHRASE'), icon: Icon(Icons.menu_book, size: 14)),
          ButtonSegment(value: 2, label: Text('PIN'), icon: Icon(Icons.dialpad, size: 14)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (Set<int> selected) {
          setState(() => _selectedMode = selected.first);
          _generatePassword();
        },
        style: _segmentedButtonStyle(),
      ),
    );
  }

  Widget _buildOutputDisplay(GeneratedPassword? res, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  res?.value ?? 'INITIATING...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: color),
                onPressed: _generatePassword,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(4, (index) {
              bool active = (res?.entropyBits ?? 0) > (index * 32);
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: active ? color : Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat("${res?.entropyBits.toInt() ?? 0} bits", "ENTROPY", color),
              _buildStat(res?.crackTime.toUpperCase() ?? "N/A", "CRACK_TIME", color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String val, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8)),
        Text(val, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildSettings() {
    switch (_selectedMode) {
      case 0: return _buildRandomPanel();
      case 1: return _buildPhrasePanel();
      case 2: return _buildPinPanel();
      default: return const SizedBox();
    }
  }

  Widget _buildRandomPanel() {
    return Column(
      children: [
        _buildSliderSetting("CHAR_LENGTH", _passwordLength, 8, 64, (v) => setState(() => _passwordLength = v.toInt())),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 3.5,
          children: [
            _buildToggle("A-Z", _includeUppercase, (v) => setState(() => _includeUppercase = v!)),
            _buildToggle("a-z", _includeLowercase, (v) => setState(() => _includeLowercase = v!)),
            _buildToggle("0-9", _includeNumbers, (v) => setState(() => _includeNumbers = v!)),
            _buildToggle("!@#", _includeSymbols, (v) => setState(() => _includeSymbols = v!)),
          ],
        ),
        _buildToggle("AVOID_AMBIGUOUS", _excludeAmbiguous, (v) => setState(() => _excludeAmbiguous = v!)),
      ],
    );
  }

  Widget _buildPhrasePanel() {
    return Column(
      children: [
        _buildSliderSetting("WORD_COUNT", _wordCount, 3, 10, (v) => setState(() => _wordCount = v.toInt())),
        const SizedBox(height: 10),
        _buildToggle("CAPITALIZE", _diceCapitalize, (v) => setState(() => _diceCapitalize = v!)),
        _buildToggle("SMART_LEET", _useSmartLeet, (v) => setState(() => _useSmartLeet = v!)),
        _buildToggle("ADD_NUMBER", _diceAddNumber, (v) => setState(() => _diceAddNumber = v!)),
      ],
    );
  }

  Widget _buildPinPanel() {
    return Column(
      children: [
        _buildSliderSetting("PIN_LENGTH", _pinLength, 4, 16, (v) => setState(() => _pinLength = v.toInt())),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
              SizedBox(width: 10),
              Expanded(child: Text("Numeric PINs have lower entropy than alphanumeric strings.", style: TextStyle(color: Colors.orange, fontSize: 10))),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildSliderSetting(String label, int val, double min, double max, Function(double) onChg) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
            Text(val.toString(), style: const TextStyle(color: Color(0xFF00FBFF), fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: val.toDouble(),
          min: min, max: max,
          divisions: (max - min).toInt(),
          activeColor: const Color(0xFF00FBFF),
          onChanged: (v) { onChg(v); _generatePassword(); },
        ),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool?) onChg) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
      value: value,
      onChanged: (v) { onChg(v); _generatePassword(); },
      activeColor: const Color(0xFF00FBFF),
      checkColor: Colors.black,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildActionButtons(GeneratedPassword? res, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white))),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ABORT', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: res == null ? null : () => Navigator.pop(context, res.value),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('USE_GENERATED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStrengthColor(StrengthLevel? strength) {
    switch (strength) {
      case StrengthLevel.weak: return Colors.redAccent;
      case StrengthLevel.fair: return Colors.orangeAccent;
      case StrengthLevel.good: return Colors.yellowAccent;
      case StrengthLevel.strong: return const Color(0xFF00FBFF);
      case StrengthLevel.overkill: return const Color(0xFF00FF00);
      default: return const Color(0xFF00FBFF);
    }
  }

  ButtonStyle _segmentedButtonStyle() {
    return ButtonStyle(
      textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? const Color(0xFF00FBFF) : Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.black : Colors.white38),
    );
  }
}

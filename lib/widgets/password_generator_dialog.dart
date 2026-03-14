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
      backgroundColor: const Color(0xFF0A0A0E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: themeColor, width: 1.5),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(themeColor),
            const SizedBox(height: 20),
            _buildModeSelector(),
            const SizedBox(height: 24),
            _buildOutputDisplay(res, themeColor),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(child: _buildSettings()),
            ),
            const SizedBox(height: 20),
            _buildActionButtons(res),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '> PASS_GEN_PRO_V3',
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            'OFFLINE_SECURE',
            style: TextStyle(color: color, fontSize: 8),
          ),
        )
      ],
    );
  }

  Widget _buildModeSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('RANDOM', style: TextStyle(fontSize: 10))),
          ButtonSegment(value: 1, label: Text('DICWARE', style: TextStyle(fontSize: 10))),
          ButtonSegment(value: 2, label: Text('PIN_CODE', style: TextStyle(fontSize: 10))),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  res?.value ?? 'LOADING...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: color, size: 20),
                onPressed: _generatePassword,
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Color(0xFFFF00FF), size: 20),
                onPressed: () {
                  if (res == null) return;
                  Clipboard.setData(ClipboardData(text: res.value));
                  _showToast(context, 'HASH_COPIED_TO_BUFFER');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: ((res?.entropyBits ?? 0) / 128).clamp(0, 1),
            backgroundColor: Colors.white10,
            color: color,
            minHeight: 4,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ENTROPY: ${res?.entropyBits.toStringAsFixed(1) ?? "0"} BITS',
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              Text(
                'CRACK_TIME: ${res?.crackTime.toUpperCase() ?? "N/A"}',
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    switch (_selectedMode) {
      case 0: return _buildPasswordSettings();
      case 1: return _buildPassphraseSettings();
      case 2: return _buildPinSettings();
      default: return const SizedBox();
    }
  }

  Widget _buildPasswordSettings() {
    return Column(
      children: [
        _buildSlider('LENGTH', _passwordLength, 8, 64, (v) => setState(() => _passwordLength = v.toInt())),
        _buildCheckbox('UPPERCASE (A-Z)', _includeUppercase, (v) => setState(() => _includeUppercase = v!)),
        _buildCheckbox('LOWERCASE (a-z)', _includeLowercase, (v) => setState(() => _includeLowercase = v!)),
        _buildCheckbox('NUMBERS (0-9)', _includeNumbers, (v) => setState(() => _includeNumbers = v!)),
        _buildCheckbox('SYMBOLS (!@#...)', _includeSymbols, (v) => setState(() => _includeSymbols = v!)),
        _buildCheckbox('AVOID AMBIGUOUS (Il1O0)', _excludeAmbiguous, (v) => setState(() => _excludeAmbiguous = v!)),
        _buildCheckbox('STRICT MODE (MIN 1 EACH)', _enforceAllSets, (v) => setState(() => _enforceAllSets = v!)),
      ],
    );
  }

  Widget _buildPassphraseSettings() {
    return Column(
      children: [
        _buildSlider('WORDS', _wordCount, 3, 10, (v) => setState(() => _wordCount = v.toInt())),
        _buildCheckbox('CAPITALIZE WORD', _diceCapitalize, (v) => setState(() => _diceCapitalize = v!)),
        _buildCheckbox('SMART LEETSPEAK (4=A, 3=E)', _useSmartLeet, (v) => setState(() => _useSmartLeet = v!)),
        _buildCheckbox('APPEND NUMBER', _diceAddNumber, (v) => setState(() => _diceAddNumber = v!)),
        _buildCheckbox('APPEND SYMBOL', _diceAddSymbol, (v) => setState(() => _diceAddSymbol = v!)),
      ],
    );
  }

  Widget _buildPinSettings() {
    return Column(
      children: [
        _buildSlider('PIN DIGITS', _pinLength, 4, 16, (v) => setState(() => _pinLength = v.toInt())),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'High-speed numeric generation. Entropy is lower but memorability is higher for device unlocks.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        )
      ],
    );
  }

  Widget _buildSlider(String label, int val, double min, double max, Function(double) onChg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $val', style: const TextStyle(color: Colors.white70, fontSize: 10)),
        Slider(
          value: val.toDouble(),
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          activeColor: const Color(0xFF00FBFF),
          onChanged: (v) { onChg(v); _generatePassword(); },
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, Function(bool?) onChg) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      value: value,
      onChanged: (v) { onChg(v); _generatePassword(); },
      activeColor: const Color(0xFF00FBFF),
      checkColor: Colors.black,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildActionButtons(GeneratedPassword? res) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
            child: const Text('ABORT', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: res == null ? null : () => Navigator.pop(context, res.value),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getStrengthColor(res?.strength),
              foregroundColor: Colors.black,
            ),
            child: const Text('INJECT_CREDENTIAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
      ],
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
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? const Color(0xFF00FBFF) : Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.black : Colors.white70),
      side: WidgetStateProperty.all(const BorderSide(color: Colors.white10)),
    );
  }

  void _showToast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating),
    );
  }
}

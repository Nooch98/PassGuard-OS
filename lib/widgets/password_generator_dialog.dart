/*
|--------------------------------------------------------------------------
| PassGuard OS - PasswordGeneratorDialog
|--------------------------------------------------------------------------
| Description:
|   Cyberpunk-style dialog for PassGuard OS "Generator Pro".
|   Generates local credentials in multiple modes:
|     - Random passwords
|     - Diceware-style passphrases
|     - Numeric PINs
|     - High-entropy mode (legacy "quantum" label in generator core)
|
| Security Notes:
|   - Generated secrets are created locally (offline)
|   - No network calls, analytics, or telemetry
|   - Clipboard copy is explicit and user-triggered
|   - Entropy is an estimate, not a formal proof
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
  int _highEntropyLength = 28;

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
        case 3:
          opt = GeneratorOptions(
            mode: GeneratorMode.quantum,
            length: _highEntropyLength,
            avoidAmbiguous: _excludeAmbiguous,
          );
          break;
        default:
          opt = const GeneratorOptions(mode: GeneratorMode.random);
      }

      final res = _gen.generate(opt);
      setState(() => _currentResult = res);
    } catch (e) {
      debugPrint("Generation Error: $e");
      setState(() => _currentResult = null);
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
                    _buildModeSelector(themeColor),
                    const SizedBox(height: 20),
                    _buildOutputDisplay(res, themeColor),
                    const SizedBox(height: 25),
                    const Text(
                      "CONFIGURATION_PARAMETERS",
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 9,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildSettings(themeColor),
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
    final bool isHighEntropyMode = _selectedMode == 3;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            isHighEntropyMode ? Icons.bolt_rounded : Icons.hub_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isHighEntropyMode ? 'HIGH_ENTROPY_MODE' : 'PASS_GEN_PRO_V3',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                isHighEntropyMode
                    ? 'GROVER-AWARE RANDOM GENERATION'
                    : 'LOCAL OFFLINE GENERATOR',
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'OFFLINE',
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildModeSelector(Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(
            value: 0,
            label: Text('RAND'),
            icon: Icon(Icons.shuffle, size: 14),
          ),
          ButtonSegment(
            value: 1,
            label: Text('PHRSE'),
            icon: Icon(Icons.menu_book, size: 14),
          ),
          ButtonSegment(
            value: 2,
            label: Text('PIN'),
            icon: Icon(Icons.dialpad, size: 14),
          ),
          ButtonSegment(
            value: 3,
            label: Text('H-ENT'),
            icon: Icon(Icons.bolt, size: 14),
          ),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (Set<int> selected) {
          setState(() => _selectedMode = selected.first);
          _generatePassword();
        },
        style: _segmentedButtonStyle(color),
      ),
    );
  }

  Widget _buildOutputDisplay(GeneratedPassword? res, Color color) {
    final bool isHighEntropyMode = _selectedMode == 3;
    final double groverAdjusted =
        ((res?.meta['groverAdjustedBits'] as num?)?.toDouble()) ??
        ((res?.entropyBits ?? 0) / 2.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: isHighEntropyMode
            ? [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
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
                    fontSize: 20,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
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
            children: List.generate(5, (index) {
              final bool active = (res?.entropyBits ?? 0) > (index * 32);
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
              _buildStat(
                "${res?.entropyBits.toInt() ?? 0} bits",
                "ENTROPY_EST",
                color,
              ),
              _buildStat(
                res?.crackTime.toUpperCase() ?? "N/A",
                "OFFLINE_EST",
                color,
              ),
              if (isHighEntropyMode)
                _buildStat(
                  "${groverAdjusted.toStringAsFixed(0)} bits",
                  "GROVER_MARGIN",
                  color,
                ),
            ],
          ),
          if (isHighEntropyMode) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                "This mode generates a very high-entropy random password. "
                "It is NOT post-quantum cryptography; the extra metric is only a Grover-adjusted estimate.",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(String val, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white24, fontSize: 8)),
        Text(
          val,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(Color color) {
    switch (_selectedMode) {
      case 0:
        return _buildRandomPanel(color);
      case 1:
        return _buildPhrasePanel(color);
      case 2:
        return _buildPinPanel(color);
      case 3:
        return _buildHighEntropyPanel(color);
      default:
        return const SizedBox();
    }
  }

  Widget _buildRandomPanel(Color color) {
    return Column(
      children: [
        _buildSliderSetting(
          "CHAR_LENGTH",
          _passwordLength,
          8,
          64,
          color,
          (v) => setState(() => _passwordLength = v.toInt()),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 3.5,
          children: [
            _buildToggle("A-Z", _includeUppercase, color, (v) => setState(() => _includeUppercase = v!)),
            _buildToggle("a-z", _includeLowercase, color, (v) => setState(() => _includeLowercase = v!)),
            _buildToggle("0-9", _includeNumbers, color, (v) => setState(() => _includeNumbers = v!)),
            _buildToggle("!@#", _includeSymbols, color, (v) => setState(() => _includeSymbols = v!)),
          ],
        ),
        _buildToggle("AVOID_AMBIGUOUS", _excludeAmbiguous, color, (v) => setState(() => _excludeAmbiguous = v!)),
        _buildToggle("ENFORCE_ALL_SETS", _enforceAllSets, color, (v) => setState(() => _enforceAllSets = v!)),
      ],
    );
  }

  Widget _buildPhrasePanel(Color color) {
    return Column(
      children: [
        _buildSliderSetting(
          "WORD_COUNT",
          _wordCount,
          4,
          10,
          color,
          (v) => setState(() => _wordCount = v.toInt()),
        ),
        const SizedBox(height: 10),
        _buildToggle("CAPITALIZE", _diceCapitalize, color, (v) => setState(() => _diceCapitalize = v!)),
        _buildToggle("SMART_LEET", _useSmartLeet, color, (v) => setState(() => _useSmartLeet = v!)),
        _buildToggle("ADD_NUMBER", _diceAddNumber, color, (v) => setState(() => _diceAddNumber = v!)),
        _buildToggle("ADD_SYMBOL", _diceAddSymbol, color, (v) => setState(() => _diceAddSymbol = v!)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Passphrases are easier to remember. Strength depends heavily on wordlist size and word count.",
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildPinPanel(Color color) {
    return Column(
      children: [
        _buildSliderSetting(
          "PIN_LENGTH",
          _pinLength,
          4,
          16,
          color,
          (v) => setState(() => _pinLength = v.toInt()),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Numeric PINs have much lower entropy than random alphanumeric passwords.",
                  style: TextStyle(color: Colors.orange, fontSize: 10),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildHighEntropyPanel(Color color) {
    return Column(
      children: [
        _buildSliderSetting(
          "TARGET_LENGTH",
          _highEntropyLength,
          20,
          64,
          color,
          (v) => setState(() => _highEntropyLength = v.toInt()),
        ),
        const SizedBox(height: 15),
        _buildToggle(
          "AVOID_AMBIGUOUS",
          _excludeAmbiguous,
          color,
          (v) => setState(() => _excludeAmbiguous = v!),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt, color: color, size: 16),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "High-Entropy mode forces uppercase, lowercase, digits, and symbols to maximize random search space. "
                  "The Grover margin shown is a heuristic estimate, not a post-quantum guarantee.",
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildSliderSetting(
    String label,
    int val,
    double min,
    double max,
    Color color,
    Function(double) onChg,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              val.toString(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: val.toDouble(),
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          activeColor: color,
          onChanged: (v) {
            onChg(v);
            _generatePassword();
          },
        ),
      ],
    );
  }

  Widget _buildToggle(
    String label,
    bool value,
    Color color,
    Function(bool?) onChg,
  ) {
    return CheckboxListTile(
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
      value: value,
      onChanged: (v) {
        onChg(v);
        _generatePassword();
      },
      activeColor: color,
      checkColor: Colors.black,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildActionButtons(GeneratedPassword? res, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ABORT',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
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
                elevation: _selectedMode == 3 ? 6 : 0,
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text(
                'USE_GENERATED',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStrengthColor(StrengthLevel? strength) {
    switch (strength) {
      case StrengthLevel.weak:
        return Colors.redAccent;
      case StrengthLevel.fair:
        return Colors.orangeAccent;
      case StrengthLevel.good:
        return Colors.yellowAccent;
      case StrengthLevel.strong:
        return const Color(0xFF00FBFF);
      case StrengthLevel.overkill:
        return const Color(0xFF00FF00);
      case StrengthLevel.ultra:
        return const Color(0xFFD000FF);
      default:
        return const Color(0xFF00FBFF);
    }
  }

  ButtonStyle _segmentedButtonStyle(Color themeColor) {
    return ButtonStyle(
      textStyle: WidgetStateProperty.all(
        const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? themeColor
            : Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.black
            : Colors.white38;
      }),
    );
  }
}

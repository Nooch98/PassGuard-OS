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

  int _passwordLength = 16;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  bool _excludeAmbiguous = false;
  bool _enforceAllSets = true;

  int _wordCount = 4;
  String _wordSeparator = '-';
  bool _diceCapitalize = false;
  bool _diceAddNumber = true;
  bool _diceAddSymbol = false;

  int _pinLength = 6;

  late final PasswordGeneratorPro _gen;
  String _generatedPassword = '';
  double _entropyBits = 0;

  @override
  void initState() {
    super.initState();
    _gen = PasswordGeneratorPro();
    _generatePassword();
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
          );
          break;

        case 2:
          opt = GeneratorOptions(
            mode: GeneratorMode.pattern,
            pattern: List.filled(_pinLength, '9').join(),
            digits: true,
            upper: false,
            lower: false,
            symbols: false,
            avoidAmbiguous: false,
          );
          break;

        default:
          opt = const GeneratorOptions(mode: GeneratorMode.random);
      }

      final res = _gen.generate(opt);

      setState(() {
        _generatedPassword = res.value;
        _entropyBits = res.entropyBits;
      });
    } catch (e) {
      setState(() {
        _generatedPassword = 'GEN_ERROR';
        _entropyBits = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF00FBFF), width: 2),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '> PASSWORD_GENERATOR',
              style: TextStyle(
                color: Color(0xFF00FBFF),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 20),

            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('PASSWORD', style: TextStyle(fontSize: 10))),
                ButtonSegment(value: 1, label: Text('PASSPHRASE', style: TextStyle(fontSize: 10))),
                ButtonSegment(value: 2, label: Text('PIN', style: TextStyle(fontSize: 10))),
              ],
              selected: {_selectedMode},
              onSelectionChanged: (Set<int> selected) {
                setState(() {
                  _selectedMode = selected.first;
                });
                _generatePassword();
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const Color(0xFF00FBFF);
                  }
                  return Colors.transparent;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.black;
                  }
                  return Colors.white;
                }),
              ),
            ),

            const SizedBox(height: 30),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _getEntropyColor(), width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: SelectableText(
                          _generatedPassword,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, color: Color(0xFFFF00FF), size: 20),
                            onPressed: _generatedPassword.isEmpty || _generatedPassword == 'GEN_ERROR'
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: _generatedPassword));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('COPIED_TO_CLIPBOARD'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Color(0xFF00FBFF), size: 20),
                            onPressed: _generatePassword,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  LinearProgressIndicator(
                    value: (_entropyBits / 120).clamp(0, 1),
                    backgroundColor: Colors.white10,
                    color: _getEntropyColor(),
                    minHeight: 6,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'ENTROPY: ${_entropyBits.toStringAsFixed(1)} bits • ${_entropyLabel(_entropyBits)}',
                    style: TextStyle(
                      color: _getEntropyColor(),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            Expanded(
              child: SingleChildScrollView(
                child: _buildSettings(),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FBFF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _generatedPassword.isEmpty || _generatedPassword == 'GEN_ERROR'
                      ? null
                      : () => Navigator.pop(context, _generatedPassword),
                  child: const Text(
                    'USE_THIS_PASSWORD',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    switch (_selectedMode) {
      case 0:
        return _buildPasswordSettings();
      case 1:
        return _buildPassphraseSettings();
      case 2:
        return _buildPinSettings();
      default:
        return const SizedBox();
    }
  }

  Widget _buildPasswordSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LENGTH: $_passwordLength',
          style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 12),
        ),
        Slider(
          value: _passwordLength.toDouble(),
          min: 8,
          max: 64,
          divisions: 56,
          activeColor: const Color(0xFF00FBFF),
          inactiveColor: Colors.white24,
          onChanged: (value) {
            setState(() => _passwordLength = value.toInt());
            _generatePassword();
          },
        ),
        const SizedBox(height: 15),
        _buildCheckbox('UPPERCASE (A-Z)', _includeUppercase, (val) {
          setState(() => _includeUppercase = val ?? false);
          _generatePassword();
        }),
        _buildCheckbox('LOWERCASE (a-z)', _includeLowercase, (val) {
          setState(() => _includeLowercase = val ?? false);
          _generatePassword();
        }),
        _buildCheckbox('NUMBERS (0-9)', _includeNumbers, (val) {
          setState(() => _includeNumbers = val ?? false);
          _generatePassword();
        }),
        _buildCheckbox('SYMBOLS (!@#\$...)', _includeSymbols, (val) {
          setState(() => _includeSymbols = val ?? false);
          _generatePassword();
        }),
        _buildCheckbox('EXCLUDE AMBIGUOUS (Il1O0)', _excludeAmbiguous, (val) {
          setState(() => _excludeAmbiguous = val ?? false);
          _generatePassword();
        }),
        _buildCheckbox('ENFORCE ALL SETS (min 1 each)', _enforceAllSets, (val) {
          setState(() => _enforceAllSets = val ?? false);
          _generatePassword();
        }),
      ],
    );
  }

  Widget _buildPassphraseSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WORD COUNT: $_wordCount',
          style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 12),
        ),
        Slider(
          value: _wordCount.toDouble(),
          min: 3,
          max: 8,
          divisions: 5,
          activeColor: const Color(0xFF00FBFF),
          inactiveColor: Colors.white24,
          onChanged: (value) {
            setState(() => _wordCount = value.toInt());
            _generatePassword();
          },
        ),
        const SizedBox(height: 10),
        _buildTextField(
          label: 'SEPARATOR',
          value: _wordSeparator,
          onChanged: (v) {
            setState(() => _wordSeparator = v.isEmpty ? '-' : v.substring(0, 1));
            _generatePassword();
          },
          hint: '-',
          maxLen: 1,
        ),
        const SizedBox(height: 10),
        _buildCheckbox('CAPITALIZE 1 WORD', _diceCapitalize, (val) {
          setState(() => _diceCapitalize = val ?? false);
          _generatePassword();
        }),
        _buildCheckbox('ADD NUMBER', _diceAddNumber, (val) {
          setState(() => _diceAddNumber = val ?? false);
          _generatePassword();
        }),
        _buildCheckbox('ADD SYMBOL', _diceAddSymbol, (val) {
          setState(() => _diceAddSymbol = val ?? false);
          _generatePassword();
        }),
        const SizedBox(height: 10),
        const Text(
          'Memorable password made of random words\nExample: casa-luna-raton-foco7!',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildPinSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PIN LENGTH: $_pinLength',
          style: const TextStyle(color: Color(0xFF00FBFF), fontSize: 12),
        ),
        Slider(
          value: _pinLength.toDouble(),
          min: 4,
          max: 12,
          divisions: 8,
          activeColor: const Color(0xFF00FBFF),
          inactiveColor: Colors.white24,
          onChanged: (value) {
            setState(() => _pinLength = value.toInt());
            _generatePassword();
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'Numeric PIN code (pattern-based)',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, Function(bool?) onChanged) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      value: value,
      activeColor: const Color(0xFF00FBFF),
      checkColor: Colors.black,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? hint,
    int? maxLen,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 6),
        TextField(
          controller: TextEditingController(text: value),
          onChanged: onChanged,
          maxLength: maxLen,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF16161D),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Color(0xFF00FBFF)),
            ),
          ),
        ),
      ],
    );
  }

  Color _getEntropyColor() {
    if (_entropyBits >= 100) return const Color(0xFF00FF00);
    if (_entropyBits >= 80) return const Color(0xFF00FBFF);
    if (_entropyBits >= 60) return const Color(0xFFFFFF00);
    if (_entropyBits >= 45) return const Color(0xFFFF8800);
    return Colors.red;
  }

  String _entropyLabel(double bits) {
    if (bits >= 100) return 'EXCELLENT';
    if (bits >= 80) return 'STRONG';
    if (bits >= 60) return 'GOOD';
    if (bits >= 45) return 'OK';
    return 'WEAK';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/password_generator_service.dart';

class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({super.key});

  @override
  State<PasswordGeneratorDialog> createState() => _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  int _selectedMode = 0; // 0: Password, 1: Passphrase, 2: PIN
  
  // Password settings
  int _passwordLength = 16;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  bool _excludeAmbiguous = false;
  
  // Passphrase settings
  int _wordCount = 4;
  
  // PIN settings
  int _pinLength = 6;
  
  String _generatedPassword = '';
  double _strength = 0;

  @override
  void initState() {
    super.initState();
    _generatePassword();
  }

  void _generatePassword() {
    String result;
    
    switch (_selectedMode) {
      case 0: // Password
        final config = PasswordGeneratorConfig(
          length: _passwordLength,
          includeUppercase: _includeUppercase,
          includeLowercase: _includeLowercase,
          includeNumbers: _includeNumbers,
          includeSymbols: _includeSymbols,
          excludeAmbiguous: _excludeAmbiguous,
        );
        result = PasswordGeneratorService.generatePassword(config);
        break;
      case 1: // Passphrase
        result = PasswordGeneratorService.generatePassphrase(wordCount: _wordCount);
        break;
      case 2: // PIN
        result = PasswordGeneratorService.generatePin(length: _pinLength);
        break;
      default:
        result = '';
    }
    
    setState(() {
      _generatedPassword = result;
      _strength = PasswordGeneratorService.calculateStrength(result);
    });
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
            
            // Mode selector
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
                  _generatePassword();
                });
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
            
            // Generated password display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF16161D),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _getStrengthColor(), width: 2),
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
                            onPressed: () {
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
                    value: _strength / 100,
                    backgroundColor: Colors.white10,
                    color: _getStrengthColor(),
                    minHeight: 6,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'STRENGTH: ${PasswordGeneratorService.getStrengthLabel(_strength)} (${_strength.toInt()}%)',
                    style: TextStyle(
                      color: _getStrengthColor(),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Settings based on mode
            Expanded(
              child: SingleChildScrollView(
                child: _buildSettings(),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Action buttons
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
                  onPressed: () => Navigator.pop(context, _generatedPassword),
                  child: const Text('USE_THIS_PASSWORD', style: TextStyle(fontWeight: FontWeight.bold)),
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
            setState(() {
              _passwordLength = value.toInt();
              _generatePassword();
            });
          },
        ),
        const SizedBox(height: 15),
        _buildCheckbox('UPPERCASE (A-Z)', _includeUppercase, (val) {
          setState(() {
            _includeUppercase = val!;
            _generatePassword();
          });
        }),
        _buildCheckbox('LOWERCASE (a-z)', _includeLowercase, (val) {
          setState(() {
            _includeLowercase = val!;
            _generatePassword();
          });
        }),
        _buildCheckbox('NUMBERS (0-9)', _includeNumbers, (val) {
          setState(() {
            _includeNumbers = val!;
            _generatePassword();
          });
        }),
        _buildCheckbox('SYMBOLS (!@#\$...)', _includeSymbols, (val) {
          setState(() {
            _includeSymbols = val!;
            _generatePassword();
          });
        }),
        _buildCheckbox('EXCLUDE AMBIGUOUS (Il1O0)', _excludeAmbiguous, (val) {
          setState(() {
            _excludeAmbiguous = val!;
            _generatePassword();
          });
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
            setState(() {
              _wordCount = value.toInt();
              _generatePassword();
            });
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'Memorable password made of random words\nExample: Correct-Horse-Battery-Staple-1234',
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
            setState(() {
              _pinLength = value.toInt();
              _generatePassword();
            });
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'Numeric PIN code for simple locks',
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

  Color _getStrengthColor() {
    if (_strength >= 80) return const Color(0xFF00FF00);
    if (_strength >= 60) return const Color(0xFF00FBFF);
    if (_strength >= 40) return const Color(0xFFFFFF00);
    if (_strength >= 20) return const Color(0xFFFF8800);
    return Colors.red;
  }
}

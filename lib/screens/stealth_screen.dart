import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'auth_wrapper.dart';

class StealthScreen extends StatefulWidget {
  const StealthScreen({super.key});

  @override
  State<StealthScreen> createState() => _StealthScreenState();
}

class _StealthScreenState extends State<StealthScreen> {
  String _display = "0";
  double? _firstValue;
  String? _operator;
  bool _shouldResetDisplay = false;
  bool _unlocked = false;

  void _onPress(String char) async {
    if (char == "C") {
      setState(() {
        _display = "0";
        _firstValue = null;
        _operator = null;
        _shouldResetDisplay = false;
      });
      return;
    }

    if (char == "=") {
      String secret = await AuthService.getStealthCode();
      if (_display == secret) {
        setState(() => _unlocked = true);
        return;
      }

      if (_firstValue != null && _operator != null) {
        double secondValue = double.tryParse(_display) ?? 0;
        double result = 0;

        switch (_operator) {
          case "+":
            result = _firstValue! + secondValue;
            break;
          case "-":
            result = _firstValue! - secondValue;
            break;
          case "*":
            result = _firstValue! * secondValue;
            break;
          case "/":
            result = secondValue != 0 ? _firstValue! / secondValue : 0;
            break;
        }

        setState(() {
          _display = result % 1 == 0 ? result.toInt().toString() : result.toStringAsFixed(2);
          _firstValue = null;
          _operator = null;
          _shouldResetDisplay = true;
        });
      }
    } else if (['+', '-', '*', '/'].contains(char)) {
      setState(() {
        _firstValue = double.tryParse(_display);
        _operator = char;
        _shouldResetDisplay = true;
      });
    } else {
      setState(() {
        if (_display == "0" || _shouldResetDisplay) {
          _display = char;
          _shouldResetDisplay = false;
        } else if (_display.length < 12) {
          _display += char;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return const AuthWrapper();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Container(
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.all(30),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _display,
                    style: const TextStyle(
                        fontSize: 80,
                        color: Colors.white,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    _buildRow(['7', '8', '9', '/']),
                    _buildRow(['4', '5', '6', '*']),
                    _buildRow(['1', '2', '3', '-']),
                    _buildRow(['C', '0', '=', '+']),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: keys
            .map((key) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _getBtnColor(key),
                        side: BorderSide(color: Colors.white.withOpacity(0.05)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _onPress(key),
                      child: Text(
                        key,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: (key == "=" || key == "C") ? const Color(0xFF00FBFF) : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Color _getBtnColor(String key) {
    if (["/", "*", "-", "+", "="].contains(key)) {
      return Colors.white.withOpacity(0.08);
    }
    return Colors.transparent;
  }
}

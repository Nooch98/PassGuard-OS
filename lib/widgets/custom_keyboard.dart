import 'package:flutter/material.dart';

class CustomKeyboard extends StatefulWidget {
  final Function(String) onTextInput;
  final VoidCallback onDelete;
  final VoidCallback onSubmit;

  const CustomKeyboard({
    super.key,
    required this.onTextInput,
    required this.onDelete,
    required this.onSubmit,
  });

  @override
  State<CustomKeyboard> createState() => _CustomKeyboardState();
}

class _CustomKeyboardState extends State<CustomKeyboard> {
  int _keyboardMode = 0; // 0: uppercase, 1: lowercase, 2: symbols

  final List<String> _upper = "QWERTYUIOPASDFGHJKLZXCVBNM".split("");
  final List<String> _lower = "qwertyuiopasdfghjklzxcvbnm".split("");
  final List<String> _symbols = "1234567890!@#\$%^&*()-_=+[]{};:,.<>?/\\|`~".split("");

  @override
  Widget build(BuildContext context) {
    List<String> currentKeys;
    String toggleLabel;

    if (_keyboardMode == 0) {
      currentKeys = _upper;
      toggleLabel = "abc";
    } else if (_keyboardMode == 1) {
      currentKeys = _lower;
      toggleLabel = "?123";
    } else {
      currentKeys = _symbols;
      toggleLabel = "ABC";
    }

    return Container(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 8,
            children: [
              ...currentKeys.map((key) => _buildKey(key, width: 32)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildKey(toggleLabel, width: 60, isAction: true, color: const Color(0xFFFF00FF)),
              const SizedBox(width: 5),
              _buildKey("SPACE", width: 100, isAction: true),
              const SizedBox(width: 5),
              _buildKey("DEL", width: 60, isAction: true),
              const SizedBox(width: 5),
              _buildKey("ENTER", width: 80, isAction: true, color: const Color(0xFF00FBFF)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label, {double width = 40, bool isAction = false, Color? color}) {
    return SizedBox(
      width: width,
      height: 45,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: color ?? const Color(0xFF00FBFF).withOpacity(0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          backgroundColor: isAction ? Colors.white.withOpacity(0.05) : Colors.transparent,
        ),
        onPressed: () {
          if (label == "DEL") {
            widget.onDelete();
          } else if (label == "ENTER") {
            widget.onSubmit();
          } else if (label == "SPACE") {
            widget.onTextInput(" ");
          } else if (label == "abc") {
            setState(() => _keyboardMode = 1);
          } else if (label == "?123") {
            setState(() => _keyboardMode = 2);
          } else if (label == "ABC") {
            setState(() => _keyboardMode = 0);
          } else {
            widget.onTextInput(label);
          }
        },
        child: Text(
          label,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: isAction ? 11 : 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

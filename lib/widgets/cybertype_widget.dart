import 'package:flutter/material.dart';

class CyberTypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration speed;

  const CyberTypewriterText({
    super.key,
    required this.text,
    required this.style,
    this.speed = const Duration(milliseconds: 30),
  });

  @override
  State<CyberTypewriterText> createState() => _CyberTypewriterTextState();
}

class _CyberTypewriterTextState extends State<CyberTypewriterText> {
  String _displayOutput = "";

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  void _startAnimation() async {
    for (int i = 0; i <= widget.text.length; i++) {
      if (!mounted) return;
      setState(() => _displayOutput = widget.text.substring(0, i));
      await Future.delayed(widget.speed);
    }
  }

  @override
  Widget build(BuildContext context) => SelectableText(_displayOutput, style: widget.style);
}

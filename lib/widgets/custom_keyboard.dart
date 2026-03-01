/*
|--------------------------------------------------------------------------
| PassGuard OS - CustomKeyboard (System-like Secure Keyboard)
|--------------------------------------------------------------------------
| Description:
|   On-screen secure keyboard used during authentication and sensitive input.
|   This version is redesigned to behave closer to a system keyboard:
|     - QWERTY row layout (less "Wrap chaos")
|     - Single-tap SHIFT (caps for next key only)
|     - Double-tap SHIFT locks CAPS (like mobile)
|     - Symbols page with "123" and "#+=" toggles (like mobile)
|     - Cleaner spacing + responsive sizing for narrow screens
|
| Responsibilities:
|   - Provide controlled character input (A–Z, a–z, symbols)
|   - Handle secure text entry for master password
|   - Manage mode switching (letters/symbols) and shift state
|   - Trigger submit and delete callbacks
|
| Security Notes:
|   - Bypasses system keyboard for master password entry
|   - No autocorrect / prediction / OS IME pipeline
|   - No input is stored locally inside this widget
|   - Data is passed directly through callbacks
|
| UX Notes:
|   - SHIFT: tap = one-shot uppercase; double tap = CAPS LOCK
|   - "123" toggles to symbols; "ABC" returns to letters
|   - "#+=" toggles between two symbol pages
|
|--------------------------------------------------------------------------
*/

import 'dart:async';
import 'package:flutter/material.dart';

class CustomKeyboard extends StatefulWidget {
  final ValueChanged<String> onTextInput;
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

enum _Page { letters, symbols1, symbols2 }

class _CustomKeyboardState extends State<CustomKeyboard> {
  _Page _page = _Page.letters;

  bool _shiftOnce = false;
  bool _capsLock = false;

  Timer? _shiftTapTimer;
  int _shiftTapCount = 0;

  static const _r1 = ['q','w','e','r','t','y','u','i','o','p'];
  static const _r2 = ['a','s','d','f','g','h','j','k','l'];
  static const _r3 = ['z','x','c','v','b','n','m'];

  static const _s1r1 = ['1','2','3','4','5','6','7','8','9','0'];
  static const _s1r2 = ['@','#','\$','%','&','-','+','(',')'];
  static const _s1r3 = ['*','"',"'",':',';','!','?'];

  static const _s2r1 = ['[',']','{','}','#','%','^','*','+','='];
  static const _s2r2 = ['_','\\','|','~','<','>','€','£','¥'];
  static const _s2r3 = ['.',';',',','/','?','!','@'];

  bool get _isUpper => _capsLock || _shiftOnce;

  List<String> _row1() => switch (_page) {
        _Page.letters => _r1,
        _Page.symbols1 => _s1r1,
        _Page.symbols2 => _s2r1,
      };

  List<String> _row2() => switch (_page) {
        _Page.letters => _r2,
        _Page.symbols1 => _s1r2,
        _Page.symbols2 => _s2r2,
      };

  List<String> _row3() => switch (_page) {
        _Page.letters => _r3,
        _Page.symbols1 => _s1r3,
        _Page.symbols2 => _s2r3,
      };

  @override
  void dispose() {
    _shiftTapTimer?.cancel();
    super.dispose();
  }

  void _setPage(_Page p) {
    setState(() {
      _page = p;
      if (_page != _Page.letters) {
        _shiftOnce = false;
        _capsLock = false;
      }
    });
  }

  void _handleShiftTap() {
    _shiftTapCount++;
    _shiftTapTimer?.cancel();

    _shiftTapTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;

      setState(() {
        if (_shiftTapCount >= 2) {
          _capsLock = true;
          _shiftOnce = false;
        } else {
          if (_capsLock) {
            _capsLock = false;
            _shiftOnce = false;
          } else {
            _shiftOnce = !_shiftOnce;
          }
        }
      });

      _shiftTapCount = 0;
    });
  }

  void _emit(String ch) {
    final out = (_page == _Page.letters && _isUpper) ? ch.toUpperCase() : ch;
    widget.onTextInput(out);

    if (_page == _Page.letters && _shiftOnce && !_capsLock) {
      setState(() => _shiftOnce = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 380;

    final gap = isNarrow ? 6.0 : 8.0;
    final keyH = isNarrow ? 44.0 : 46.0;
    final pad = isNarrow ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.fromLTRB(pad, 10, pad, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, _row1(), gap: gap, height: keyH),
          SizedBox(height: gap),

          _rowWithSpacers(context, _row2(), leftSpacerFlex: 1, rightSpacerFlex: 1, gap: gap, height: keyH),
          SizedBox(height: gap),

          _thirdRow(context, gap: gap, height: keyH),
          SizedBox(height: gap),

          _bottomRow(context, gap: gap, height: keyH),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, List<String> keys, {required double gap, required double height}) {
    return Row(
      children: [
        for (int i = 0; i < keys.length; i++) ...[
          Expanded(
            child: _key(
              label: (_page == _Page.letters && _isUpper) ? keys[i].toUpperCase() : keys[i],
              height: height,
              onPressed: () => _emit(keys[i]),
            ),
          ),
          if (i != keys.length - 1) SizedBox(width: gap),
        ],
      ],
    );
  }

  Widget _rowWithSpacers(
    BuildContext context,
    List<String> keys, {
    required int leftSpacerFlex,
    required int rightSpacerFlex,
    required double gap,
    required double height,
  }) {
    return Row(
      children: [
        Expanded(flex: leftSpacerFlex, child: const SizedBox()),
        for (int i = 0; i < keys.length; i++) ...[
          Expanded(
            flex: 2,
            child: _key(
              label: (_page == _Page.letters && _isUpper) ? keys[i].toUpperCase() : keys[i],
              height: height,
              onPressed: () => _emit(keys[i]),
            ),
          ),
          if (i != keys.length - 1) SizedBox(width: gap),
        ],
        Expanded(flex: rightSpacerFlex, child: const SizedBox()),
      ],
    );
  }

  Widget _thirdRow(BuildContext context, {required double gap, required double height}) {
    final row3 = _row3();
    final isLetters = _page == _Page.letters;

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _actionKey(
            label: isLetters ? (_capsLock ? 'CAPS' : 'SHIFT') : (_page == _Page.symbols1 ? '#+=' : '123'),
            height: height,
            color: const Color(0xFFFF00FF),
            isActive: isLetters && (_shiftOnce || _capsLock),
            onPressed: isLetters
                ? _handleShiftTap
                : () => _setPage(_page == _Page.symbols1 ? _Page.symbols2 : _Page.symbols1),
          ),
        ),
        SizedBox(width: gap),

        Expanded(flex: 1, child: const SizedBox()),
        for (int i = 0; i < row3.length; i++) ...[
          Expanded(
            flex: 2,
            child: _key(
              label: (_page == _Page.letters && _isUpper) ? row3[i].toUpperCase() : row3[i],
              height: height,
              onPressed: () => _emit(row3[i]),
            ),
          ),
          if (i != row3.length - 1) SizedBox(width: gap),
        ],
        Expanded(flex: 1, child: const SizedBox()),
        SizedBox(width: gap),

        Expanded(
          flex: 3,
          child: _actionKey(
            label: 'DEL',
            height: height,
            onPressed: widget.onDelete,
          ),
        ),
      ],
    );
  }

  Widget _bottomRow(BuildContext context, {required double gap, required double height}) {
    final leftLabel = (_page == _Page.letters) ? '123' : 'ABC';

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _actionKey(
            label: leftLabel,
            height: height,
            color: const Color(0xFFFF00FF),
            onPressed: () => _setPage(_page == _Page.letters ? _Page.symbols1 : _Page.letters),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          flex: 7,
          child: _actionKey(
            label: 'SPACE',
            height: height,
            onPressed: () => widget.onTextInput(' '),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          flex: 4,
          child: _actionKey(
            label: 'ENTER',
            height: height,
            color: const Color(0xFF00FBFF),
            onPressed: widget.onSubmit,
          ),
        ),
      ],
    );
  }

  Widget _key({
    required String label,
    required double height,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: const Color(0xFF00FBFF).withOpacity(0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: Colors.transparent,
        ),
        onPressed: onPressed,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey({
    required String label,
    required double height,
    required VoidCallback onPressed,
    Color? color,
    bool isActive = false,
  }) {
    final c = color ?? Colors.white;
    final border = c.withOpacity(isActive ? 1.0 : 0.45);

    return SizedBox(
      height: height,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: Colors.white.withOpacity(isActive ? 0.09 : 0.05),
        ),
        onPressed: onPressed,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

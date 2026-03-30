/*
|--------------------------------------------------------------------------
| PassGuard OS - Application Entry Point (main.dart)
|--------------------------------------------------------------------------
| Description:
|   Main entry point of the PassGuard OS application.
|   Initializes Flutter bindings, configures system UI preferences,
|   enforces portrait orientation, and launches the root widget.
|
| Responsibilities:
|   - Initialize Flutter engine
|   - Configure status/navigation bar styling
|   - Enforce portrait-only orientation (mobile)
|   - Apply global cyberpunk theme
|   - Route to AuthWrapper (authentication layer)
|
| Architecture Flow:
|   main() → PasswordApp → AuthWrapper → HomePage
|
| Security Notes:
|   - No sensitive data is initialized here
|   - Master key is handled only after authentication
|   - UI configuration does not affect cryptographic logic
|
| Design:
|   - Cyberpunk dark theme
|   - Neon accent colors (cyan / pink / green)
|   - Monospace typography for terminal-style aesthetic
|
| Author: Nooch98
| License: MIT
|--------------------------------------------------------------------------
*/
import 'dart:io' show Platform, ProcessSignal, exit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:passguard/services/session_manager.dart';
import 'screens/auth_wrapper.dart';
import 'services/local_bridge_Service.dart';
import 'services/bridge_auth_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupShutdownHooks();
  await BridgeAuthService.instance.initialize();

  if (Platform.isWindows || Platform.isLinux) {
    await LocalBridgeService.start();
  } else {
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0A0E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const PasswordApp());
}

void _setupShutdownHooks() {
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => _shutdown());
    ProcessSignal.sigint.watch().listen((_) => _shutdown());
  }
}

Future<void> _shutdown() async {
  await LocalBridgeService.stop();
  await BridgeAuthService.instance.clear();
  exit(0);
}

class PasswordApp extends StatelessWidget {
  const PasswordApp({super.key});

  @override
  Widget build(BuildContext context) {
    const neonCyan = Color(0xFF00FBFF);
    const neonPink = Color(0xFFFF00FF);
    const neonGreen = Color(0xFF00FF00);
    const darkBg = Color(0xFF0A0A0E);
    const cardBg = Color(0xFF16161D);

    return Listener(
      onPointerDown: (_) => SessionManager().activity(),
      behavior: HitTestBehavior.translucent,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'PassGuard OS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: darkBg,
          colorScheme: const ColorScheme.dark(
            primary: neonCyan,
            secondary: neonPink,
            surface: cardBg,
            tertiary: neonGreen,
          ),
          textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'Courier New',
                bodyColor: Colors.white,
                displayColor: Colors.white,
              ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: cardBg,
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: neonCyan.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: neonCyan, width: 2),
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            errorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red, width: 2),
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
            labelStyle: const TextStyle(color: neonCyan),
            hintStyle: const TextStyle(color: Colors.white24),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: neonCyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                fontFamily: 'Courier New',
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: neonCyan,
              textStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                fontFamily: 'Courier New',
              ),
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return neonCyan;
              return Colors.white24;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return neonCyan.withOpacity(0.5);
              return Colors.white10;
            }),
          ),
          sliderTheme: const SliderThemeData(
            activeTrackColor: neonCyan,
            inactiveTrackColor: Colors.white24,
            thumbColor: neonCyan,
            overlayColor: Color(0x3300FBFF),
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: neonCyan,
            linearTrackColor: Colors.white10,
          ),
          dividerTheme: const DividerThemeData(
            color: Colors.white10,
            thickness: 1,
            space: 1,
          ),
          cardTheme: CardThemeData(
            color: cardBg,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: neonCyan.withOpacity(0.2)),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: darkBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: neonCyan, width: 1),
            ),
            titleTextStyle: const TextStyle(
              color: neonCyan,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier New',
            ),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: darkBg,
            modalBackgroundColor: darkBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: cardBg,
            contentTextStyle: TextStyle(
              color: Colors.white,
              fontFamily: 'Courier New',
              fontWeight: FontWeight.bold,
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: neonCyan),
            titleTextStyle: TextStyle(
              color: neonCyan,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier New',
            ),
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: neonCyan.withOpacity(0.3)),
            ),
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

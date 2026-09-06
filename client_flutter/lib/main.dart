import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

import 'core/theme/flo_theme.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/error_logging_service.dart';
import 'ui/onboarding/welcome_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/acrylic_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AcrylicTheme.initialize();
  await ErrorLoggingService.instance.init();
  await DatabaseService.database;
  await AuthService.ensureDefaultLocalAccount();

  runApp(const FlowspaceApp());

  doWhenWindowReady(() {
    const initialSize = Size(1280, 800);
    appWindow.minSize = const Size(1024, 768);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = 'FlowSpace';
    appWindow.show();
  });
}

class FlowspaceApp extends StatelessWidget {
  const FlowspaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowSpace',
      debugShowCheckedModeBanner: false,
      theme: FloTheme.darkTheme,
      home: FutureBuilder<bool>(
        future: _hasLocalSession(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data == true
              ? const AppShell()
              : const WelcomeScreen();
        },
      ),
    );
  }

  static Future<bool> _hasLocalSession() async {
    try {
      return await AuthService.getCurrentUser() != null;
    } catch (error) {
      ErrorLoggingService.instance.error(
        'Error resolving local startup session',
        error: error,
      );
      return false;
    }
  }
}

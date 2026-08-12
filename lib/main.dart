import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/platform/app_menu_channel.dart';
import 'package:nexus/features/onboarding/presentation/pages/app_root.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Los atajos globales los registra el sistema, no la app: sobreviven a un
  // hot reload y quedarían duplicados —o peor, huérfanos— sin esta limpieza
  // al arrancar.
  await hotKeyManager.unregisterAll();
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  /// Los ajustes se abren desde el menú de macOS, que no tiene un `context` a
  /// mano. Esta llave es ese `context`.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    AppMenuChannel.listen(onOpenSettings: _openSettings);
  }

  void _openSettings() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    SettingsPage.open(navigator.context);
  }

  @override
  Widget build(BuildContext context) {
    // No es const: theme/darkTheme llaman a NexusTheme.light()/.dark(), que
    // arman un ThemeData vía ColorScheme.fromSeed. Ni fromSeed ni ThemeData
    // tienen constructor const, así que no hay forma de recuperar el const
    // que tenía este MaterialApp sin abandonar fromSeed por un ColorScheme
    // literal con sus ~40 campos a mano. El costo real es nulo: light()/
    // dark() ya cachean el resultado en un static final.
    return MaterialApp(
      navigatorKey: _navigatorKey,
      theme: NexusTheme.light(),
      darkTheme: NexusTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AppRoot(),
    );
  }
}

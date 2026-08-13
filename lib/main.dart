import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/platform/app_menu_channel.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/presentation/widgets/conversation_history_sheet.dart';
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

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  /// Los ajustes se abren desde el menú de macOS, que no tiene un `context` a
  /// mano. Esta llave es ese `context`.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    AppMenuChannel.listen(
      onOpenSettings: _openSettings,
      onOpenHistory: _openHistory,
    );
  }

  void _openSettings() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    SettingsPage.open(navigator.context);
  }

  /// El historial es **de una conversación**, así que sin ninguna abierta no
  /// hay nada que enseñar: se calla en vez de abrir una lista vacía que no
  /// explica de qué carpeta estaría hablando.
  void _openHistory() {
    final navigator = _navigatorKey.currentState;
    final focused = ref.read(conversationsProvider).focused;
    if (navigator == null || focused == null) return;
    final controller = ref.read(
      assistantControllerProvider(focused.id).notifier,
    );
    ConversationHistorySheet.open(
      navigator.context,
      folderPath: focused.folderPath,
      onPick: controller.resume,
      onForget: controller.forgetConversation,
    );
  }

  @override
  Widget build(BuildContext context) {
    // No es const: theme/darkTheme llaman a NexusTheme.light()/.dark(), que
    // arman un ThemeData vía ColorScheme.fromSeed. Ni fromSeed ni ThemeData
    // tienen constructor const, así que no hay forma de recuperar el const
    // que tenía este MaterialApp sin abandonar fromSeed por un ColorScheme
    // literal con sus ~40 campos a mano. El costo real es nulo: light()/
    // dark() ya cachean el resultado en un static final.
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      navigatorKey: _navigatorKey,
      theme: NexusTheme.light(),
      darkTheme: NexusTheme.dark(),
      themeMode: ThemeMode.system,
      locale: locale,
      supportedLocales: NexusStrings.supported,
      // Los de Flutter, para que los widgets de Material —menús, selección de
      // texto— hablen el mismo idioma que la app y no se queden en inglés.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Por encima del Navigator, no envolviendo `home`: Ajustes se abre como
      // una ruta nueva, y esas se construyen **fuera** del hijo de `home`. Con
      // el scope ahí abajo, abrir Ajustes reventaba con «falta un
      // StringsScope» — y solo en esa pantalla, que es lo que lo hacía fácil
      // de no ver hasta usarla.
      builder: (context, child) =>
          StringsScope(strings: NexusStrings.of(locale), child: child!),
      home: const AppRoot(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/onboarding/presentation/pages/app_root.dart';

void main() {
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    // No es const: theme/darkTheme llaman a NexusTheme.light()/.dark(), que
    // arman un ThemeData vía ColorScheme.fromSeed. Ni fromSeed ni ThemeData
    // tienen constructor const, así que no hay forma de recuperar el const
    // que tenía este MaterialApp sin abandonar fromSeed por un ColorScheme
    // literal con sus ~40 campos a mano. El costo real es nulo: light()/
    // dark() ya cachean el resultado en un static final.
    return MaterialApp(
      theme: NexusTheme.light(),
      darkTheme: NexusTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AppRoot(),
    );
  }
}

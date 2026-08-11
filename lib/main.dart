import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/counter/presentation/pages/counter_page.dart';

void main() {
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: NexusTheme.light(),
      darkTheme: NexusTheme.dark(),
      themeMode: ThemeMode.system,
      home: const CounterPage(),
    );
  }
}

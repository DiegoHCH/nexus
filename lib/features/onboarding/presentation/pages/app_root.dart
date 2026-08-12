import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/initial_setup_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/splash_page.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';

/// Decide qué pantalla ve el usuario al arrancar: [SplashPage] siempre
/// primero, y desde ahí a [InitialSetupPage] o directo a [HomePage] (Reposo)
/// según resuelva [AppRouteController].
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(appRouteControllerProvider);
    return switch (route) {
      AppRouteLoading() => const SplashPage(),
      AppRouteNeedsSetup() => const InitialSetupPage(),
      AppRouteReady() => const HomePage(),
    };
  }
}

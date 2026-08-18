import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/initial_setup_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/readiness_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/splash_page.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';

/// Decide qué pantalla ve el usuario al arrancar: [SplashPage] siempre primero,
/// y desde ahí a [ReadinessPage] si falta algo **del sistema**, a
/// [InitialSetupPage] si falta la llave, o directo a [HomePage] (Reposo).
///
/// Ese orden no es casual: lo del sistema va delante porque sin Claude Code la
/// llave de Gemini solo consigue que te contesten sin poder hacer nada.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(appRouteControllerProvider);
    return switch (route) {
      AppRouteLoading() => const SplashPage(),
      AppRouteNotReady(:final readiness) => ReadinessPage(readiness: readiness),
      AppRouteNeedsSetup() => const InitialSetupPage(),
      AppRouteReady() => const HomePage(),
    };
  }
}

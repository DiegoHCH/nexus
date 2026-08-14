import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/initial_setup_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/splash_page.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// Las mismas pantallas de `screens_open_test`, **en claro**.
///
/// Hasta ahora el tema claro estaba construido y cableado pero no se podía
/// elegir, así que nadie lo había visto nunca puesto: ninguna pantalla se había
/// dibujado con esa paleta. Y lo que rompe un tema no rompe ninguna regla —un
/// desbordamiento, un contraste imposible— solo se ve, y solo si alguien mira.
void main() {
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('el splash, en claro', (tester) async {
    await pumpScreen(tester, const SplashPage(), theme: NexusTheme.light());
    expect(tester.takeException(), isNull);
  });

  testWidgets('la configuración inicial, en claro', (tester) async {
    await pumpScreen(
      tester,
      const InitialSetupPage(),
      theme: NexusTheme.light(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('la casa, en claro', (tester) async {
    await pumpScreen(
      tester,
      const HomePage(),
      theme: NexusTheme.light(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('los ajustes, en claro', (tester) async {
    await pumpScreen(
      tester,
      const SettingsPage(),
      theme: NexusTheme.light(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    expect(tester.takeException(), isNull);
  });
}

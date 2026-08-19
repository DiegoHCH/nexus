import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// Que el mínimo de la ventana sea **habitable**.
///
/// El tamaño lo elige el producto y no esta prueba: por debajo de una tablet en
/// horizontal —**1024×768**— esto deja de ser una app de escritorio. Lo que aquí
/// se comprueba es que a ese tamaño las dos pantallas grandes se dibujan sin
/// salirse, porque un mínimo que no cabe es peor que no tener mínimo.
///
/// **Medido, y conviene dejarlo dicho**: a 800×600 tampoco desborda. O sea que
/// 1024 no es el punto de ruptura de la interfaz —aguanta más estrecha de lo que
/// sugería un comentario viejo del repo, probablemente desde que la barra de
/// Ajustes se volvió flexible—. Es una decisión, no un límite descubierto, y
/// esta prueba solo la sostiene.
void main() {
  const minimo = Size(1024, 768);
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('la casa cabe en el mínimo', (tester) async {
    await pumpScreen(
      tester,
      const HomePage(),
      size: minimo,
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('y los ajustes también, que son los más anchos', (tester) async {
    await pumpScreen(
      tester,
      const SettingsPage(),
      size: minimo,
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    expect(tester.takeException(), isNull);
  });
}

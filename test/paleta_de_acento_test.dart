import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

// Elegir el color: que llegue de verdad hasta el orbe.
//
// El token estaba clavado y se llamaba `cyan`. Ahora se elige, y lo que puede
// fallar en silencio es que la elección se guarde y **no se vea**: el acento pasa
// por la preferencia, por el `ThemeData`, por la extensión de tokens y por el
// pintor del orbe, y cualquiera de esos cuatro saltos podría perderla dejando la
// interfaz cian con un círculo violeta marcado en Ajustes.
//
// De ahí que la prueba del orbe mire **píxeles** y no el token: que el token
// llegue no demuestra que se pinte con él.
void main() {
  const es = NexusStringsEs();
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  group('el acento llega al tema', () {
    test('el ThemeData lo lleva en sus tokens', () {
      final tema = NexusTheme.dark(accent: AccentChoice.violet.dark);
      expect(
        tema.extension<NexusColors>()!.accent,
        AccentChoice.violet.dark,
      );
    });

    test('y sin pedir nada sigue siendo el de la paleta', () {
      // Importa porque casi todas las pruebas del repo montan el tema sin acento:
      // si esto cambiara, cambiarían de color sin que nadie lo pidiera.
      expect(
        NexusTheme.dark().extension<NexusColors>()!.accent,
        NexusColors.dark.accent,
      );
    });

    test('cada color se guarda en un tema aparte y no se pisan', () {
      // Los temas se cachean por acento. Con una sola caché, el segundo color
      // elegido devolvería el tema del primero — y el fallo sería «cambio el color
      // y no pasa nada».
      final violeta = NexusTheme.dark(accent: AccentChoice.violet.dark);
      final ambar = NexusTheme.dark(accent: AccentChoice.amber.dark);
      expect(
        violeta.extension<NexusColors>()!.accent,
        isNot(ambar.extension<NexusColors>()!.accent),
      );
    });
  });

  testWidgets('la paleta enseña un círculo por color y marca el elegido', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const SettingsPage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    await tester.tap(find.text(es.sectionAppearance.toUpperCase()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(es.accentTitle), findsOne);
    for (final opcion in AccentChoice.values) {
      expect(
        find.byKey(ValueKey('acento-${opcion.name}')),
        findsOne,
        reason: 'falta el círculo de ${opcion.name}',
      );
    }
  });

  testWidgets('tocar un círculo cambia el acento elegido', (tester) async {
    late ProviderContainer container;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const SettingsPage();
        },
      ),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    await tester.tap(find.text(es.sectionAppearance.toUpperCase()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(accentControllerProvider), AccentChoice.cyan);
    await tester.tap(find.byKey(const ValueKey('acento-violet')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(accentControllerProvider), AccentChoice.violet);
  });

  testWidgets('y el orbe se pinta con el color elegido, no con el cian', (
    tester,
  ) async {
    // La prueba de verdad: píxeles. Que el token llegue al tema no demuestra que
    // el orbe lo use — lo leía como `context.colors.cyan` y podría haberse
    // quedado con un valor propio en cualquier momento.
    Future<(int, int, int)> masVivo(AccentChoice acento) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: NexusTheme.dark(accent: acento.dark),
            builder: (context, child) =>
                StringsScope(strings: const NexusStringsEs(), child: child!),
            home: const RepaintBoundary(
              key: ValueKey('orbe'),
              child: SizedBox(
                width: 300,
                height: 300,
                child: NexusOrb(state: NexusOrbState.listen),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      late List<(int, int, int)> pixeles;
      await tester.runAsync(() async {
        final limite = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('orbe')),
        );
        final imagen = await limite.toImage();
        final datos = await imagen.toByteData(format: ui.ImageByteFormat.rawRgba);
        pixeles = [
          for (var i = 0; i < datos!.lengthInBytes; i += 4)
            (datos.getUint8(i), datos.getUint8(i + 1), datos.getUint8(i + 2)),
        ];
      });
      // El más saturado: el orbe se pinta sobre un fondo casi neutro, así que el
      // píxel que más se aparta del gris es acento puro.
      return pixeles.reduce((a, b) {
        int rango((int, int, int) p) =>
            [p.$1, p.$2, p.$3].reduce((x, y) => x > y ? x : y) -
            [p.$1, p.$2, p.$3].reduce((x, y) => x < y ? x : y);
        return rango(a) >= rango(b) ? a : b;
      });
    }

    int distancia((int, int, int) p, Color c) =>
        (p.$1 - (c.r * 255).round()).abs() +
        (p.$2 - (c.g * 255).round()).abs() +
        (p.$3 - (c.b * 255).round()).abs();

    final conVioleta = await masVivo(AccentChoice.violet);
    expect(
      distancia(conVioleta, AccentChoice.violet.dark),
      lessThan(60),
      reason:
          'el píxel más vivo del orbe es $conVioleta y debería acercarse al '
          'violeta ${AccentChoice.violet.dark}: el acento no llegó al pintor',
    );
    expect(
      distancia(conVioleta, AccentChoice.cyan.dark),
      greaterThan(60),
      reason: 'sigue pintando cian: el orbe no obedece la elección',
    );

    // Y el otro sentido, para que la prueba no pase por casualidad con cualquier
    // color que resulte parecido al violeta.
    final conAmbar = await masVivo(AccentChoice.amber);
    expect(distancia(conAmbar, AccentChoice.amber.dark), lessThan(60));
  });
}

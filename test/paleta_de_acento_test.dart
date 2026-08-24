import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/accent_wheel.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

// Elegir el color en la rueda, y que llegue de verdad hasta el orbe.
//
// Lo que puede fallar en silencio es que la elección se guarde y **no se vea**: el
// acento pasa por la preferencia, por el ajuste de brillo, por el `ThemeData`, por
// la extensión de tokens y por el pintor del orbe. Cualquiera de esos cinco saltos
// podría perderla dejando la app cian con un círculo violeta en Ajustes.
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
      const violeta = Color(0xFFB79BFF);
      final tema = NexusTheme.dark(accent: violeta);
      expect(tema.extension<NexusColors>()!.accent, violeta);
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
      // elegido devolvería el tema del primero — y el fallo se viviría como
      // «cambio el color y no pasa nada».
      final a = NexusTheme.dark(accent: const Color(0xFFB79BFF));
      final b = NexusTheme.dark(accent: const Color(0xFFF5C451));
      expect(
        a.extension<NexusColors>()!.accent,
        isNot(b.extension<NexusColors>()!.accent),
      );
    });
  });

  testWidgets('el botón enseña el color puesto, su nombre y su hexadecimal', (
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
    expect(find.byKey(const ValueKey('abrir-rueda-de-color')), findsOne);
    // Arranca en el cian, así que eso es lo que debe decir.
    expect(find.text(es.accentNameCyan), findsOne);
    expect(find.text('#56E1EA'), findsOne);
    // Y la rueda **no** está a la vista hasta que se pide.
    expect(find.byType(AccentWheel), findsNothing);
  });

  testWidgets('el botón abre la modal con la rueda', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('abrir-rueda-de-color')));
    await tester.pumpAndSettle();

    expect(find.byType(AccentWheel), findsOne);
    // Y la explicación del ajuste de brillo, que es lo que evita que el ajuste se
    // lea como un fallo.
    expect(find.text(es.accentAdjusted), findsOne);
  });

  testWidgets('arrastrar en la rueda cambia el color elegido', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('abrir-rueda-de-color')));
    await tester.pumpAndSettle();

    expect(container.read(accentControllerProvider), Accent.cyan);

    // Se toca a la derecha del centro del disco: ahí el matiz es otro, y el radio
    // da saturación alta.
    final disco = tester.getRect(find.byType(AccentWheel));
    final centro = Offset(
      disco.left + disco.width / 2,
      disco.top + disco.width / 2,
    );
    await tester.dragFrom(centro, const Offset(70, 0));
    await tester.pumpAndSettle();

    final elegido = container.read(accentControllerProvider);
    expect(
      elegido,
      isNot(Accent.cyan),
      reason: 'arrastrar en la rueda no cambió nada',
    );
    // Y se confirmó al soltar: si solo se hubiera avisado durante el arrastre, el
    // estado seguiría en cian.
    expect(elegido.chosen.a, 1.0, reason: 'el acento tiene que ser opaco');
  });

  testWidgets('se puede volver al color original, y solo cuando hace falta', (
    tester,
  ) async {
    // «Volver al original» es de las cosas que se agradecen después de un rato
    // probando colores, y el botón solo tiene sentido si hay algo que deshacer:
    // con el cian puesto no debe estar, igual que la fila del aviso en el menú de
    // la barra no existe cuando no hay versión nueva.
    late ProviderContainer container;
    Future<void> abrir() async {
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
      await tester.tap(find.byKey(const ValueKey('abrir-rueda-de-color')));
      await tester.pumpAndSettle();
    }

    await abrir();
    expect(
      find.byKey(const ValueKey('volver-al-color-original')),
      findsNothing,
      reason: 'con el original puesto no hay nada que devolver',
    );

    // Se elige otro y entonces sí aparece.
    container
        .read(accentControllerProvider.notifier)
        .select(const Color(0xFFB79BFF));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('volver-al-color-original')), findsOne);

    await tester.tap(find.byKey(const ValueKey('volver-al-color-original')));
    await tester.pumpAndSettle();

    expect(container.read(accentControllerProvider), Accent.cyan);
    expect(
      find.byKey(const ValueKey('volver-al-color-original')),
      findsNothing,
      reason: 'y se va, porque ya no hay nada que deshacer',
    );
  });

  testWidgets('y el orbe se pinta con el color elegido, no con el cian', (
    tester,
  ) async {
    // La prueba de verdad: píxeles. Que el token llegue al tema no demuestra que
    // el orbe lo use.
    Future<(int, int, int)> masVivo(Color elegido) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: NexusTheme.dark(
              accent: Accent(elegido).forBrightness(Brightness.dark),
            ),
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
        final datos = await imagen.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        pixeles = [
          for (var i = 0; i < datos!.lengthInBytes; i += 4)
            (datos.getUint8(i), datos.getUint8(i + 1), datos.getUint8(i + 2)),
        ];
      });
      // El más saturado: el orbe se pinta sobre un fondo casi neutro, así que el
      // píxel que más se aparta del gris es acento puro.
      int rango((int, int, int) p) =>
          [p.$1, p.$2, p.$3].reduce((x, y) => x > y ? x : y) -
          [p.$1, p.$2, p.$3].reduce((x, y) => x < y ? x : y);
      return pixeles.reduce((a, b) => rango(a) >= rango(b) ? a : b);
    }

    int distancia((int, int, int) p, Color c) =>
        (p.$1 - (c.r * 255).round()).abs() +
        (p.$2 - (c.g * 255).round()).abs() +
        (p.$3 - (c.b * 255).round()).abs();

    const violeta = Color(0xFFB79BFF);
    final conVioleta = await masVivo(violeta);
    expect(
      distancia(conVioleta, violeta),
      lessThan(60),
      reason:
          'el píxel más vivo del orbe es $conVioleta y debería acercarse al '
          'violeta: el acento no llegó al pintor',
    );
    expect(
      distancia(conVioleta, const Color(0xFF56E1EA)),
      greaterThan(60),
      reason: 'sigue pintando cian: el orbe no obedece la elección',
    );

    // Y el otro sentido, para que no pase por casualidad con cualquier color que
    // resulte parecido al violeta.
    const ambar = Color(0xFFF5C451);
    expect(distancia(await masVivo(ambar), ambar), lessThan(60));
  });
}

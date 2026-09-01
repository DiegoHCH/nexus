import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/permission_switch.dart';

import 'support/screen_harness.dart';

/// Tres cosas de Ajustes, reportadas mirándolo.
///
/// Ninguna rompe nada ni lanza: las pestañas respondían solo en el ancho de su
/// palabra, el interruptor de permisos salía en todas las secciones sin nada que
/// lo explicase, y «Cerrar» se plantaba a media pantalla en vez de en el borde.
void main() {
  const strings = NexusStringsEs();
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  Future<void> abrir(WidgetTester tester) => pumpScreen(
    tester,
    const SettingsPage(),
    overrides: [
      workspaceControllerProvider.overrideWith(
        () => FixedWorkspace(workspaceWith()),
      ),
    ],
  );

  group('las pestañas se pueden pulsar', () {
    testWidgets('cada una ocupa el ancho de la columna, no el de su palabra', (
      tester,
    ) async {
      await abrir(tester);

      // «VOZ» es la corta y «SUPERPODERES» la larga. Antes, apuntar a la corta
      // daba tres letras de blanco útil y la larga doce.
      final corta = tester.getRect(find.byKey(const ValueKey('seccion-voice')));
      final larga = tester.getRect(
        find.byKey(const ValueKey('seccion-superpowers')),
      );

      expect(corta.width, larga.width, reason: 'todas valen lo mismo');
      expect(
        corta.width,
        greaterThan(180),
        reason:
            'la columna mide 200: el área útil es la columna, no la palabra',
      );
    });

    testWidgets('y no queda hueco muerto entre una y la siguiente', (
      tester,
    ) async {
      await abrir(tester);

      // Se recorren en orden y cada una tiene que empezar donde acaba la
      // anterior: un hueco entre ambas es una franja que no responde al clic y
      // que no se ve, que es la peor clase de hueco.
      Rect anterior = tester.getRect(
        find.byKey(const ValueKey('seccion-voice')),
      );
      // El orden es el del enum, escrito a mano a propósito: añadir una sección
      // obliga a pasar por aquí, y así una pestaña nueva no puede colarse sin que
      // nadie compruebe que no deja un hueco. «mobile» entró justo así.
      for (final nombre in [
        'llaves',
        'imagenes',
        'avisos',
        'nombres',
        'permissions',
        'mobile',
        'history',
        'pruebas',
        'cuentas',
        'stats',
        'superpowers',
        'emulators',
        'appearance',
        'language',
        'salidas',
        'help',
      ]) {
        final actual = tester.getRect(find.byKey(ValueKey('seccion-$nombre')));
        expect(
          actual.top,
          anterior.bottom,
          reason: 'hay hueco muerto antes de «$nombre»',
        );
        expect(actual.height, greaterThan(30), reason: '«$nombre» es muy baja');
        anterior = actual;
      }
    });
  });

  group('la cabecera', () {
    testWidgets('ya no lleva el interruptor de permisos', (tester) async {
      // Es del espacio de trabajo entero: en la cabecera aparecía junto a la voz
      // o al idioma sin decir de qué hablaba.
      //
      // Se mira desde **Voz**, no desde la sección de apertura: Ajustes abre en
      // Permisos, que tiene su propio interruptor con contexto, y comprobarlo ahí
      // no distinguiría el de la cabecera del de la sección.
      await abrir(tester);
      // Por llave y no por texto: «VOZ» sale dos veces en esta pantalla —la
      // pestaña y la modalidad de una carpeta— y por eso las pestañas la llevan.
      await tester.tap(find.byKey(const ValueKey('seccion-voice')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(PermissionSwitch), findsNothing);
    });

    testWidgets('pero en Permisos sigue estando, con su explicación', (
      tester,
    ) async {
      // Quitarlo de la cabecera no es quitarlo de la app: ahí tiene contexto.
      await abrir(tester);
      await tester.tap(find.byKey(const ValueKey('seccion-permissions')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(PermissionSwitch), findsOne);
      expect(find.text(strings.filePermissionsTitle), findsOne);
    });

    testWidgets('y «Cerrar» está pegado al borde derecho', (tester) async {
      await abrir(tester);

      final ventana = tester.view.physicalSize / tester.view.devicePixelRatio;
      final cerrar = tester.getRect(find.text(strings.closeEsc));

      expect(
        ventana.width - cerrar.right,
        lessThan(80),
        reason:
            'con un Flexible por texto, el reparto dejaba el botón a media '
            'pantalla en vez de en el borde',
      );
    });
  });
}

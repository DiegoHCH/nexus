import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

// Que **todas** las secciones de Ajustes abran, no dos de ocho.
//
// Esto nace de un hueco medido al partir `settings_page.dart` en diez archivos: de
// las ocho secciones, **solo Apariencia y Ayuda se abrían en alguna prueba**. Las
// otras seis se movieron de archivo con la suite entera en verde, y ese verde no
// decía nada sobre ellas — es exactamente el fallo para el que existe
// `screen_harness.dart`: montaje roto con el análisis limpio y las reglas
// intactas.
//
// No comprueba contenido a propósito. Comprueba que se pulsa la pestaña y **la
// sección se construye sin lanzar**, que es lo único que un cambio de archivos
// puede romper y lo único que ninguna otra prueba miraba.
/// **Emuladores es la única sección que habla con procesos al construirse**, y
/// aquí eso no vale: `flutter emulators` y `adb` tardarían segundos y su plazo de
/// espera deja un `Timer` vivo cuando el árbol ya se tiró —«A Timer is still
/// pending even after the widget tree was disposed»—. Así que se le pone una
/// puerta de mentira.
///
/// Se sustituye el data source y no el provider de la lista para que lo que se
/// prueba siga siendo el montaje de verdad: la sección pide, recibe y pinta.
class _SinMaquina extends EmuladoresDataSource {
  const _SinMaquina();

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async =>
      (emuladores: const <Emulador>[], error: null);

  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => const [];
}

void main() {
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('todas las secciones se abren sin reventar', (tester) async {
    await pumpScreen(
      tester,
      const SettingsPage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
        emuladoresDataSourceProvider.overrideWithValue(const _SinMaquina()),
      ],
    );

    // Las pestañas se buscan por su llave y no por su texto: el texto sale del
    // diccionario y cambiar una palabra no debería romper esta prueba, que es de
    // montaje.
    final pestanas = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('seccion-'),
    );

    final cuantas = tester.widgetList(pestanas).length;
    expect(
      cuantas,
      // Diez con «Emuladores». Este número se sube **a mano y a propósito** — es
      // lo que hace que añadir una sección pase por aquí, y ya avisó dos veces:
      // de la novena («Móvil», al dejar de estar apagada) y de la décima.
      //
      // El título de la prueba no lleva el número justamente por eso: decía
      // «ocho» cuando ya esperaba nueve, y un nombre que miente es peor que uno
      // vago.
      10,
      reason:
          'se esperaban diez secciones y hay $cuantas: si se añade una al enum, '
          'esta prueba tiene que verla — y si desaparece, también',
    );

    for (var i = 0; i < cuantas; i++) {
      final llave =
          (tester.widgetList(pestanas).elementAt(i).key! as ValueKey<String>)
              .value;
      await tester.tap(find.byKey(ValueKey(llave)));
      // Dos bombeos y no `pumpAndSettle`: hay secciones con animaciones que no
      // paran —el orbe de la prueba de sonido— y asentarlas sería esperar para
      // siempre.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        tester.takeException(),
        isNull,
        reason: 'la sección «$llave» revienta al abrirse',
      );
    }
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      // Trece desde que entró «Qué sale», la que enseña las cuatro puertas
      // juntas. Este número se toca **a mano y a propósito** — es lo que hace
      // que añadir o quitar una sección pase por aquí, y ya avisó seis veces: de
      // la novena («Móvil», al dejar de estar apagada), de la décima, de
      // «Corridas» al entrar, de «Pruebas», de «Corridas» otra vez al salir, y
      // de esta última.
      //
      // El título de la prueba no lleva el número justamente por eso: decía
      // «ocho» cuando ya esperaba nueve, y un nombre que miente es peor que uno
      // vago.
      15,
      reason:
          'se esperaban quince secciones y hay $cuantas: si se añade una al enum, '
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

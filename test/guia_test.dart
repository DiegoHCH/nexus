import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// La guía: lo que necesita Nexus y qué hacer con él, en frío y siempre a mano.
///
/// Lo que se vigila aquí no es que el texto exista, es que **no mienta**. La
/// guía afirma cosas concretas sobre el código —cuántos modos de carpeta hay,
/// con cuál se empieza— y esas afirmaciones envejecen solas: el día que alguien
/// añada un tercer modo, la frase «uno de dos modos» pasa a ser falsa y nada lo
/// diría. Ya pasó una vez esta semana con el tour, que aseguraba que el contexto
/// se veía en la barra de arriba.
void main() {
  const es = NexusStringsEs();
  const en = NexusStringsEn();
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  Future<void> abrirAyuda(WidgetTester tester, {ThemeData? tema}) async {
    await pumpScreen(
      tester,
      const SettingsPage(),
      theme: tema,
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    // Las pestañas se pintan en mayúsculas; se transforma igual que la pantalla
    // para que un cambio de texto no rompa la prueba por el lado equivocado.
    await tester.tap(find.text(es.sectionHelp.toUpperCase()));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('la guía abre y se lee', () {
    testWidgets('los cuatro bloques, desplazándose', (tester) async {
      await abrirAyuda(tester);
      expect(tester.takeException(), isNull);

      // Se buscan desplazándose porque la guía **no cabe en una pantalla** y su
      // `ListView` solo construye lo visible: comprobarlos sin scroll solo
      // encontraría los dos primeros, y pasaría igual si los otros dos no
      // existieran.
      for (final titulo in [
        es.guideNeedsTitle,
        es.guidePrivacyTitle,
        es.guidePiecesTitle,
        es.guideTroubleTitle,
      ]) {
        await tester.scrollUntilVisible(
          find.text(titulo),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(titulo), findsOne, reason: 'falta el bloque «$titulo»');
      }
      expect(tester.takeException(), isNull, reason: 'y sin desbordar al bajar');
    });

    testWidgets('y en claro', (tester) async {
      await abrirAyuda(tester, tema: NexusTheme.light());
      expect(tester.takeException(), isNull);
      expect(find.text(es.guideNeedsTitle), findsOne);
    });

    testWidgets('con el tour a mano, que es lo que ya existía', (tester) async {
      await abrirAyuda(tester);
      expect(find.text(es.helpTourAction), findsOne);
    });
  });

  group('la guía no miente sobre el código', () {
    // Si alguien añade un tercer modo, esta prueba cae y con ella el texto que
    // dice «uno de dos modos». Es el único enganche entre la prosa y el código.
    test('son dos modos de carpeta, ni uno ni tres', () {
      expect(FolderModality.values, hasLength(2));
      expect(
        FolderModality.values.toSet(),
        {FolderModality.textOnly, FolderModality.voice},
      );
    });

    test('y el restrictivo es el que no deja hablar', () {
      // La guía dice que se empieza en el restrictivo. Que `textOnly` sea el
      // restrictivo no es una convención de nombres: se comprueba.
      expect(FolderModality.textOnly.allowsVoice, isFalse);
      expect(FolderModality.voice.allowsVoice, isTrue);
    });

    test('lo del `toolResponse` se dice, porque es lo único no deducible', () {
      // Es la frase por la que existe este bloque: sin ella, «solo texto» se lee
      // como «micrófono apagado», que es falso y tiene consecuencias fuera de la
      // app. Si alguien recorta el texto, que sea a la vista.
      for (final strings in [es.guidePrivacyBody, en.guidePrivacyBody]) {
        expect(strings.toLowerCase(), contains('gemini'));
      }
      expect(es.guidePrivacyBody, contains('micrófono apagado'));
      expect(en.guidePrivacyBody, contains('microphone off'));
    });

    test('cuenta las dos cosas que no se ven desde la app', () {
      // Ninguna de las dos se puede deducir mirando la pantalla, y las dos se
      // añadieron después de que se preguntara por ellas en voz alta.
      //
      // La del cajón de salida tiene código detrás —el guardia que niega la voz,
      // en `voice_guard_test`—, así que si alguien quita la frase, la guía deja
      // de explicar un comportamiento que sí existe.
      expect(es.guidePrivacyBody, contains('Anthropic'));
      expect(en.guidePrivacyBody, contains('Anthropic'));
      expect(es.guidePrivacyBody, contains('carpeta de salida'));
      expect(en.guidePrivacyBody, contains('output folder'));
    });

    test('los atajos que se prometen son los que hay', () {
      // ⌥Espacio, ⌘Y y ⌘, están escritos en `home_page.dart`. Aquí solo se fija
      // que la guía no invente otros: cambiar un atajo sin cambiar la guía deja
      // una instrucción que no funciona.
      for (final cuerpo in [es.guidePiecesBody, en.guidePiecesBody]) {
        expect(cuerpo, contains('⌘Y'));
        expect(cuerpo, contains('⌘,'));
        expect(cuerpo, contains('⌥'));
      }
    });
  });
}

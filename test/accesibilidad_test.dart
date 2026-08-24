import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/screen_harness.dart';

// Lo que un lector de pantalla encuentra en el HUD.
//
// Medido antes de tocar nada: el HUD en reposo tenía **seis nodos con etiqueta**
// —la carpeta, el permiso, «NUEVA», Modelo, Esfuerzo y la caja de escribir—. Los
// tooltips ya etiquetan varios botones, así que no era el desierto que parecía.
//
// Lo que no existía para VoiceOver era justo lo importante: **el orbe**, que es
// el mando principal de la app y es un `CustomPaint` sin nombre; y el círculo del
// cupo y el botón de adjuntar, los dos con `tooltip: ''` — alguien lo vació para
// quitar el globo y con eso se llevó también la etiqueta.
void main() {
  const strings = NexusStringsEs();
  late Directory support;

  setUp(() {
    support = prepareScreenTest();
    // Con el tour ya visto: si no, el velo tapa el HUD y se estaría midiendo el
    // tour en vez de la pantalla.
    SharedPreferences.setMockInitialValues({'flutter.tour_seen': true});
  });
  tearDown(() => support.deleteSync(recursive: true));

  Future<SemanticsHandle> abrirCasa(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () =>
              FixedWorkspace(workspaceWith(modality: FolderModality.textOnly)),
        ),
      ],
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return handle;
  }

  testWidgets('el orbe se anuncia, y dice en qué estado está', (tester) async {
    final handle = await abrirCasa(tester);

    final orbe = find.bySemanticsLabel(strings.orbLabel);
    expect(orbe, findsOne, reason: 'el mando principal no tenía nombre');

    final nodo = tester.getSemantics(orbe);
    expect(
      nodo.flagsCollection.isButton,
      isTrue,
      reason: 'se pulsa: anunciarlo como texto no dice que se pueda',
    );
    expect(
      nodo.value,
      strings.asleep,
      reason:
          'el estado es la única forma de saber qué pasa sin ver el dibujo: '
          'dormido, escuchando, trabajando',
    );
    expect(nodo.hint, isNotEmpty, reason: 'y cómo se usa, incluido el atajo');

    handle.dispose();
  });

  testWidgets('el círculo del cupo también, con sus cifras', (tester) async {
    // `tooltip: ''` le quitaba el globo y la etiqueta a la vez.
    final handle = await abrirCasa(tester);

    final medidor = find.bySemanticsLabel(strings.contextWindow);
    expect(medidor, findsOne);
    expect(
      tester.getSemantics(medidor).value,
      isNotEmpty,
      reason: 'sin cifras aún, tiene que decir eso y no quedarse mudo',
    );

    handle.dispose();
  });

  testWidgets('y el botón de adjuntar', (tester) async {
    final handle = await abrirCasa(tester);
    expect(find.bySemanticsLabel(strings.attachFile), findsWidgets);
    handle.dispose();
  });
}

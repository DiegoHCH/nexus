import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// El orbe es lo único que ocupa la pantalla de arranque, así que es lo primero
/// que se pulsa para hablar. Y era el único de los cuatro caminos para empezar
/// que no hacía nada: «NUEVA», escribir y ⌥Espacio ya creaban conversación.
void main() {
  const strings = NexusStringsEs();
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('tocar el orbe sin conversaciones crea una y abre la voz', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          // En solo texto a propósito: así el guardia de voz corta **después**
          // de crear la conversación, y la prueba comprueba lo suyo —que el
          // orbe actúa— sin necesitar un micrófono de verdad.
          () =>
              FixedWorkspace(workspaceWith(modality: FolderModality.textOnly)),
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );

    expect(
      container.read(conversationsProvider).items,
      isEmpty,
      reason: 'se arranca sin ninguna, que es la pantalla del fallo',
    );

    await tester.tap(find.byType(NexusOrb));
    // `pump` y no `pumpAndSettle`: el orbe se anima en bucle y el árbol no se
    // queda quieto nunca.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(conversationsProvider).items,
      hasLength(1),
      reason: 'el orbe era decorativo: se pulsaba y no pasaba nada',
    );
  });

  testWidgets('y el hueco «NUEVA» sigue pulsándose por encima del orbe', (
    tester,
  ) async {
    // El orbe ocupa toda la pantalla y es opaco al tacto, así que hay que
    // asegurarse de que no se traga lo que tiene encima.
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );
    await tester.tap(find.text(strings.newConversation));
    // `pump` y no `pumpAndSettle`: el orbe se anima en bucle y el árbol no se
    // queda quieto nunca.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));

    // «NUEVA» abre un menú para elegir dónde. Que el menú aparezca **es** lo
    // que esta prueba mira: significa que la pulsación llegó al hueco y no se
    // la tragó el orbe, que ahora ocupa la pantalla entera y es opaco al tacto.
    expect(
      find.text('proyecto'),
      findsOneWidget,
      reason: 'el orbe de debajo no puede robarle las pulsaciones al dock',
    );
  });
}

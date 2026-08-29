import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/conversation_dock.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';
import 'package:nexus/features/onboarding/presentation/widgets/tour_anchor.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// El orbe y el muelle de conversaciones **comparten esquina**: los dos viven
/// en el mismo `Stack`, el orbe ocupando la columna izquierda entera y el
/// muelle flotando abajo a la izquierda. Sin reservarle su franja al muelle,
/// la pila de conversaciones subía hasta la mitad del orbe y quedaba una
/// encima de la otra según el orden de pintado — que no es una decisión de
/// diseño, es el accidente de quién se declaró después.
///
/// Es geometría, no lógica: no hay estado que mirar, solo dos rectángulos que
/// no se pueden cruzar. Por eso se mide, que es la única forma de que no se
/// vuelva a colar.
void main() {
  const carpetas = [
    '/Users/alguien/proyecto',
    '/Users/alguien/otra',
    '/Users/alguien/tercera',
  ];
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('con varias abiertas, el muelle no se cruza con el orbe', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(
            Workspace(
              folders: [
                for (final path in carpetas)
                  PairedFolder(path: path, modality: FolderModality.textOnly),
              ],
              activePath: carpetas.first,
            ),
          ),
        ),
        conversationsDataSourceProvider.overrideWithValue(
          _Disco({
            'items': [
              for (final (i, path) in carpetas.indexed)
                {'id': 'c$i', 'folderPath': path},
            ],
            'focusedId': 'c0',
          }),
        ),
      ],
    );
    // El disco contesta en asíncrono: sin esta vuelta la lista todavía está
    // vacía y se estaría midiendo la pantalla de arranque.
    await tester.pump(const Duration(milliseconds: 100));

    final muelle = tester.getRect(find.byType(ConversationDock));
    final orbe = tester.getRect(_anclaDe(TourStop.orb));

    expect(
      orbe.overlaps(muelle),
      isFalse,
      reason: 'el muelle se pintaba encima del orbe, o el orbe encima de él',
    );
    expect(
      orbe.bottom,
      lessThanOrEqualTo(muelle.top),
      reason: 'la franja del muelle va debajo del orbe, no al lado',
    );
  });
}

/// El orbe grande, y no los pequeños de cada ficha del muelle: hay un `NexusOrb`
/// por conversación abierta, así que buscar por tipo devuelve cuatro.
Finder _anclaDe(TourStop stop) => find.byWidgetPredicate(
  (widget) => widget is TourAnchor && widget.stop == stop,
);

class _Disco implements ConversationsDataSource {
  _Disco(this.contenido);

  Map<String, dynamic> contenido;

  @override
  Future<Map<String, dynamic>> read() async {
    await Future<void>.delayed(Duration.zero);
    return contenido;
  }

  @override
  Future<void> write(Map<String, dynamic> json) async => contenido = json;
}

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb_painter.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/conversation_dock.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
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
        // Con archivo: al arrancar, una conversación que no ha dicho nada se
        // cierra sola, y esta prueba necesita las cuatro abiertas para mirar
        // cómo se apila el muelle.
        localConversationStoreProvider.overrideWithValue(
          _ConAlgoDicho([for (final (i, _) in carpetas.indexed) 'c$i']),
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
    final caja = tester.getRect(_anclaDe(TourStop.orb));

    // Se mide **el orbe pintado**, no su caja. Antes se exigía que las cajas no
    // se cruzaran, y esa exigencia era el fallo: la caja del orbe es toda la
    // columna izquierda, así que para no tocar el muelle tenía que acabar por
    // encima de él — y el orbe, que llena el lado corto de su caja, se
    // encogía con cada conversación abierta aunque el círculo no llegara ni de
    // lejos al muelle. Lo que no se puede cruzar es el dibujo.
    expect(
      NexusOrbPainter.envolventeEn(caja).overlaps(muelle),
      isFalse,
      reason: 'el muelle se pintaba encima del orbe, o el orbe encima de él',
    );
  });

  /// Lo que se rompió al reservar la franja siempre: en la pantalla de arranque
  /// el orbe es lo único que hay que mirar, y encogía **por abrir
  /// conversaciones que nunca lo tocaron**.
  testWidgets('sin cruce, el orbe no cede nada de su caja', (tester) async {
    const caja = Size(1400, 800);

    expect(
      ConversationDock.franjaQueEstorba(caja, const Conversations()),
      0,
      reason: 'con la ventana entera el círculo no llega al muelle',
    );

    // Y con una abierta tampoco: la franja crece hacia arriba por la
    // izquierda, y el círculo sigue empezando muy a la derecha del muelle.
    expect(
      ConversationDock.franjaQueEstorba(caja, _conAbiertas(1)),
      0,
      reason: 'una abierta no acerca el muelle al círculo',
    );

    // Lo que sí lo acerca es que el muelle se parta en dos columnas, que es
    // cuando de verdad llega hasta donde el orbe se pinta. Eso no es el fallo
    // que se arregla aquí: es un cruce real, y ceder la franja es correcto.
    final dosColumnas = _conAbiertas(Conversations.porColumna);
    expect(
      ConversationDock.anchoOcupado(dosColumnas),
      greaterThan(ConversationDock.tabWidth),
      reason: 'con cuatro piezas el muelle mide dos columnas',
    );
  });

  _laAlineacion();

  testWidgets('con la caja estrecha sí la cede, que es para lo que existe', (
    tester,
  ) async {
    // La caja del orbe con la conversación abierta: el 42 % del ancho. Ahí el
    // círculo mide el ancho entero y su borde llega al margen izquierdo, justo
    // donde está el muelle.
    const caja = Size(1400 * 0.42, 800);
    final abiertas = _conAbiertas(Conversations.porColumna);

    expect(
      ConversationDock.franjaQueEstorba(caja, abiertas),
      ConversationDock.espacioReservado(abiertas),
      reason: 'aquí sí se cruzan, y la franja es justo lo que se le aparta',
    );
  });
}

/// Las dos columnas del muelle, alineadas entre sí.
///
/// Con más de [Conversations.porColumna] abiertas el muelle se parte en
/// columnas puestas en un `Row` alineado por abajo. La separación entre fichas
/// la ponía **cada ficha**, con un `Padding` de abajo, y el hueco de «NUEVA» no
/// lo llevaba: la columna que acaba en «NUEVA» medía esos 8 px menos y se
/// hundía enteros, dejando dos columnas de fichas del mismo alto desalineadas
/// entre sí. Se reportó mirando la pantalla, que es la única forma de verlo.
void _laAlineacion() {
  const carpetas = [
    '/Users/alguien/uno',
    '/Users/alguien/dos',
    '/Users/alguien/tres',
    '/Users/alguien/cuatro',
  ];
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('las dos columnas del muelle apoyan en el mismo suelo', (
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
        // Con archivo: al arrancar, una conversación que no ha dicho nada se
        // cierra sola, y esta prueba necesita las cuatro abiertas para mirar
        // cómo se apila el muelle.
        localConversationStoreProvider.overrideWithValue(
          _ConAlgoDicho([for (final (i, _) in carpetas.indexed) 'c$i']),
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
    await tester.pump(const Duration(milliseconds: 100));

    // Cuatro abiertas con columnas de tres: tres en la primera, la cuarta y
    // «NUEVA» en la segunda. Las fichas se agrupan por su borde izquierdo, que
    // es lo que dice en qué columna cayó cada una.
    final columnas = <double, List<double>>{};
    for (final ficha
        in find
            .descendant(
              of: find.byType(ConversationDock),
              matching: find.byType(InkWell),
            )
            .evaluate()) {
      final r = tester.getRect(find.byElementPredicate((e) => e == ficha));
      if (r.width != ConversationDock.tabWidth) continue;
      columnas.putIfAbsent(r.left, () => []).add(r.bottom);
    }

    expect(columnas.length, 2, reason: 'dos columnas con cuatro abiertas');
    // **Coinciden por abajo, no por arriba.** Las columnas tienen distinto
    // número de fichas y van alineadas por el suelo, así que la corta arranca
    // más abajo — eso es lo correcto. Lo que no puede pasar es que sus suelos
    // se separen: ahí es donde se hundían los 8 px.
    final suelos = [for (final ys in columnas.values) ys.reduce(max)];
    expect(
      suelos.first,
      moreOrLessEquals(suelos.last, epsilon: 0.5),
      reason: 'una columna se hundía 8 px por el hueco que le falta a «NUEVA»',
    );
  });
}

Conversations _conAbiertas(int cuantas) => Conversations(
  items: [
    for (var i = 0; i < cuantas; i++)
      Conversation(id: 'c$i', folderPath: '/Users/alguien/p$i'),
  ],
  focusedId: 'c0',
);

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

/// Un archivo que dice que todas ellas hablaron.
///
/// Hace falta desde que el arranque cierra las que no dijeron nada: sin esto,
/// las cuatro de esta prueba se cerrarían antes de que el muelle las pinte.
class _ConAlgoDicho implements LocalConversationStore {
  const _ConAlgoDicho(this.ids);

  final List<String> ids;

  @override
  Future<List<ConversationSummary>> list(String folderPath) async => [
    for (final id in ids)
      ConversationSummary(
        id: id,
        folderPath: folderPath,
        startedAt: DateTime(2026, 9, 5),
        title: 'algo',
        turns: 2,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

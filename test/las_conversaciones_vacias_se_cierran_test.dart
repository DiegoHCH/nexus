import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Las conversaciones que no llegaron a decir nada se cierran al arrancar.
//
// 🔴 **Una pestaña vacía no es trabajo empezado**: es una que se abrió y se
// dejó. Y mientras esté ahí el arranque no es el arranque — la puerta que
// saluda y pregunta dónde trabajar solo aparece sin ninguna conversación
// abierta, así que una vacía de ayer la tapa entera.
//
// Vacía se decide **por los turnos de su ficha**, y no porque la ficha exista:
// la ficha se escribe al abrir la conversación, así que hasta la que no ha
// dicho nada tiene la suya. Los turnos los pone Claude — sin hablarle ni
// escribirle, no hay ninguno. Reportado con una pestaña de `nexus` sin un solo
// mensaje que no se cerraba.

const _carpeta = '/Users/alguien/personal/nexus';

class _Guardadas extends ConversationsDataSource {
  _Guardadas(this._items);

  Map<String, dynamic> _items;
  Map<String, dynamic>? escrito;

  @override
  Future<Map<String, dynamic>> read() async => _items;

  @override
  Future<void> write(Map<String, dynamic> value) async {
    escrito = value;
    _items = value;
  }
}

class _Archivo implements LocalConversationStore {
  _Archivo(this.fichas);

  final List<ConversationSummary> fichas;

  @override
  Future<List<ConversationSummary>> list(String folderPath) async => [
    for (final ficha in fichas)
      if (ficha.folderPath == folderPath) ficha,
  ];

  @override
  Future<void> save(ConversationRecord record) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ConversationSummary _ficha(String id, {required int turnos}) =>
    ConversationSummary(
      id: id,
      folderPath: _carpeta,
      startedAt: DateTime(2026, 9, 5),
      title: 'lo que sea',
      turns: turnos,
    );

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => const Workspace(
    folders: [PairedFolder(path: _carpeta, modality: FolderModality.voice)],
    activePath: _carpeta,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Conversations> alArrancar({
    required List<String> abiertas,
    required List<ConversationSummary> archivo,
  }) async {
    final guardadas = _Guardadas({
      'items': [
        for (final id in abiertas) {'id': id, 'folderPath': _carpeta},
      ],
      'focusedId': abiertas.firstOrNull,
    });
    final container = ProviderContainer(
      overrides: [
        conversationsDataSourceProvider.overrideWithValue(guardadas),
        localConversationStoreProvider.overrideWithValue(_Archivo(archivo)),
        workspaceControllerProvider.overrideWith(_Espacio.new),
      ],
    );
    addTearDown(container.dispose);

    container.read(conversationsProvider);
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(conversationsProvider);
  }

  test('la que no dijo nada se cierra', () async {
    final estado = await alArrancar(
      abiertas: const ['vacia'],
      archivo: [_ficha('vacia', turnos: 0)],
    );

    expect(estado.items, isEmpty);
  });

  // 🔴 El caso que se escapó: la ficha existe —se escribe al abrirla— y hasta
  // ahí llegaba la comprobación, así que no se cerraba ninguna.
  test('y la que ni ficha tiene, también', () async {
    final estado = await alArrancar(
      abiertas: const ['vacia'],
      archivo: const [],
    );

    expect(estado.items, isEmpty);
  });

  test('la que sí habló se queda', () async {
    final estado = await alArrancar(
      abiertas: const ['con-algo'],
      archivo: [_ficha('con-algo', turnos: 2)],
    );

    expect(estado.items.single.id, 'con-algo');
  });

  test('con varias, se van solo las vacías', () async {
    final estado = await alArrancar(
      abiertas: const ['vacia', 'con-algo'],
      archivo: [_ficha('vacia', turnos: 0), _ficha('con-algo', turnos: 3)],
    );

    expect([for (final item in estado.items) item.id], ['con-algo']);
    expect(
      estado.focusedId,
      'con-algo',
      reason: 'el foco no se queda huérfano',
    );
  });

  // Si el archivo no se deja leer no se cierra nada: perder una pestaña por no
  // poder mirar el disco es peor que dejarla puesta.
  test('con el archivo ilegible no se toca ninguna', () async {
    final guardadas = _Guardadas({
      'items': [
        {'id': 'vacia', 'folderPath': _carpeta},
      ],
      'focusedId': 'vacia',
    });
    final container = ProviderContainer(
      overrides: [
        conversationsDataSourceProvider.overrideWithValue(guardadas),
        localConversationStoreProvider.overrideWithValue(_ArchivoRoto()),
        workspaceControllerProvider.overrideWith(_Espacio.new),
      ],
    );
    addTearDown(container.dispose);

    container.read(conversationsProvider);
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(container.read(conversationsProvider).items, hasLength(1));
  });
}

class _ArchivoRoto implements LocalConversationStore {
  @override
  Future<List<ConversationSummary>> list(String folderPath) async =>
      throw StateError('el disco dijo que no');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

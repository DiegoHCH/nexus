import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';

/// Reabrir la app y encontrarse la conversación **entera**.
///
/// Lo que pasaba: al arrancar volvían las fichas de las conversaciones abiertas —la
/// lista se guarda— pero vacías, aunque los turnos estuvieran en disco desde el primer
/// encargo. Y eso es peor que perderlas: la ficha sigue ahí, con su nombre, invitando a
/// seguir una conversación de la que no se ve nada.

const _id = 'c1';
const _carpeta = '/Users/alguien/General';

class _Almacen implements LocalConversationStore {
  _Almacen(this.registros);

  final List<ConversationRecord> registros;
  var vecesQueSeLeyo = 0;

  @override
  Future<List<ConversationRecord>> list(String folderPath) async {
    vecesQueSeLeyo++;
    return registros.where((r) => r.folderPath == folderPath).toList();
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _AlmacenRoto implements LocalConversationStore {
  @override
  Future<List<ConversationRecord>> list(String folderPath) async =>
      throw StateError('disco ilegible');

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SinMemoria implements ConversationMemory {
  const _SinMemoria();
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory();
  @override
  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  }) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> forget(String folderPath) async {}
}

class _Lista implements ConversationsDataSource {
  _Lista(this.contenido);
  Map<String, dynamic> contenido;
  @override
  Future<Map<String, dynamic>> read() async => contenido;
  @override
  Future<void> write(Map<String, dynamic> json) async => contenido = json;
}

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [PairedFolder(path: _carpeta, modality: FolderModality.voice)],
    activePath: _carpeta,
  );
}

ConversationRecord _registro({
  String id = _id,
  List<ChatMessage> mensajes = const [
    ChatMessage(author: ChatAuthor.user, text: 'ordena la casa'),
    ChatMessage(author: ChatAuthor.nexus, text: 'ya está ordenada'),
  ],
}) => ConversationRecord(
  id: id,
  folderPath: _carpeta,
  startedAt: DateTime(2026, 8, 24, 8),
  messages: mensajes,
);

ProviderContainer _contenedor(LocalConversationStore almacen) {
  final c = ProviderContainer(
    overrides: [
      conversationFolderProvider(_id).overrideWithValue(_carpeta),
      conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
      workspaceControllerProvider.overrideWith(_Espacio.new),
      localConversationStoreProvider.overrideWithValue(almacen),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  // El contenedor arrastra providers que leen preferencias, y sin binding eso no es
  // «vacío»: lanza. Es la misma trampa de otra prueba de esta tanda — un fallo de
  // arnés que se disfraza del fallo que se está midiendo.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('al abrirla vuelve con lo que ya se había dicho', () async {
    final c = _contenedor(_Almacen([_registro()]));

    c.read(assistantControllerProvider(_id));
    // Una vuelta para que la lectura del disco termine: es asíncrona, y de eso
    // dependía que no se viera nada.
    await Future<void>.delayed(Duration.zero);

    final estado = c.read(assistantControllerProvider(_id));
    expect(estado.messages.map((m) => m.text), [
      'ordena la casa',
      'ya está ordenada',
    ]);
  });

  test('la de otra conversación no se cuela', () async {
    // Se busca por el id de **esta**, que es con el que se guardó — el archivo se
    // llama así. Traer la de al lado sería peor que no traer nada.
    final c = _contenedor(_Almacen([_registro(id: 'otra')]));

    c.read(assistantControllerProvider(_id));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(assistantControllerProvider(_id)).messages, isEmpty);
  });

  test('un disco ilegible no impide abrirla', () async {
    // Se sigue en blanco, que es lo que había antes de esto: lo que no puede pasar
    // es que la conversación no se abra.
    final c = _contenedor(_AlmacenRoto());

    c.read(assistantControllerProvider(_id));
    await Future<void>.delayed(Duration.zero);

    expect(c.read(assistantControllerProvider(_id)).messages, isEmpty);
  });
  test('una retomada del archivo tambien vuelve con su contenido', () async {
    // **El caso que mi primer arreglo no cubria, y el que importaba.** Al retomar del
    // historial, la pestaña adopta el id de ese registro para seguir escribiendo en el
    // en vez de crear otro. La recuperacion buscaba por el id de la conversacion, que
    // no existe como fichero — asi que la pestaña volvia vacia con sus turnos intactos
    // en disco. La prueba de antes usaba una conversacion cuyo id coincidia con su
    // registro: el camino facil.
    // Lo guardado al cerrar la app: la conversacion `c1` **escribiendo en**
    // `el-del-archivo`, que es lo que deja retomar una del historial.
    final c = ProviderContainer(
      overrides: [
        conversationFolderProvider(_id).overrideWithValue(_carpeta),
        conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
        workspaceControllerProvider.overrideWith(_Espacio.new),
        localConversationStoreProvider.overrideWithValue(
          _Almacen([_registro(id: 'el-del-archivo')]),
        ),
        conversationsDataSourceProvider.overrideWithValue(
          _Lista({
            'items': [
              {'id': _id, 'folderPath': _carpeta, 'recordId': 'el-del-archivo'},
            ],
            'focusedId': _id,
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(assistantControllerProvider(_id));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      c.read(assistantControllerProvider(_id)).messages.map((m) => m.text),
      ['ordena la casa', 'ya está ordenada'],
      reason: 'si busca por el id de la conversacion, la pestaña vuelve vacia',
    );
  });
}

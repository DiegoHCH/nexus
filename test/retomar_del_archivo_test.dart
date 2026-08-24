import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retomar una del archivo teniendo otra delante.
///
/// Lo que pasaba: la conversación elegida se abría **en la que ya tenías** y la
/// modificaba. Una conversación viva se guarda en el archivo desde su primer turno, así
/// que la de la lista puede ser exactamente la que estás mirando — y abrirla otra vez
/// creaba una segunda pestaña escribiendo en el mismo registro.

const _carpeta = '/Users/alguien/General';

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

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [PairedFolder(path: _carpeta, modality: FolderModality.voice)],
    activePath: _carpeta,
  );
}

ConversationRecord _registro(String id) => ConversationRecord(
  id: id,
  folderPath: _carpeta,
  startedAt: DateTime(2026, 8, 24, 8),
  messages: const [
    ChatMessage(author: ChatAuthor.user, text: 'ordena la casa'),
  ],
);

ProviderContainer _contenedor() {
  final c = ProviderContainer(
    overrides: [
      conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
      workspaceControllerProvider.overrideWith(_Espacio.new),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('la que ya está abierta se enfoca, no se duplica', () async {
    final c = _contenedor();
    final abierta = await c.read(conversationsProvider.notifier).open(_carpeta);
    // Esa pestaña adopta el registro, que es lo que hace al guardarse.
    c
        .read(assistantControllerProvider(abierta!).notifier)
        .resume(_registro('r1'));
    final otra = await c.read(conversationsProvider.notifier).open(_carpeta);

    // Con el foco en la otra, se retoma la del archivo que ya estaba abierta.
    c.read(conversationsProvider.notifier).focus(otra!);
    final resultado = await c.read(retomarDelArchivoProvider)(_registro('r1'));

    expect(resultado, RetomarResultado.yaEstaba);
    expect(c.read(conversationsProvider).items, hasLength(2));
    expect(
      c.read(conversationsProvider).focusedId,
      abierta,
      reason: 'se va a la suya en vez de escribir en la que estabas mirando',
    );
  });

  test('una que no está abierta se abre en pestaña nueva', () async {
    final c = _contenedor();
    final primera = await c.read(conversationsProvider.notifier).open(_carpeta);
    c
        .read(assistantControllerProvider(primera!).notifier)
        .resume(_registro('r1'));

    final resultado = await c.read(retomarDelArchivoProvider)(_registro('r2'));

    expect(resultado, RetomarResultado.enPestanaNueva);
    expect(c.read(conversationsProvider).items, hasLength(2));
    // Y la que ya tenías **no se toca**: era el fallo original.
    expect(
      c.read(assistantControllerProvider(primera).notifier).isShowing('r1'),
      isTrue,
    );
  });

  test('con el muelle lleno se dice, no se calla', () async {
    final c = _contenedor();
    for (var i = 0; i < Conversations.max; i++) {
      expect(
        await c.read(conversationsProvider.notifier).open(_carpeta),
        isNotNull,
      );
    }

    final resultado = await c.read(retomarDelArchivoProvider)(
      _registro('nueva'),
    );

    expect(resultado, RetomarResultado.noCabe);
  });

  test('caben seis, en columnas de tres', () {
    // El tope estuvo en tres por atención, y el uso lo corrigió: se dejan corriendo y
    // se vuelve a ellas. Seis y no siete por la rejilla — un número que no sea
    // múltiplo deja una columna coja.
    expect(Conversations.max, 6);
    expect(Conversations.max % Conversations.porColumna, 0);
  });
}

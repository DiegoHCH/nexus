import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nombrar la carpeta hablando y que el encargo caiga donde toca.
///
/// 🔴 **Es el 80 % del spike sin pagar su nudo.** Hoy hay que elegir la carpeta a
/// mano antes de hablar, y de ella cuelgan la cuenta, el modelo, los permisos y
/// el prompt. «En el front mobile, arregla el login» ya dice dónde.
///
/// Y la regla que manda: **nunca se trabaja en la carpeta que no era** — un
/// encargo en la equivocada puede escribir con la cuenta del trabajo en un repo
/// personal, y eso no se deshace pidiéndolo.
const _aqui = '/w/nexus';
const _alla = '/w/front-mobile-b2c';

class _Claude implements AskClaude {
  _Claude(this.dondeCayo, this.conversacion);

  final Map<String, List<String>> dondeCayo;
  final String conversacion;

  @override
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
    Future<RespuestaDePermiso> Function(PeticionDePermiso peticion)?
    alPedirPermiso,
  }) async* {
    (dondeCayo[conversacion] ??= []).add(instruction);
    yield const ClaudeTurnCompleted(result: 'ya está');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SinLlave implements GeminiImageKeyStore {
  const _SinLlave();
  @override
  Future<String?> read(String? perfil) async => null;
  @override
  Future<void> save(String? perfil, String key) async {}
  @override
  Future<void> clear(String? perfil) async {}
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

class _SinAlmacen implements LocalConversationStore {
  const _SinAlmacen();
  @override
  Future<void> save(ConversationRecord record) async {}
  @override
  Future<List<ConversationSummary>> list(String folderPath) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [
      PairedFolder(path: _aqui, modality: FolderModality.voice),
      PairedFolder(path: _alla, modality: FolderModality.voice),
    ],
    activePath: _aqui,
  );
}

class _Abiertas extends ConversationsController {
  _Abiertas(this._items);
  final List<Conversation> _items;
  @override
  Conversations build() =>
      Conversations(items: _items, focusedId: _items.first.id, cargado: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, List<String>> dondeCayo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dondeCayo = {};
  });

  ProviderContainer montar(List<Conversation> abiertas) {
    final container = ProviderContainer(
      overrides: [
        conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
        workspaceControllerProvider.overrideWith(_Espacio.new),
        localConversationStoreProvider.overrideWithValue(const _SinAlmacen()),
        geminiImageKeyStoreProvider.overrideWithValue(const _SinLlave()),
        conversationsProvider.overrideWith(() => _Abiertas(abiertas)),
        for (final c in abiertas) ...[
          conversationFolderProvider(c.id).overrideWithValue(c.folderPath),
          askClaudeProvider(c.id).overrideWithValue(_Claude(dondeCayo, c.id)),
        ],
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> asentar() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  const dosAbiertas = [
    Conversation(id: 'aqui', folderPath: _aqui),
    Conversation(id: 'alla', folderPath: _alla),
  ];

  test('sin nombrar carpeta, el encargo se queda donde se escribió', () async {
    final container = montar(dosAbiertas);

    await container
        .read(assistantControllerProvider('aqui').notifier)
        .submit('arregla el login');
    await asentar();

    expect(dondeCayo['aqui'], ['arregla el login']);
    expect(dondeCayo['alla'], isNull);
  });

  // 🔴 El caso del spike.
  test('nombrando otra, el encargo cae allí y sin la mención', () async {
    final container = montar(dosAbiertas);

    await container
        .read(assistantControllerProvider('aqui').notifier)
        .submit('en el front mobile b2c, arregla el login');
    await asentar();

    expect(dondeCayo['alla'], ['arregla el login']);
    expect(
      dondeCayo['aqui'],
      isNull,
      reason: 'trabajar en la carpeta que no era es lo que esto viene a evitar',
    );
  });

  // El foco es la única señal de que pasó algo: sin eso, se escribe en una
  // pestaña y el trabajo aparece en otra que no se está mirando.
  test('y el foco se va con él', () async {
    final container = montar(dosAbiertas);

    await container
        .read(assistantControllerProvider('aqui').notifier)
        .submit('en front-mobile-b2c corre las pruebas');
    await asentar();

    expect(container.read(conversationsProvider).focusedId, 'alla');
  });

  test('nombrando la de aquí, no se mueve y va sin la mención', () async {
    final container = montar(dosAbiertas);

    await container
        .read(assistantControllerProvider('aqui').notifier)
        .submit('en nexus, arregla el login');
    await asentar();

    expect(dondeCayo['aqui'], ['arregla el login']);
    expect(container.read(conversationsProvider).focusedId, 'aqui');
  });

  // Cambiar de sitio sin encargo es legítimo: se mueve el foco y ya.
  test('nombrarla sola solo cambia de sitio', () async {
    final container = montar(dosAbiertas);

    await container
        .read(assistantControllerProvider('aqui').notifier)
        .submit('vete al front mobile b2c');
    await asentar();

    expect(container.read(conversationsProvider).focusedId, 'alla');
    expect(dondeCayo['alla'], isNull);
  });

  // 🔴 De la carpeta salen la cuenta y los permisos: elegir por la persona es
  // justo lo que no se puede hacer.
  test('nombrando dos, no se hace nada y se dice', () async {
    final container = montar(dosAbiertas);

    await container
        .read(assistantControllerProvider('aqui').notifier)
        .submit('pasa lo de nexus al front mobile b2c');
    await asentar();

    expect(dondeCayo, isEmpty);
    final dicho = container
        .read(assistantControllerProvider('aqui'))
        .messages
        .last
        .text;
    expect(dicho, contains('front-mobile-b2c'));
    expect(dicho, contains('nexus'));
  });

  test('un reintento no se vuelve a enrutar', () async {
    final container = montar(dosAbiertas);

    await container
        .read(assistantControllerProvider('aqui').notifier)
        .submit('en el front mobile b2c, arregla el login', reintento: true);
    await asentar();

    expect(
      dondeCayo['aqui'],
      ['en el front mobile b2c, arregla el login'],
      reason:
          'un reintento ya se enrutó en su día: volver a hacerlo lo movería',
    );
  });
}

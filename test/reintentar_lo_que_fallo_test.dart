import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// «Si el trabajo falla tengo que copiar y pegar el mensaje de nuevo.»
///
/// La petición sigue escrita ahí, en su fila: volver a teclearla es trabajo que
/// la app puede ahorrarse. El botón solo aparece si falló — uno que esté
/// siempre enseña a no mirarlo.
const _id = 'c1';
const _carpeta = '/Users/alguien/General';

class _Claude implements AskClaude {
  _Claude();

  /// Falla la primera vez y contesta la segunda: es el caso del reintento.
  var vueltas = 0;
  final pedidos = <String>[];

  @override
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    vueltas++;
    pedidos.add(instruction);
    if (vueltas == 1) {
      yield const ClaudeFailed('se cayó el proceso');
      return;
    }
    yield const ClaudeTextDelta('ya está');
    yield const ClaudeTurnCompleted(result: 'ya está');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Sin llave de imágenes: `/imagen` falla enseguida, que es lo que hace falta
/// para medir la conversación sin salir a la red ni gastar un céntimo.
class _SinLlaveDeImagenes implements GeminiImageKeyStore {
  const _SinLlaveDeImagenes();
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
    folders: [PairedFolder(path: _carpeta, modality: FolderModality.voice)],
    activePath: _carpeta,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _Claude claude;

  /// `submit` **no espera al turno**: se suscribe al stream y vuelve. El fallo
  /// llega en otra vuelta del bucle de eventos, así que hay que dejarla pasar o
  /// se mide el estado de antes de que ocurriera nada.
  Future<void> vueltas() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ProviderContainer contenedor() {
    claude = _Claude();
    final c = ProviderContainer(
      overrides: [
        conversationFolderProvider(_id).overrideWithValue(_carpeta),
        conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
        workspaceControllerProvider.overrideWith(_Espacio.new),
        localConversationStoreProvider.overrideWithValue(const _SinAlmacen()),
        askClaudeProvider(_id).overrideWithValue(claude),
        geminiImageKeyStoreProvider.overrideWithValue(
          const _SinLlaveDeImagenes(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('lo que falla se marca en tu propio mensaje', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();

    final tuyo = c
        .read(assistantControllerProvider(_id))
        .messages
        .firstWhere((m) => m.author == ChatAuthor.user);
    expect(tuyo.fallo, isTrue);
  });

  test('y si va bien, no se marca nada', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    // La segunda vuelta de este doble contesta bien.
    claude.vueltas = 1;
    await controlador.submit('ordena la casa');
    await vueltas();

    expect(
      c.read(assistantControllerProvider(_id)).messages.any((m) => m.fallo),
      isFalse,
      reason: 'un botón que está siempre enseña a no mirarlo',
    );
  });

  // 🔴 El desvío de `/imagen` ocurre **antes** de donde `submit` decide no
  // reescribir el mensaje, así que sin traerse la bandera hasta el dibujo,
  // reintentar dejaba la misma petición dos veces con una sola respuesta.
  //
  // Y con las imágenes pasa más que con nada: el modelo se satura y contesta
  // «vuelve a intentarlo más tarde», que es una invitación a pulsar el botón.
  test('reintentar una imagen tampoco la escribe dos veces', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    // Sin llave de imágenes falla enseguida, que es lo que hace falta: lo que
    // se mide es la conversación, no la generación.
    await controlador.submit('/imagen un zorro');
    await vueltas();

    final mensajes = c.read(assistantControllerProvider(_id)).messages;
    final fallido = mensajes.firstWhere((m) => m.author == ChatAuthor.user);
    await controlador.reintentar(fallido);
    await vueltas();

    expect(
      c
          .read(assistantControllerProvider(_id))
          .messages
          .where((m) => m.author == ChatAuthor.user)
          .length,
      1,
      reason: 'la misma petición dos veces seguidas sobraría en la ventana',
    );
  });

  test('reintentar manda lo mismo sin escribirlo dos veces', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);
    await controlador.submit('ordena la casa');
    await vueltas();

    final fallido = c
        .read(assistantControllerProvider(_id))
        .messages
        .firstWhere((m) => m.fallo);
    await controlador.reintentar(fallido);
    await vueltas();

    final estado = c.read(assistantControllerProvider(_id));
    expect(claude.pedidos, ['ordena la casa', 'ordena la casa']);
    expect(
      estado.messages.where((m) => m.author == ChatAuthor.user).length,
      1,
      reason: 'la misma petición dos veces seguidas sobraría en la ventana',
    );
    expect(
      estado.messages.any((m) => m.fallo),
      isFalse,
      reason: 'el reintento salió bien: ya no hay nada que reintentar',
    );
  });
}

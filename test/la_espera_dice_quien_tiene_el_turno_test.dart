import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
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

/// A quién se culpa de la espera.
///
/// 🔴 **Se reportó dos veces como un cuelgue, con una sola conversación
/// abierta.** El aviso decía «Esperando a la otra conversación sobre esta
/// carpeta» y no había otra: quien tenía el turno era esta misma, comprimiéndose.
///
/// Comprimir es un turno entero de Claude sobre la carpeta, así que toma el
/// turno de la cola como cualquier encargo. Medido en la máquina: `flow init`
/// contestó, el contexto pasó del 85 %, salió la compresión, y el mensaje
/// siguiente se puso a esperar detrás de ella — tres procesos vivos en la
/// carpeta, uno el `/compact`.
///
/// La espera **no** se toca: dos turnos a la vez sobre la misma sesión pierden
/// uno. Lo que se arregla es el texto.
const _id = 'c1';
const _carpeta = '/Users/alguien/General';

/// 180k de una ventana de 200k son el 90 %, y el umbral de compresión es 85.
const _contextoLleno = 180000;

/// Un Claude de guion con la compresión **retenida**, que es lo que hace falta:
/// mientras `/compact` no termine, la conversación sigue teniendo el turno.
class _Claude implements AskClaude {
  final pedidos = <String>[];
  final compresionEnCurso = Completer<void>();

  /// Que el próximo encargo se encuentre la cola ocupada. Lo decide la prueba
  /// porque lo que se mide es **el texto del aviso**, no la cola —esa tiene sus
  /// propias pruebas en `el_turno_se_suelta_al_terminar_test.dart`—.
  var encolarElProximo = false;

  @override
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
    Future<RespuestaDePermiso> Function(PeticionDePermiso peticion)?
    alPedirPermiso,
  }) async* {
    pedidos.add(instruction);

    if (instruction == '/compact') {
      // Se queda dentro: el turno de la carpeta es suyo hasta que la prueba lo
      // suelte.
      await compresionEnCurso.future;
      yield const ClaudeTurnCompleted(result: '');
      return;
    }

    await Future<void>.delayed(Duration.zero);

    if (encolarElProximo) {
      encolarElProximo = false;
      yield const ClaudeQueued();
      return;
    }

    yield const ClaudeTextDelta('ya está');
    yield const ClaudeTurnCompleted(
      result: 'ya está',
      contextTokens: _contextoLleno,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

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
  Future<void> rememberPermissionMode(
    String f,
    String mode, {
    String? claudeProfile,
  }) async {}

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

  late _Claude claude;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    claude = _Claude();
    addTearDown(() {
      if (!claude.compresionEnCurso.isCompleted) {
        claude.compresionEnCurso.complete();
      }
    });
  });

  ProviderContainer montar() {
    final container = ProviderContainer(
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
    addTearDown(container.dispose);
    return container;
  }

  Future<void> asentar() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'esperar la propia compresión no se le echa a otra conversación',
    () async {
      final container = montar();
      final controlador = container.read(
        assistantControllerProvider(_id).notifier,
      );

      // Un turno que deja el contexto al 90 % → arranca la compresión, y ahí se
      // queda: el turno de la carpeta es suyo.
      await controlador.submit('lo primero');
      await asentar();
      expect(claude.pedidos, contains('/compact'));

      // Y ahora se escribe con la compresión en marcha.
      claude.encolarElProximo = true;
      await controlador.submit('listo, ahora sí está funcionando');
      await asentar();

      final strings = container.read(stringsProvider);
      final avisos = container
          .read(assistantControllerProvider(_id))
          .activity
          .map((paso) => paso.description);

      expect(
        avisos,
        contains(strings.waitingForOwnCompaction),
        reason:
            'quien tiene el turno es esta misma conversación: decirlo es la '
            'diferencia entre una espera y un cuelgue',
      );
      expect(
        avisos,
        isNot(contains(strings.waitingForOtherConversation)),
        reason: 'no hay otra conversación a la que culpar',
      );
    },
  );

  test('con otra conversación de por medio, el mensaje de siempre', () async {
    final container = montar();
    final controlador = container.read(
      assistantControllerProvider(_id).notifier,
    );

    // Sin compresión de esta conversación: quien tiene el turno es de fuera, y
    // ahí el mensaje original es la verdad. Esta es la mitad que evita
    // "arreglarlo" cambiando el texto para todos los casos.
    claude.encolarElProximo = true;
    await controlador.submit('lo primero');
    await asentar();

    final strings = container.read(stringsProvider);
    final avisos = container
        .read(assistantControllerProvider(_id))
        .activity
        .map((paso) => paso.description);

    expect(avisos, contains(strings.waitingForOtherConversation));
    expect(avisos, isNot(contains(strings.waitingForOwnCompaction)));
    expect(
      claude.pedidos,
      isNot(contains('/compact')),
      reason: 'sin turno no hay turno completado, así que no hay compresión',
    );
  });
}

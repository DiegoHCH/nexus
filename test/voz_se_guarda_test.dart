import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';
import 'package:nexus/features/assistant/domain/usecases/hold_voice_conversation.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/microfono.dart';

const conversationId = 'c1';
const folderPath = '/Users/alguien/General';

/// La sesión de voz, movida a mano desde la prueba.
///
/// Se sustituye `call()` entero, así que las piezas que recibe el padre no se
/// usan: van dobles vacíos, que es más honesto que fingir un micrófono.
class _Guionizada extends HoldVoiceConversation {
  _Guionizada()
    : super(
        _Nada(),
        _Nada(),
        _Nada(),
        AskClaude(
          _Nada(),
          (_) async => null,
          const _NoMemory(),
          FolderErrandQueue(),
          _Nada(),
        ),
        (_) {},
      );

  final _events = StreamController<VoiceEvent>.broadcast();

  void emit(VoiceEvent event) => _events.add(event);

  @override
  Stream<VoiceEvent> call() => _events.stream;
}

/// Nada de esto se llama: si algo lo llamara, la prueba lo diría a gritos en
/// vez de pasar por un camino que no quería probar.
class _Nada
    implements VoiceInput, VoiceGateway, AudioOutput, ClaudeBridge, StaysAwake {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no debía llamarse');
}

class _Store implements LocalConversationStore {
  final guardadas = <ConversationRecord>[];

  @override
  Future<void> save(ConversationRecord record) async => guardadas.add(record);

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoMemory implements ConversationMemory {
  const _NoMemory();
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

class _Workspace extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [PairedFolder(path: folderPath, modality: FolderModality.voice)],
    activePath: folderPath,
  );
}

void main() {
  // Terminar un turno avisa por un canal nativo, y sin binding el canal ni
  // siquiera puede lanzar `MissingPluginException` —que sí está atrapada—: se
  // queja de que no hay binding. Se inicializa aquí, que es donde está el
  // problema, en vez de ensanchar el `catch` de producción.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({ProviderContainer container, _Guionizada voz, _Store store}) montar() {
    final voz = _Guionizada();
    final store = _Store();
    final container = ProviderContainer(
      overrides: [
        conversationFolderProvider(
          conversationId,
        ).overrideWithValue(folderPath),
        conversationMemoryProvider.overrideWithValue(const _NoMemory()),
        workspaceControllerProvider.overrideWith(_Workspace.new),
        conMicrofono,
        holdVoiceConversationProvider(conversationId).overrideWithValue(voz),
        localConversationStoreProvider.overrideWithValue(store),
        // El destino externo —vault, Notion— se apaga: aquí se mira el
        // historial de la app, que es el que nunca debe depender de nada de
        // fuera.
        conversationArchiveProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, voz: voz, store: store);
  }

  test('una conversación hablada se guarda en el historial', () async {
    final m = montar();
    final controller = m.container.read(
      assistantControllerProvider(conversationId).notifier,
    );

    await controller.toggleVoice();
    await Future<void>.delayed(Duration.zero);

    // Un turno que contesta Gemini solo, sin pasar por Claude: es justo el que
    // desaparecía entero del historial, porque guardar colgaba del turno de
    // Claude y ahí no hay ninguno.
    m.voz
      ..emit(const VoiceUserTranscript('dime cómo funciona gitflow'))
      ..emit(const VoiceReplyTranscript('Gitflow es un modelo de ramas.'))
      ..emit(const VoiceTurnCompleted());
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(m.store.guardadas, isNotEmpty);
    expect(m.store.guardadas.last.folderPath, folderPath);
    expect(m.store.guardadas.last.messages, isNotEmpty);
  });

  test('un turno que resolvió Gemini solo no toca las cifras', () async {
    final m = montar();
    final controller = m.container.read(
      assistantControllerProvider(conversationId).notifier,
    );

    await controller.toggleVoice();
    await Future<void>.delayed(Duration.zero);

    m.voz
      ..emit(const VoiceUserTranscript('hola'))
      ..emit(const VoiceReplyTranscript('Hola, ¿en qué te ayudo?'))
      ..emit(const VoiceTurnCompleted());
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final estado = m.container.read(
      assistantControllerProvider(conversationId),
    );
    expect(m.store.guardadas, isNotEmpty, reason: 'guardarse, sí');
    expect(
      estado.meter.contextTokens,
      isNull,
      reason:
          'pero las cifras salen del turno de Claude, y aquí no hubo ninguno: '
          'inventar una medida sería peor que no darla',
    );
    expect(estado.meter.turnTokens, isNull);
  });

  test(
    'y el medidor de contexto recoge las cifras del turno de Claude',
    () async {
      final m = montar();
      final controller = m.container.read(
        assistantControllerProvider(conversationId).notifier,
      );

      await controller.toggleVoice();
      await Future<void>.delayed(Duration.zero);

      m.voz.emit(
        const VoiceToolFinished(
          ok: true,
          turnTokens: 1200,
          contextTokens: 63300,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final estado = m.container.read(
        assistantControllerProvider(conversationId),
      );
      expect(
        estado.meter.contextTokens,
        63300,
        reason:
            'hablando, el turno de Claude lo consume el caso de uso de voz: si '
            'las cifras no viajan en el evento, la ventana de contexto se queda '
            'en «Sin dato» toda la conversación',
      );
      expect(estado.meter.turnTokens, 1200);
    },
  );
}

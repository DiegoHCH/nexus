import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
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

/// Un almacén que se niega, como un disco lleno o un permiso retirado.
class _StoreRoto implements LocalConversationStore {
  @override
  Future<void> save(ConversationRecord record) async =>
      throw StateError('no hay sitio');

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Un destino externo que se niega: el vault que ya no está.
class _ArchivoRoto implements ConversationArchive {
  @override
  Future<void> save(ConversationRecord record) async =>
      throw StateError('el vault no existe');

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// Si archivar falla, **te enteras**.
//
// Los dos caminos —el historial de la app y el destino externo— solo hacían
// `debugPrint`. Caso de fallo: pones el archivo en un vault de Obsidian, el
// vault se renombra, y la conversación se pierde sin que la app diga nada. Te
// enteras el día que vas a buscar la nota, cuando ya no hay forma de
// recuperarla — y no se repite, porque la conversación ya terminó.
//
// Lo que se comprueba es que el aviso **diga dónde**: si el historial de la app
// la tiene, no se ha perdido nada y eso hay que decirlo; si no la tiene, hay que
// copiarla antes de cerrar. Son dos avisos distintos porque piden cosas
// distintas.
void main() {
  late _Guionizada voz;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    voz = _Guionizada();
  });

  /// El destino se deja en Obsidian a propósito: el aviso tiene que nombrarlo,
  /// y con «en ningún sitio» no habría nada externo que fallara.
  ProviderContainer montar({
    required LocalConversationStore store,
    required ConversationArchive? archivo,
  }) {
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
        conversationArchiveProvider.overrideWith((ref) async => archivo),
        archiveControllerProvider.overrideWith(
          () => _Destino(ArchiveDestination.obsidian),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String?> avisoTras(ProviderContainer container) async {
    final controller = container.read(
      assistantControllerProvider(conversationId).notifier,
    );
    await controller.toggleVoice();
    await Future<void>.delayed(Duration.zero);

    voz
      ..emit(const VoiceUserTranscript('resume lo que hicimos'))
      ..emit(const VoiceReplyTranscript('Hecho.'))
      ..emit(const VoiceTurnCompleted());
    await Future<void>.delayed(const Duration(milliseconds: 30));

    return container
        .read(assistantControllerProvider(conversationId))
        .errorMessage;
  }

  test(
    'si falla el destino externo, se dice cuál — y que está a salvo',
    () async {
      final container = montar(store: _Store(), archivo: _ArchivoRoto());
      final aviso = await avisoTras(container);

      final strings = container.read(stringsProvider);
      expect(aviso, strings.archiveFailedExternal(strings.archiveObsidian));
    },
  );

  test('si falla el historial de la app, avisa de copiarla', () async {
    // Este es el grave: la conversación no está en ningún sitio y al cerrarla se
    // va. El destino externo se apaga para aislar el caso.
    final container = montar(store: _StoreRoto(), archivo: null);
    final aviso = await avisoTras(container);

    expect(aviso, container.read(stringsProvider).archiveFailedLocal);
  });

  test('si fallan los dos, un solo aviso y el peor', () async {
    // Dos `errorMessage` seguidos se pisan: el segundo borraría el primero y el
    // usuario leería «está a salvo en el historial» justo cuando no lo está.
    final container = montar(store: _StoreRoto(), archivo: _ArchivoRoto());
    final aviso = await avisoTras(container);

    final strings = container.read(stringsProvider);
    expect(aviso, strings.archiveFailedBoth(strings.archiveObsidian));
    expect(
      aviso,
      isNot(strings.archiveFailedExternal(strings.archiveObsidian)),
    );
  });

  test('y cuando todo va bien no se inventa un aviso', () async {
    final container = montar(store: _Store(), archivo: null);
    expect(await avisoTras(container), isNull);
  });
}

/// El destino elegido en Ajustes, fijo.
class _Destino extends ArchiveController {
  _Destino(this._destination);

  final ArchiveDestination _destination;

  @override
  ArchiveSettings build() => ArchiveSettings(destination: _destination);
}

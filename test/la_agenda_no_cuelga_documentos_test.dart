import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/data/datasources/artifacts_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/correr_una_prueba.dart';
import 'package:nexus/features/assistant/domain/repositories/el_parte_del_dia.dart';
import 'package:nexus/features/assistant/domain/repositories/la_agenda_de_hoy.dart';
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
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/microfono.dart';

const conversationId = 'c1';
const folderPath = '/Users/alguien/General';
const cajon = '/Users/alguien/Documentos';

/// Preguntar la agenda **no cuelga un documento de la respuesta**.
///
/// 🔴 Se vio en pantalla: «¿qué reuniones tengo hoy?» y debajo de la respuesta,
/// un `resumen-atlas-credito-colateralizado.html` que no tenía nada que ver con
/// lo preguntado ni se había generado en ese turno.
///
/// La causa no fue la agenda, fue **anunciarla como un encargo**. Al emitir la
/// pareja de eventos de un encargo, quien escucha corre la cola de después de
/// uno —entre otras cosas, buscar el documento que salió—. Y como la marca de
/// «qué había antes» se toma sin esperarla y la agenda contesta al instante, la
/// comparación llegaba primero: sin marca, **toda** la carpeta cuenta como
/// recién salida y se cuelga el último.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({ProviderContainer container, _Guionizada voz}) montar() {
    final voz = _Guionizada();
    final container = ProviderContainer(
      overrides: [
        conversationFolderProvider(
          conversationId,
        ).overrideWithValue(folderPath),
        conversationMemoryProvider.overrideWithValue(const _NoMemory()),
        workspaceControllerProvider.overrideWith(_Workspace.new),
        conMicrofono,
        holdVoiceConversationProvider(conversationId).overrideWithValue(voz),
        localConversationStoreProvider.overrideWithValue(const _SinDisco()),
        conversationArchiveProvider.overrideWith((ref) async => null),
        // El cajón, con un documento viejo dentro. Es la pieza que hacía falta
        // para reproducirlo: sin nada en la carpeta no hay qué colgar mal.
        artifactsFolderProvider.overrideWith(_Cajon.new),
        artifactsDataSourceProvider.overrideWithValue(const _ConUnViejo()),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, voz: voz);
  }

  // Esta comprueba el resultado, y hay que decir qué **no** comprueba: la
  // carrera de verdad no se reproduce aquí. En la app quien la pierde es la
  // marca del repositorio, que se toma con `git` de por medio; en un arnés sin
  // repositorio `git` falla al instante y la marca gana siempre. Así que esto
  // vale como red de seguridad del resultado, y quien fija la causa es la
  // prueba de al lado —qué evento emite la agenda— más la de `hold_voice`.
  test('la respuesta sale sola, sin el documento viejo pegado', () async {
    final m = montar();
    await m.container
        .read(assistantControllerProvider(conversationId).notifier)
        .toggleVoice();
    await Future<void>.delayed(Duration.zero);

    m.voz
      ..emit(const VoiceUserTranscript('qué reuniones tengo hoy'))
      ..emit(const VoiceLookupStarted('La agenda de hoy'))
      ..emit(const VoiceReplyTranscript('Hoy tienes cinco reuniones.'))
      ..emit(const VoiceTurnCompleted());
    // De sobra para que corra cualquier cosa que se hubiera lanzado suelta.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final mensajes = m.container
        .read(assistantControllerProvider(conversationId))
        .messages;
    expect(
      mensajes.where((mensaje) => mensaje.documento != null),
      isEmpty,
      reason:
          'un documento que ya estaba en la carpeta no salió de este turno, y '
          'colgarlo de la respuesta lo presenta como que sí',
    );
  });

  test('mientras la mira, TRABAJANDO con su titular', () async {
    final m = montar();
    await m.container
        .read(assistantControllerProvider(conversationId).notifier)
        .toggleVoice();
    await Future<void>.delayed(Duration.zero);

    m.voz.emit(const VoiceLookupStarted('La agenda de hoy'));
    await Future<void>.delayed(Duration.zero);

    final hud = m.container.read(assistantControllerProvider(conversationId));
    expect(hud.orbState, NexusOrbState.think);
    expect(hud.subtitle, 'La agenda de hoy');
  });

  // 🔴 Y no entra en «lo que has pedido». Esa lista sirve para **repetir una
  // petición**, y «La agenda de hoy» no es nada que nadie escribiera: es el
  // titular que le puso la app.
  test('y no se apunta como algo que pediste', () async {
    final m = montar();
    await m.container
        .read(assistantControllerProvider(conversationId).notifier)
        .toggleVoice();
    await Future<void>.delayed(Duration.zero);

    m.voz.emit(const VoiceLookupStarted('La agenda de hoy'));
    await Future<void>.delayed(Duration.zero);

    expect(
      m.container.read(assistantControllerProvider(conversationId)).history,
      isEmpty,
    );
  });
}

/// El cajón de documentos, fijo.
class _Cajon extends ArtifactsFolder {
  @override
  String? build() => cajon;
}

/// Un documento que **ya estaba**: ni lo escribió este turno ni lo pidió nadie.
class _ConUnViejo implements ArtifactsDataSource {
  const _ConUnViejo();

  @override
  Future<List<Artifact>> list(
    String directory, {
    Set<String> cuentas = const {},
  }) async {
    return [
      Artifact(
        path: '$cajon/resumen-atlas-credito-colateralizado.html',
        name: 'resumen-atlas-credito-colateralizado.html',
        at: DateTime(2026, 8, 30),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

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
        const _SinPruebas(),
        const _SinParte(),
        const _SinAgenda(),
      );

  final _events = StreamController<VoiceEvent>.broadcast();

  void emit(VoiceEvent event) => _events.add(event);

  @override
  Stream<VoiceEvent> call() => _events.stream;
}

class _Nada
    implements VoiceInput, VoiceGateway, AudioOutput, ClaudeBridge, StaysAwake {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no debía llamarse');
}

class _SinPruebas implements CorrerUnaPrueba {
  const _SinPruebas();
  @override
  Future<String> loQuePidieron(String pedido) async => 'no';
}

class _SinParte implements ElParteDelDia {
  const _SinParte();
  @override
  Future<String?> instruccion() async => null;
  @override
  void yaEstaEscrito(String parte) {}
}

class _SinAgenda implements LaAgendaDeHoy {
  const _SinAgenda();
  @override
  Future<String?> deHoy() async => 'Hoy tienes cinco reuniones.';
}

class _SinDisco implements LocalConversationStore {
  const _SinDisco();
  @override
  Future<void> save(ConversationRecord record) async {}
  @override
  Future<List<ConversationSummary>> list(String folderPath) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

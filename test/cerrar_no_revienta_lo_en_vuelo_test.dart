import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/despacho.dart';
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

/// Cerrar una conversación **no puede reventar lo que quedó en vuelo**.
///
/// 🔴 Un `unawaited` que toca `state` o `ref` después de un `await` es un error
/// asíncrono sin dueño el día que el proveedor muere en ese hueco: leer `state`,
/// escribirlo y `ref.read` lanzan los tres `UnmountedRefException`, y desde
/// dentro de un `unawaited` no lo atrapa nadie.
///
/// Se comprueba con el hueco más largo de todos: `/compact` es un turno entero
/// de Claude —un minuto largo— y **no cuelga de `_subscription`**, así que el
/// `onDispose` que cancela las suscripciones no lo alcanza. Lo que corta el
/// resto de los caminos aquí no sirve.
///
/// La prueba no afirma nada con un `expect`: lo que comprueba es que **no llegue
/// un error**. Un `UnmountedRefException` en este hueco cae después de que la
/// prueba haya terminado, con «failed after test completion», que es como se vio
/// en CI la primera vez.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'comprimiendo el contexto, con la conversación cerrada en medio',
    () async {
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
          // El `/compact` que tarda: el hueco se abre en el `await` de dentro,
          // que es exactamente donde está el de verdad.
          askClaudeProvider(conversationId).overrideWithValue(
            AskClaude(
              _Nada(),
              (_) async {
                await Future<void>.delayed(const Duration(milliseconds: 60));
                return null;
              },
              const _NoMemory(),
              FolderErrandQueue(),
              _Nada(),
            ),
          ),
        ],
      );

      await container
          .read(assistantControllerProvider(conversationId).notifier)
          .toggleVoice();
      await Future<void>.delayed(Duration.zero);

      // 180k sobre la ventana de 200k son el 90 %: por encima del listón del
      // 85 % que dispara la compresión.
      voz.emit(
        const VoiceToolFinished(
          ok: true,
          model: 'claude-opus-5',
          contextTokens: 180000,
        ),
      );

      // Se cierra **con la compresión en vuelo**: los 60 ms no han pasado.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.dispose();

      // Y se le da tiempo a volver. Sin los guardias, lo que llega aquí es el
      // `UnmountedRefException` de `_onClaudeToolFinished` tocando `state`.
      //
      // **Hacen falta los dos**, y el detalle importa para quien vaya a tocar
      // esto: el primer lanzamiento cae dentro del `try` del propio método, así
      // que su `catch` se lo traga —y vuelve a llamar a `_onClaudeToolFinished`,
      // que lanza otra vez, ya sin nada que lo atrape—. Quitando solo uno de los
      // dos, esta prueba pasa: es la clase de verde que no significa nada.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    },
  );
}

/// La sesión de voz, movida a mano desde la prueba.
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
        const SinEnrutar(),
        () => null,
        () => true,
        () => null,
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
  Future<String?> deHoy() async => null;
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
  Future<void> rememberPermissionMode(
    String f,
    String mode, {
    String? claudeProfile,
  }) async {}

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

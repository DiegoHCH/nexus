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

/// Lo que la cabecera enseña mientras se trabaja para ti.
///
/// 🔴 **Nace de la agenda que no contestó nunca.** Se preguntó por voz qué
/// reuniones había, sonó «consulto tu agenda de hoy» y ahí acabó todo: en la
/// cabecera, DORMIDO. El cierre de la sesión se arregló aparte; esto es la otra
/// mitad, la que decide qué se lee mientras dura.
///
/// La regla que fijan estas pruebas: **mientras se investiga, TRABAJANDO; y la
/// voz sale cuando hay respuesta, no antes.** Soltar el estado en medio es
/// prometer un turno que no existe — quien está delante lee «te toca», habla, y
/// se pisa con la respuesta que venía en camino.
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
        // 🔴 **El archivo se corta aquí, y no por comodidad.** Terminar un
        // turno lo guarda, y sin sustituirlo el guardado real sale a buscar
        // `path_provider` —que en una prueba pura no existe— y se queda en
        // vuelo después del `dispose` del contenedor. En esta máquina ganaba la
        // carrera y en CI la perdía: dos pruebas rojas por un camino que no es
        // el que afirman. Es el mismo arnés que `voz_se_guarda_test.dart`.
        localConversationStoreProvider.overrideWithValue(const _SinDisco()),
        conversationArchiveProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, voz: voz);
  }

  Future<({ProviderContainer container, _Guionizada voz})> hablando() async {
    final m = montar();
    await m.container
        .read(assistantControllerProvider(conversationId).notifier)
        .toggleVoice();
    await Future<void>.delayed(Duration.zero);
    return m;
  }

  NexusOrbState orbe(ProviderContainer container) =>
      container.read(assistantControllerProvider(conversationId)).orbState;

  test('mientras se investiga, TRABAJANDO y con el titular puesto', () async {
    final m = await hablando();

    m.voz
      ..emit(const VoiceUserTranscript('qué reuniones tengo hoy'))
      ..emit(const VoiceToolStarted('La agenda de hoy'));
    await Future<void>.delayed(Duration.zero);

    expect(orbe(m.container), NexusOrbState.think);
    expect(
      m.container.read(assistantControllerProvider(conversationId)).subtitle,
      'La agenda de hoy',
      reason: 'treinta segundos sin nada en pantalla se leen como que no oyó',
    );
  });

  // 🔴 El hueco que quedaba. `VoiceToolFinished` solo dice que el resultado
  // viajó de vuelta al modelo, y al modelo le queda lo que más tarda: generar
  // la respuesta hablada, medido entre 5 y 11 s en esta máquina.
  test(
    'con el resultado ya entregado sigue TRABAJANDO, no ESCUCHANDO',
    () async {
      final m = await hablando();

      m.voz
        ..emit(const VoiceUserTranscript('qué reuniones tengo hoy'))
        ..emit(const VoiceToolStarted('La agenda de hoy'))
        ..emit(const VoiceToolFinished(ok: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        orbe(m.container),
        NexusOrbState.think,
        reason: 'decir «te toca» antes de hablar invita a pisar la respuesta',
      );
    },
  );

  test('y lo suelta cuando la voz empieza de verdad', () async {
    final m = await hablando();

    m.voz
      ..emit(const VoiceUserTranscript('qué reuniones tengo hoy'))
      ..emit(const VoiceToolStarted('La agenda de hoy'))
      ..emit(const VoiceToolFinished(ok: true))
      ..emit(const VoiceReplyTranscript('Hoy tienes una reunión a las diez.'));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(orbe(m.container), NexusOrbState.speak);
  });

  // Que se quede en trabajando no puede convertirse en quedarse ahí para
  // siempre: si la respuesta no llega nunca, la sesión se cierra sola —eso lo
  // decide el caso de uso— y al acabarse el flujo el orbe se duerme.
  test(
    'si la respuesta no llega nunca, el orbe se duerme al cerrarse',
    () async {
      final m = await hablando();

      m.voz
        ..emit(const VoiceToolStarted('La agenda de hoy'))
        ..emit(const VoiceToolFinished(ok: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(orbe(m.container), NexusOrbState.think);

      await m.voz.cerrar();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(orbe(m.container), NexusOrbState.sleep);
      expect(
        m.container
            .read(assistantControllerProvider(conversationId))
            .voiceActive,
        isFalse,
      );
    },
  );

  // Hablas tú antes de que conteste: entonces sí es escuchar, y lo dice.
  test('si hablas tú primero, pasa a escuchar', () async {
    final m = await hablando();

    m.voz
      ..emit(const VoiceToolStarted('La agenda de hoy'))
      ..emit(const VoiceToolFinished(ok: true))
      ..emit(const VoiceUserTranscript('déjalo, mejor otra cosa'));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(orbe(m.container), NexusOrbState.listen);
  });
}

/// La sesión de voz, movida a mano desde la prueba: se sustituye `call()`
/// entero, así que las piezas del padre van dobles vacíos.
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
      );

  final _events = StreamController<VoiceEvent>.broadcast();

  void emit(VoiceEvent event) => _events.add(event);

  /// La sesión se cierra sola por inactividad, y eso aquí es el flujo
  /// acabándose: es el camino que duerme el orbe.
  Future<void> cerrar() => _events.close();

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

/// El historial, sin disco: aquí se mira la cabecera, no lo que se guarda.
///
/// Contesta también a la lectura de apertura, y vacía. Dejándola en
/// `noSuchMethod` la prueba escupía «no se pudo leer lo dicho» en cada caso —un
/// aviso de verdad, de un fallo de mentira, que es la clase de ruido que enseña
/// a no leer la salida.
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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/microphone_access.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
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
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
class _Nada implements VoiceInput, VoiceGateway, AudioOutput, ClaudeBridge,
    StaysAwake {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no debía llamarse');
}

class _NoMemory implements ConversationMemory {
  const _NoMemory();
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async => const FolderMemory();
  @override
  Future<void> rememberSession(String folderPath, String sessionId, {String? claudeProfile}) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> forget(String folderPath) async {}
}

class _Workspace extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [
      PairedFolder(path: folderPath, modality: FolderModality.voice),
    ],
    activePath: folderPath,
  );
}



/// El permiso, en el estado que pida cada prueba.
class _Permiso implements MicrophoneAccess {
  const _Permiso(this._status);

  final MicrophoneStatus _status;

  @override
  Future<MicrophoneStatus> status() async => _status;
}

/// Un micrófono al que se le puede preguntar y que contesta lo que se le diga.
///
/// Solo se usa en el camino `notAsked`, que es el único donde la app **pide** el
/// permiso: ahí sí toca el diálogo del sistema.
class _Micro implements VoiceInput {
  _Micro(this.concede);

  final bool concede;
  var preguntado = false;

  @override
  Future<bool> hasPermission() async {
    preguntado = true;
    return concede;
  }

  @override
  Stream<AudioFrame> listen() => const Stream.empty();
}

// Nadie comprobaba el micrófono al abrir la voz.
//
// Caso de fallo: concedes el permiso, y meses después lo revocas en Ajustes del
// sistema —o lo revoca una actualización—. El orbe seguía respondiendo al clic,
// la sesión intentaba montarse y lo que salía era el error del motor de audio,
// que no dice a dónde ir a arreglarlo.
//
// Y hacen falta los tres estados: «denegado» se arregla en Ajustes del sistema y
// «sin decidir» se arregla preguntando. Tratarlos igual manda a la gente a buscar
// un interruptor que todavía no existe.
void main() {
  late _Guionizada voz;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    voz = _Guionizada();
  });

  ProviderContainer montar({
    required MicrophoneStatus permiso,
    VoiceInput? micro,
  }) {
    final container = ProviderContainer(
      overrides: [
        conversationFolderProvider(conversationId).overrideWithValue(folderPath),
        conversationMemoryProvider.overrideWithValue(const _NoMemory()),
        workspaceControllerProvider.overrideWith(_Workspace.new),
        holdVoiceConversationProvider(conversationId).overrideWithValue(voz),
        microphoneAccessProvider.overrideWithValue(_Permiso(permiso)),
        if (micro != null) voiceInputProvider.overrideWithValue(micro),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String?> avisoTrasPulsar(ProviderContainer container) async {
    await container
        .read(assistantControllerProvider(conversationId).notifier)
        .toggleVoice();
    await Future<void>.delayed(Duration.zero);
    return container.read(assistantControllerProvider(conversationId)).errorMessage;
  }

  test('denegado: no se abre, y se dice dónde se arregla', () async {
    final container = montar(permiso: MicrophoneStatus.denied);

    final aviso = await avisoTrasPulsar(container);

    expect(aviso, container.read(stringsProvider).microphoneBlocked);
    expect(
      container.read(assistantControllerProvider(conversationId)).voiceActive,
      isFalse,
    );
  });

  // Aparte y sobre los diccionarios, no sobre el aviso que salga: en las pruebas
  // el idioma del sistema es inglés, así que clavar «Ajustes» aquí haría fallar
  // la prueba por traducir bien. Ya pasó una vez con el guardia de i5.
  test('y el aviso dice a dónde ir, en los dos idiomas', () {
    // Un aviso que no dice dónde se arregla es la mitad de un aviso.
    expect(const NexusStringsEs().microphoneBlocked, contains('Ajustes'));
    expect(const NexusStringsEn().microphoneBlocked, contains('Settings'));
    for (final textos in [const NexusStringsEs(), const NexusStringsEn()]) {
      expect(textos.microphoneBlocked.toLowerCase(), contains('nexus'));
    }
  });

  test('sin decidir: se pregunta, no se rinde', () async {
    // El caso del primer arranque. Rendirse aquí mandaría a Ajustes del sistema a
    // buscar un permiso que nadie ha pedido todavía.
    final micro = _Micro(true);
    final container = montar(
      permiso: MicrophoneStatus.notAsked,
      micro: micro,
    );

    await avisoTrasPulsar(container);

    expect(micro.preguntado, isTrue, reason: 'se pidió el permiso');
    expect(
      container.read(assistantControllerProvider(conversationId)).errorMessage,
      isNot(container.read(stringsProvider).microphoneBlocked),
      reason: 'concedido: no hay nada que avisar',
    );
  });

  test('sin decidir y te dicen que no: se avisa igual', () async {
    final micro = _Micro(false);
    final container = montar(
      permiso: MicrophoneStatus.notAsked,
      micro: micro,
    );

    expect(
      await avisoTrasPulsar(container),
      container.read(stringsProvider).microphoneBlocked,
    );
    expect(micro.preguntado, isTrue);
  });

  test('concedido: el guardia no estorba', () async {
    final container = montar(permiso: MicrophoneStatus.granted);

    expect(
      await avisoTrasPulsar(container),
      isNot(container.read(stringsProvider).microphoneBlocked),
      reason: 'con permiso, este camino no dice nada',
    );
  });
}

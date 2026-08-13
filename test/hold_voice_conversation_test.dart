import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
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

/// El micrófono, callado: esta prueba va de lo que llega del servicio.
class _Mic implements VoiceInput {
  final _frames = StreamController<AudioFrame>();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<AudioFrame> listen() => _frames.stream;
}

/// La sesión de voz, movida a mano desde la prueba.
class _Session implements VoiceSession {
  final events_ = StreamController<VoiceEvent>.broadcast();
  final notes = <String>[];

  void emit(VoiceEvent event) => events_.add(event);

  @override
  Stream<VoiceEvent> get events => events_.stream;

  @override
  String? endReason;

  @override
  void sendAudio(Uint8List pcm) {}

  @override
  void sendSystemNote(String text) => notes.add(text);

  @override
  void sendToolResult({
    required String callId,
    required String name,
    required String result,
  }) {}

  @override
  Future<void> close() async {
    if (!events_.isClosed) await events_.close();
  }
}

class _Gateway implements VoiceGateway {
  _Gateway(this.session);
  final _Session session;

  @override
  Future<VoiceSession> connect() async => session;

  @override
  Future<VoiceSession> resume() async => session;
}

class _Speaker implements AudioOutput {
  @override
  Future<void> start() async {}
  @override
  void enqueue(Uint8List pcm) {}
  @override
  Future<void> discard() async {}
  @override
  Future<Duration> pending() async => Duration.zero;
  @override
  Future<void> stop() async {}
}

/// Anota el encargo que le llega. Es el testigo de la prueba: lo que Claude
/// recibe es lo que el usuario dijo, o no lo es.
///
/// Se guarda **sin la coletilla del idioma** que `AskClaude` le pega detrás:
/// aquí se mira qué se pidió, no cómo se envuelve.
class _Bridge implements ClaudeBridge {
  final _raw = <String>[];

  List<String> get asked =>
      [for (final instruction in _raw) instruction.split('\n\n').first];

  @override
  Stream<ClaudeEvent> ask(
    String instruction, {
    required String workingDirectory,
    required bool canEdit,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? claudeProfile,
    String? model,
    String? effort,
    String? artifactsFolder,
    List<String> disallowedTools = const [],
  }) async* {
    _raw.add(instruction);
    yield const ClaudeTurnCompleted(result: 'hecho');
  }
}

class _Memory implements ConversationMemory {
  @override
  Future<FolderMemory> read(String folderPath) async =>
      const FolderMemory(sessionId: null, prompts: []);
  @override
  Future<void> rememberSession(String folderPath, String id) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> forget(String folderPath) async {}
}

class _Awake implements StaysAwake {
  @override
  Future<void Function()> hold(String reason) async => () {};
}

AskClaude _askClaude(_Bridge bridge) => AskClaude(
  bridge,
  (_) async => (
    workingDirectory: '/repo',
    canEdit: false,
    extraDirectories: const <String>[],
    language: 'español',
    claudeProfile: null,
    model: null,
    effort: null,
    artifactsFolder: null,
    disallowedTools: const <String>[],
    constraintsNotice: null,
  ),
  _Memory(),
  FolderErrandQueue(),
  _Awake(),
);

void main() {
  test(
    'una frase larga llega en pedazos y va a Claude entera, no su cola (b11)',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      // Así llega de verdad: la transcripción de lo que dices viene por
      // trozos, no frase a frase. Lo dice el propio evento.
      for (final trozo in [
        'mira el repositorio ',
        'de nexus y dime ',
        'cuántos tests hay',
      ]) {
        session.emit(VoiceUserTranscript(trozo));
      }
      // El modelo contestó de memoria, sin llamar a la herramienta: aquí es
      // donde este código corrige y manda el encargo a Claude.
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, hasLength(1));
      expect(
        bridge.asked.single,
        'mira el repositorio de nexus y dime cuántos tests hay',
        reason:
            'antes se guardaba solo el último trozo, así que a Claude le '
            'llegaba «cuántos tests hay» — la frase cortada a mitad',
      );

      await subscription.cancel();
    },
  );

  test('el turno cierra la frase: la siguiente no arrastra la anterior', () async {
    final session = _Session();
    final bridge = _Bridge();
    final conversation = HoldVoiceConversation(
      _Mic(),
      _Gateway(session),
      _Speaker(),
      _askClaude(bridge),
      (_) {},
    );

    final subscription = conversation().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    session.emit(const VoiceUserTranscript('corre los tests'));
    session.emit(const VoiceTurnCompleted());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    session.emit(const VoiceUserTranscript('y ahora mira el historial'));
    session.emit(const VoiceTurnCompleted());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bridge.asked, [
      'corre los tests',
      'y ahora mira el historial',
    ]);

    await subscription.cancel();
  });

  test(
    'un saludo suelto sigue sin ir a Claude, aunque ahora se acumule',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('hola'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, isEmpty);

      await subscription.cancel();
    },
  );
}

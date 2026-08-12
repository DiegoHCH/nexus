import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// El pegamento entre los dos modelos y la pantalla: traduce cada
/// [ClaudeEvent] y cada [VoiceEvent] al mismo [AssistantHudState] que el orbe,
/// el horizonte y la franja de subtítulos escuchan.
///
/// Los dos caminos comparten estado a propósito: para quien mira, hablar y
/// escribir son la misma conversación, aunque por dentro uno sea un proceso
/// y el otro un socket.
class AssistantController extends Notifier<AssistantHudState> {
  StreamSubscription<ClaudeEvent>? _subscription;
  StreamSubscription<VoiceEvent>? _voiceSubscription;

  /// Lo que va diciendo el usuario y lo que va respondiendo el modelo, por
  /// separado: la franja muestra uno u otro según quién tenga el turno.
  final _heard = StringBuffer();
  final _reply = StringBuffer();

  @override
  AssistantHudState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _voiceSubscription?.cancel();
    });
    return const AssistantHudState();
  }

  Future<void> submit(String instruction) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return;

    await _subscription?.cancel();
    final buffer = StringBuffer();
    state = const AssistantHudState(orbState: NexusOrbState.think, isStreaming: true);

    final ask = ref.read(askClaudeProvider);
    _subscription = ask(trimmed).listen(
      (event) => switch (event) {
        ClaudeSessionStarted() => null,
        ClaudeTextDelta() => _onTextDelta(buffer, event),
        ClaudeTurnCompleted() => _onTurnCompleted(),
        ClaudeFailed() => _onFailed(event.message),
      },
      onError: (Object error) => _onFailed(error.toString()),
    );
  }

  void _onTextDelta(StringBuffer buffer, ClaudeTextDelta event) {
    buffer.write(event.text);
    state = state.copyWith(orbState: NexusOrbState.speak, subtitle: buffer.toString(), isStreaming: true);
  }

  void _onTurnCompleted() {
    state = state.copyWith(orbState: NexusOrbState.sleep, isStreaming: false);
  }

  void _onFailed(String message) {
    state = state.copyWith(orbState: NexusOrbState.sleep, isStreaming: false, errorMessage: message);
  }

  /// Mientras no hay sesión de voz, el campo de texto enfocado es la señal
  /// más cercana a "te estoy escuchando" que hay — solo mientras no haya
  /// nada en curso.
  void setListening(bool isListening) {
    if (state.voiceActive) return;
    final idle = state.orbState == NexusOrbState.sleep || state.orbState == NexusOrbState.listen;
    if (!idle) return;
    state = state.copyWith(orbState: isListening ? NexusOrbState.listen : NexusOrbState.sleep);
  }

  /// Abre o cierra la conversación por voz. Es un interruptor y no dos
  /// métodos porque el mando en la interfaz es uno solo: el orbe.
  Future<void> toggleVoice() async {
    if (state.voiceActive) {
      await stopVoice();
      return;
    }

    _heard.clear();
    _reply.clear();
    state = const AssistantHudState(orbState: NexusOrbState.think, voiceActive: true);

    final conversation = ref.read(holdVoiceConversationProvider);
    _voiceSubscription = conversation().listen(
      (event) => switch (event) {
        VoiceSessionReady() => _onVoiceReady(),
        VoiceUserTranscript() => _onHeard(event.text),
        VoiceReplyTranscript() => _onReply(event.text),
        VoiceInterrupted() => _onInterrupted(),
        VoiceTurnCompleted() => _onVoiceTurnCompleted(),
        VoiceSessionFailed() => unawaited(_onVoiceFailed(event.message)),
        // El audio no llega hasta aquí: lo reproduce el caso de uso. La
        // interfaz solo necesita el texto y el estado.
        VoiceReplyAudio() => null,
      },
      onError: (Object error) => unawaited(_onVoiceFailed(error.toString())),
      onDone: () => state = state.copyWith(voiceActive: false, orbState: NexusOrbState.sleep),
    );
  }

  Future<void> stopVoice() async {
    await _voiceSubscription?.cancel();
    _voiceSubscription = null;
    state = state.copyWith(
      voiceActive: false,
      orbState: NexusOrbState.sleep,
      isStreaming: false,
    );
  }

  void _onVoiceReady() {
    state = state.copyWith(orbState: NexusOrbState.listen, subtitle: '');
  }

  void _onHeard(String text) {
    // Si el usuario vuelve a hablar, lo anterior deja de ser el turno actual.
    if (_reply.isNotEmpty) {
      _reply.clear();
      _heard.clear();
    }
    _heard.write(text);
    state = state.copyWith(
      orbState: NexusOrbState.listen,
      subtitle: _heard.toString(),
      isStreaming: true,
    );
  }

  void _onReply(String text) {
    _reply.write(text);
    state = state.copyWith(
      orbState: NexusOrbState.speak,
      subtitle: _reply.toString(),
      isStreaming: true,
    );
  }

  void _onInterrupted() {
    _reply.clear();
    state = state.copyWith(orbState: NexusOrbState.listen, isStreaming: false);
  }

  void _onVoiceTurnCompleted() {
    _heard.clear();
    _reply.clear();
    state = state.copyWith(orbState: NexusOrbState.listen, isStreaming: false);
  }

  Future<void> _onVoiceFailed(String message) async {
    await _voiceSubscription?.cancel();
    _voiceSubscription = null;
    state = state.copyWith(
      voiceActive: false,
      orbState: NexusOrbState.sleep,
      isStreaming: false,
      errorMessage: message,
    );
  }
}

final assistantControllerProvider = NotifierProvider<AssistantController, AssistantHudState>(
  AssistantController.new,
);

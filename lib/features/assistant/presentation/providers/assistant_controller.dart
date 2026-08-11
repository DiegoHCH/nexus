import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// El pegamento entre el bridge y la pantalla: manda una instrucción, y va
/// traduciendo cada [ClaudeEvent] en un [AssistantHudState] que el orbe, el
/// horizonte y la franja de subtítulos escuchan.
class AssistantController extends Notifier<AssistantHudState> {
  StreamSubscription<ClaudeEvent>? _subscription;

  @override
  AssistantHudState build() {
    ref.onDispose(() => _subscription?.cancel());
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

  /// Sin voz todavía (Fase 2), el campo de texto enfocado es la señal más
  /// cercana a "te estoy escuchando" que hay — solo mientras no hay nada
  /// en curso.
  void setListening(bool isListening) {
    final idle = state.orbState == NexusOrbState.sleep || state.orbState == NexusOrbState.listen;
    if (!idle) return;
    state = state.copyWith(orbState: isListening ? NexusOrbState.listen : NexusOrbState.sleep);
  }
}

final assistantControllerProvider = NotifierProvider<AssistantController, AssistantHudState>(
  AssistantController.new,
);

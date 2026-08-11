import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// Todo lo que necesita pintar la pantalla principal: el estado del orbe y
/// el horizonte, el texto de la franja de subtítulos, y si el último turno
/// falló.
@immutable
class AssistantHudState {
  const AssistantHudState({
    this.orbState = NexusOrbState.sleep,
    this.subtitle = '',
    this.isStreaming = false,
    this.errorMessage,
  });

  final NexusOrbState orbState;
  final String subtitle;

  /// Claude sigue generando texto: la franja muestra el cursor parpadeando.
  final bool isStreaming;

  final String? errorMessage;

  AssistantHudState copyWith({
    NexusOrbState? orbState,
    String? subtitle,
    bool? isStreaming,
    Object? errorMessage = _unset,
  }) {
    return AssistantHudState(
      orbState: orbState ?? this.orbState,
      subtitle: subtitle ?? this.subtitle,
      isStreaming: isStreaming ?? this.isStreaming,
      errorMessage: errorMessage == _unset ? this.errorMessage : errorMessage as String?,
    );
  }
}

const _unset = Object();

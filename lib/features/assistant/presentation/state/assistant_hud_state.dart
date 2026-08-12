import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';

/// Una acción de Claude, para la columna «Ahora mismo».
@immutable
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.description,
    required this.writes,
    this.detail,
    this.output,
    this.done = false,
    this.parentId,
  });

  final String id;
  final String description;
  final bool writes;
  final bool done;

  /// La delegación de la que cuelga este paso, si lo dio un subagente.
  final String? parentId;

  /// El comando o la ruta completos, sin recortar: la línea de la columna va
  /// abreviada para leerse de un vistazo, esto es para cuando quieres saber
  /// exactamente qué se ejecutó.
  final String? detail;

  /// Lo que devolvió la herramienta, ya recortado en la capa de datos.
  final String? output;

  /// Si hay algo que enseñar al desplegar. Sin esto, la fila sería un botón
  /// que abre un hueco vacío.
  bool get hasDetail =>
      (detail?.isNotEmpty ?? false) || (output?.isNotEmpty ?? false);

  ActivityItem asDone({String? output}) => ActivityItem(
    id: id,
    description: description,
    writes: writes,
    detail: detail,
    output: output ?? this.output,
    done: true,
    parentId: parentId,
  );
}

/// Todo lo que necesita pintar la pantalla principal: el estado del orbe y
/// el horizonte, el texto de la franja de subtítulos, y si el último turno
/// falló.
@immutable
class AssistantHudState {
  const AssistantHudState({
    this.orbState = NexusOrbState.sleep,
    this.subtitle = '',
    this.isStreaming = false,
    this.voiceActive = false,
    this.activity = const [],
    this.messages = const [],
    this.history = const [],
    this.meter = const SessionMeter(),
    this.errorMessage,
  });

  final NexusOrbState orbState;
  final String subtitle;

  /// Claude sigue generando texto: la franja muestra el cursor parpadeando.
  final bool isStreaming;

  /// Hay una sesión de voz abierta — el micrófono está saliendo hacia Google.
  /// La interfaz lo muestra siempre: que esto sea invisible es justo lo que
  /// no puede pasar.
  final bool voiceActive;

  /// Lo que Claude ha ido haciendo en este turno, en orden. Se vacía al
  /// empezar uno nuevo: es «ahora mismo», no un historial.
  final List<ActivityItem> activity;

  /// La conversación entera, en orden: lo pedido y lo respondido, por voz o
  /// por teclado.
  final List<ChatMessage> messages;

  /// Lo que se le pidió antes en esta sesión, de lo más reciente hacia atrás.
  /// El diseño lo llama «Antes» y lo deja accesible pero no protagonista: son
  /// dos líneas en gris, no una lista de chat.
  final List<String> history;

  /// Modelo, tokens y contexto: los datos de la esquina superior derecha.
  final SessionMeter meter;

  final String? errorMessage;

  AssistantHudState copyWith({
    NexusOrbState? orbState,
    String? subtitle,
    bool? isStreaming,
    bool? voiceActive,
    List<ActivityItem>? activity,
    List<ChatMessage>? messages,
    List<String>? history,
    SessionMeter? meter,
    Object? errorMessage = _unset,
  }) {
    return AssistantHudState(
      orbState: orbState ?? this.orbState,
      subtitle: subtitle ?? this.subtitle,
      isStreaming: isStreaming ?? this.isStreaming,
      voiceActive: voiceActive ?? this.voiceActive,
      activity: activity ?? this.activity,
      messages: messages ?? this.messages,
      history: history ?? this.history,
      meter: meter ?? this.meter,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _unset = Object();

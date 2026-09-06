import 'package:flutter/foundation.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';

/// Una acción de Claude, para la columna «Ahora mismo».
@immutable
class ActivityItem {
  ActivityItem({
    required this.id,
    required this.description,
    required this.writes,
    this.detail,
    this.output,
    this.done = false,
    this.parentId,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final String id;
  final String description;
  final bool writes;
  final bool done;

  /// La delegación de la que cuelga este paso, si lo dio un subagente.
  final String? parentId;

  /// Cuándo empezó, para poder decir cuánto lleva. Un comando de cuatro minutos
  /// y uno colgado se ven igual mirando una línea quieta; el contador es lo que
  /// los separa sin tener que adivinar.
  final DateTime startedAt;

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
    startedAt: startedAt,
  );

  /// Para guardarlo con la conversación.
  ///
  /// **Se guarda o se pierde**, que es la lección que ya dejaron los cambios de
  /// cada turno: la actividad vivía solo en memoria y se borra al empezar el
  /// encargo siguiente, así que «qué hizo aquella vez» no tenía respuesta ni
  /// bajando por la conversación, mucho menos al día siguiente.
  ///
  /// Las claves van en español como las del resto del registro. `done` no se
  /// escribe: lo que se guarda ya terminó, y leerlo como terminado es lo
  /// correcto aunque el encargo se cortara a la mitad — un paso que quedó a
  /// medias no va a seguir corriendo mañana.
  Map<String, dynamic> toJson() => {
    'id': id,
    'que': description,
    if (writes) 'escribe': true,
    if (parentId != null) 'padre': parentId,
    'desde': startedAt.toIso8601String(),
    if (detail != null) 'detalle': detail,
    if (output != null) 'devolvio': output,
  };

  static ActivityItem? fromJson(Object? crudo) {
    if (crudo is! Map<String, dynamic>) return null;
    final id = crudo['id'];
    final que = crudo['que'];
    if (id is! String || que is! String) return null;
    return ActivityItem(
      id: id,
      description: que,
      writes: crudo['escribe'] == true,
      parentId: crudo['padre'] as String?,
      startedAt: DateTime.tryParse(crudo['desde'] as String? ?? ''),
      detail: crudo['detalle'] as String?,
      output: crudo['devolvio'] as String?,
      done: true,
    );
  }
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
    this.laSesionCaduco = false,
    this.notice,
    this.puedeEmpezarDeCero = false,
    this.changes,
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

  /// El fallo de arriba es una sesión caducada, y por eso se puede ofrecer
  /// entrar desde aquí.
  ///
  /// Va como bandera y no se deduce del texto: [errorMessage] ya viene
  /// traducido, así que para reconocerlo habría que buscar palabras en un
  /// idioma que puede ser cualquiera de los dos. La señal se toma donde
  /// todavía existe —la salida cruda del CLI— y se guarda.
  final bool laSesionCaduco;

  /// Algo que conviene saber y que **no es un fallo**: hoy, que los archivos de
  /// reglas del repositorio no son los mismos que la última vez.
  ///
  /// Va aparte de [errorMessage] y no reusa su hueco porque no es lo mismo:
  /// pintarlo en rojo diría que algo se rompió, y lo que pasa es que algo
  /// cambió. Y porque los dos pueden coincidir — un encargo puede fallar
  /// justo el día que cambiaron las reglas.
  final String? notice;

  /// Si el aviso de arriba se puede resolver **desde el aviso**: es el de
  /// «continúo donde quedó la última conversación de esta carpeta», y su salida
  /// es empezar de cero. Un botón que a veces está y a veces no es más honesto
  /// que uno permanente que casi nunca sirve — el mismo criterio que ya sigue el
  /// aviso de la sesión caducada.
  final bool puedeEmpezarDeCero;

  /// Lo que **este turno** dejó tocado en el repositorio, si tocó algo.
  ///
  /// De este turno y no de la conversación: acumular los cambios haría que el
  /// quinto encargo enseñara también los cuatro anteriores, y entonces revisar
  /// «qué acaba de hacer» sería buscar una aguja en lo que ya diste por bueno.
  final GitChanges? changes;

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
    bool? laSesionCaduco,
    Object? notice = _unset,
    bool? puedeEmpezarDeCero,
    Object? changes = _unset,
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
      laSesionCaduco: laSesionCaduco ?? this.laSesionCaduco,
      notice: notice == _unset ? this.notice : notice as String?,
      puedeEmpezarDeCero: puedeEmpezarDeCero ?? this.puedeEmpezarDeCero,
      changes: changes == _unset ? this.changes : changes as GitChanges?,
    );
  }
}

const _unset = Object();

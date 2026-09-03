import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// Quién habla en una línea de la conversación.
enum ChatAuthor { user, nexus }

/// Qué se contestó a una petición de permiso.
///
/// `null` en el mensaje significa que **sigue esperando**, y esa es la
/// diferencia que pinta los botones o los quita.
enum DecisionDePermiso {
  concedido,
  concedidoTodo,
  denegado,

  /// Nadie contestó: el encargo se detuvo o la conversación se cerró con la
  /// pregunta en pie. Se distingue de [denegado] porque no fue una decisión.
  cancelado,
}

extension DecisionDePermisoJson on DecisionDePermiso {
  /// La decisión guardada, o `null` si no hay ninguna que leer.
  ///
  /// Tolerante a propósito, como [ActivityItem.fromJson]: un nombre que no
  /// conocemos —porque lo escribió una versión con una salida más— vale menos
  /// que el turno donde está, así que se descarta él y no la conversación.
  static DecisionDePermiso? deJson(Object? crudo) {
    if (crudo is! String) return null;
    for (final decision in DecisionDePermiso.values) {
      if (decision.name == crudo) return decision;
    }
    return null;
  }
}

/// Un turno de la conversación, venga de la voz o del teclado.
///
/// Los dos caminos producen lo mismo a propósito: para quien mira, hablar y
/// escribir son la misma conversación, y verlas en listas distintas obligaría
/// a recordar por dónde entró cada cosa.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.author,
    required this.text,
    this.spoken = false,
    this.streaming = false,
    this.attachments = const [],
    this.respondeA,
    this.cambios,
    this.documento,
    this.esElParte = false,
    this.actividad = const [],
    this.fallo = false,
    this.permiso,
    this.decision,
  });

  final ChatAuthor author;
  final String text;

  /// Lo que **este** encargo dejó tocado, si tocó algo.
  ///
  /// Va en el mensaje y no solo en el estado de la pantalla, que es donde
  /// vivía: así, al subir por la conversación, cada turno conserva lo suyo. El
  /// estado solo guardaba el último, y entonces el segundo encargo borraba de
  /// la vista lo que había hecho el primero.
  final GitChanges? cambios;

  /// El documento que este encargo creó, si creó alguno.
  final String? documento;

  /// Los pasos que dio este encargo: qué leyó, qué corrió, qué escribió.
  ///
  /// Cuelgan del mensaje por el mismo motivo que [cambios], y con una urgencia
  /// más: la lista de la pantalla **se vacía al empezar el encargo siguiente**,
  /// así que sin esto lo que hizo el primero desaparecía en cuanto pedías la
  /// segunda cosa — no hacía falta ni cerrar la app.
  final List<ActivityItem> actividad;

  /// Esta respuesta es el parte del día, así que se le puede mandar a Slack.
  ///
  /// Se marca el mensaje en vez de ofrecer «mandar a Slack» en todos: un botón
  /// de enviar en cada respuesta invita a mandar cualquier cosa por una puerta
  /// que existe para una sola.
  final bool esElParte;

  /// El encargo que salió de este mensaje **no llegó a hacerse**.
  ///
  /// Va en el mensaje y no en el estado de la pantalla porque lo que se ofrece
  /// es reintentar **esto**, no «lo último»: si mientras tanto pediste otra
  /// cosa, un aviso suelto ya no sabría a qué se refería.
  ///
  /// Solo lo lleva el tuyo. Un fallo no produce respuesta que marcar, y lo que
  /// se reintenta es la petición.
  final bool fallo;

  /// Lo que Claude pide permiso para hacer en este punto de la conversación.
  ///
  /// **La pregunta es un turno y no una ventana**, que es lo que se pidió: se
  /// lee donde se está leyendo todo lo demás, se puede subir a mirar qué se
  /// autorizó y no tapa la pantalla. El precio es que se puede ignorar —una
  /// modal no—, y por eso mientras haya una sin contestar la franja lo dice:
  /// un encargo detenido esperando y uno colgado se ven igual.
  ///
  /// Solo lo llevan los mensajes vivos. Al releer una conversación del disco
  /// esto viene `null` y queda el texto, que es lo correcto: la pregunta ya no
  /// se puede contestar y ofrecer botones sería mentir.
  final PeticionDePermiso? permiso;

  /// Qué se contestó, o `null` si sigue esperando.
  final DecisionDePermiso? decision;

  /// Hay una pregunta en pie en este mensaje.
  bool get esperaPermiso => permiso != null && decision == null;

  /// Llegó por voz. Se marca porque un texto transcrito no es lo mismo que uno
  /// escrito: si la transcripción se equivocó, saber que venía del micrófono
  /// explica el disparate.
  final bool spoken;

  /// Todavía se está escribiendo: la interfaz le pone el cursor.
  final bool streaming;

  /// Las rutas que acompañaban a esta petición.
  ///
  /// Van **aparte del texto** a propósito. Antes se pegaban dentro del mensaje
  /// —«Archivos adjuntos:» y la ruta completa debajo— porque eso es lo que
  /// necesita Claude, y la conversación acababa enseñando rutas absolutas en
  /// vez del archivo. Son dos cosas distintas: lo que se le manda al modelo y
  /// lo que se le enseña a quien mira. Guardándolas aquí, la vista puede pintar
  /// la misma miniatura que ya se veía en la caja al adjuntarlo.
  final List<String> attachments;

  /// La pregunta a la que contesta este mensaje, **cuando no es la de justo
  /// arriba**.
  ///
  /// 🔴 **Solo lo llevan las respuestas a lo que esperó turno.** En un
  /// intercambio normal la respuesta va pegada a su pregunta y citarla sería
  /// ruido: se lee el orden y ya está. Pero al encolar, escribes tres cosas
  /// seguidas y las tres respuestas llegan después, así que el orden deja de
  /// decir a cuál contesta cada una — que es justo lo que la cola introdujo y
  /// hay que devolver.
  ///
  /// Se guarda **el texto** y no un identificador porque tiene que sobrevivir a
  /// guardar y releer la conversación desde el disco, donde los mensajes no
  /// tienen identidad propia.
  final String? respondeA;

  ChatMessage copyWith({
    String? text,
    bool? streaming,
    GitChanges? cambios,
    String? documento,
    bool? esElParte,
    List<ActivityItem>? actividad,
    bool? fallo,
    DecisionDePermiso? decision,
  }) => ChatMessage(
    author: author,
    text: text ?? this.text,
    spoken: spoken,
    streaming: streaming ?? this.streaming,
    attachments: attachments,
    cambios: cambios ?? this.cambios,
    documento: documento ?? this.documento,
    esElParte: esElParte ?? this.esElParte,
    actividad: actividad ?? this.actividad,
    fallo: fallo ?? this.fallo,
    respondeA: respondeA,
    permiso: permiso,
    decision: decision ?? this.decision,
  );

  /// Un mensaje que solo trae adjuntos **no está vacío**: soltar un archivo y
  /// dar a enviar es un gesto legítimo, y borrarlo de la vista por no tener
  /// texto dejaría la conversación sin la mitad de lo que pasó.
  /// Y uno que trae una pregunta de permiso tampoco: lo que hay que mirar son
  /// los botones, no el texto.
  bool get isEmpty =>
      text.trim().isEmpty && attachments.isEmpty && permiso == null;
}

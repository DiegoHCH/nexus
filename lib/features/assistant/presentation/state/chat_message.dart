import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// Quién habla en una línea de la conversación.
enum ChatAuthor { user, nexus }

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
  );

  /// Un mensaje que solo trae adjuntos **no está vacío**: soltar un archivo y
  /// dar a enviar es un gesto legítimo, y borrarlo de la vista por no tener
  /// texto dejaría la conversación sin la mitad de lo que pasó.
  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
}

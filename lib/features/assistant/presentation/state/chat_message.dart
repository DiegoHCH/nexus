import 'package:flutter/foundation.dart';
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
    this.cambios,
    this.documento,
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

  ChatMessage copyWith({
    String? text,
    bool? streaming,
    GitChanges? cambios,
    String? documento,
  }) => ChatMessage(
    author: author,
    text: text ?? this.text,
    spoken: spoken,
    streaming: streaming ?? this.streaming,
    attachments: attachments,
    cambios: cambios ?? this.cambios,
    documento: documento ?? this.documento,
  );

  /// Un mensaje que solo trae adjuntos **no está vacío**: soltar un archivo y
  /// dar a enviar es un gesto legítimo, y borrarlo de la vista por no tener
  /// texto dejaría la conversación sin la mitad de lo que pasó.
  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
}

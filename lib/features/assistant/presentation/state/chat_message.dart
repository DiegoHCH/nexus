import 'package:flutter/foundation.dart';

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
  });

  final ChatAuthor author;
  final String text;

  /// Llegó por voz. Se marca porque un texto transcrito no es lo mismo que uno
  /// escrito: si la transcripción se equivocó, saber que venía del micrófono
  /// explica el disparate.
  final bool spoken;

  /// Todavía se está escribiendo: la interfaz le pone el cursor.
  final bool streaming;

  ChatMessage copyWith({String? text, bool? streaming}) => ChatMessage(
    author: author,
    text: text ?? this.text,
    spoken: spoken,
    streaming: streaming ?? this.streaming,
  );

  bool get isEmpty => text.trim().isEmpty;
}

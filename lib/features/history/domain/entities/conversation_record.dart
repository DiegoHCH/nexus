import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';

/// Una conversación entera, lista para guardarse.
///
/// Lleva **la carpeta** además del texto porque es la unidad que organiza todo
/// el producto: la memoria va por carpeta, el contexto va por carpeta y el
/// archivo también. Cinco conversaciones sobre `workspace` acaban juntas, y las
/// de otro proyecto en otro sitio.
@immutable
class ConversationRecord {
  const ConversationRecord({
    required this.id,
    required this.folderPath,
    required this.startedAt,
    required this.messages,
  });

  final String id;
  final String folderPath;
  final DateTime startedAt;
  final List<ChatMessage> messages;

  /// El nombre de la carpeta, que es como se llama el proyecto en todos lados.
  String get projectName {
    final parts = folderPath.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'sin-proyecto' : parts.last;
  }

  /// La primera cosa que se pidió, recortada. Es el mejor título disponible sin
  /// gastar un turno del modelo en inventar uno — y el que reconoce quien
  /// buscaba esta conversación.
  String get title {
    final first = messages
        .where((message) => message.author == ChatAuthor.user)
        .map((message) => message.text.trim())
        .where((text) => text.isNotEmpty)
        .firstOrNull;
    if (first == null || first.isEmpty) return 'Conversación sin título';
    final flat = first.replaceAll(RegExp(r'\s+'), ' ');
    return flat.length <= 70 ? flat : '${flat.substring(0, 70)}…';
  }

  /// Vacía si nadie llegó a decir nada. No se guarda: un archivo por cada vez
  /// que se abrió una pestaña y se cerró sin usarla no es historial, es ruido.
  bool get isEmpty => messages.every((message) => message.text.trim().isEmpty);
}

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
    this.profileName,
    this.sourcePath,
    String? title,
    // El campo es privado y el parámetro no: quien construye pasa `title`, y
    // adentro se guarda como el título de respaldo que usa el getter.
    // ignore: prefer_initializing_formals
  }) : _title = title;

  final String id;
  final String folderPath;
  final DateTime startedAt;
  final List<ChatMessage> messages;

  /// Con qué cuenta de Claude se trabajó — `work`, `private`— o `null` con la
  /// de siempre. Es el primer nivel de carpetas del vault, la misma convención
  /// que ya usa La Oficina: `vault/perfil/proyecto/conversación.md`.
  final String? profileName;

  /// El nombre de la carpeta, que es como se llama el proyecto en todos lados.
  String get projectName {
    final parts = folderPath.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'sin-proyecto' : parts.last;
  }

  /// El archivo del que se leyó, cuando vino de una carpeta o un vault. Sin
  /// esto no se podría borrar lo que se está viendo: la nota tiene su propio
  /// nombre en el disco y no se puede deducir del identificador.
  final String? sourcePath;

  /// El título que traía la nota, si venía con uno. Lo que se lee de un vault
  /// ya tiene título escrito, y deducirlo otra vez del primer mensaje daría uno
  /// distinto del que se ve en el archivo.
  final String? _title;

  /// La primera cosa que se pidió, recortada. Es el mejor título disponible sin
  /// gastar un turno del modelo en inventar uno — y el que reconoce quien
  /// buscaba esta conversación.
  String get title {
    if (_title case final stored? when stored.trim().isNotEmpty) return stored;
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

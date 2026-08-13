import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';

/// El Markdown de una conversación y el de la nota que agrupa un proyecto.
///
/// Se separa de quien escribe en disco porque es donde están las decisiones que
/// se pueden discutir —y probar— sin tocar archivos: cómo se titula, qué lleva
/// la cabecera, y **cómo se enlazan**, que es lo único que hace que Obsidian
/// dibuje un grafo por proyecto en vez de una nube de notas sueltas.
abstract final class ConversationMarkdown {
  /// Nombre de archivo: fecha delante para que ordenen solos, y el título
  /// detrás para reconocerla de un vistazo en el explorador.
  static String fileName(ConversationRecord record) {
    final date = _date(record.startedAt);
    final slug = _slug(record.title);
    return '$date-$slug.md';
  }

  /// La conversación.
  ///
  /// [wikilinks] pone el enlace al proyecto en la sintaxis de Obsidian. Es
  /// **la diferencia entre las dos opciones**: en una carpeta normal ese
  /// `[[workspace]]` sería un símbolo raro en medio del texto, y en un vault es
  /// lo que agrupa las cinco conversaciones del proyecto en su propio grafo.
  static String conversation(
    ConversationRecord record, {
    required bool wikilinks,
  }) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('titulo: ${_quote(record.title)}')
      ..writeln('proyecto: ${record.projectName}')
      ..writeln('carpeta: ${record.folderPath}')
      ..writeln('fecha: ${record.startedAt.toIso8601String()}')
      ..writeln('tags: [nexus, ${_slug(record.projectName)}]')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${record.title}')
      ..writeln()
      ..writeln(
        wikilinks
            ? 'Proyecto: [[${record.projectName}]]'
            : 'Proyecto: **${record.projectName}** (`${record.folderPath}`)',
      )
      ..writeln();

    for (final message in record.messages) {
      if (message.text.trim().isEmpty) continue;
      final quien = message.author == ChatAuthor.user ? 'Tú' : 'Nexus';
      // Se conserva si se dijo o se escribió: si la transcripción se equivocó,
      // saber que venía del micrófono explica el disparate meses después.
      final comoLoDijo = message.spoken ? ' · por voz' : '';
      buffer
        ..writeln('## $quien$comoLoDijo')
        ..writeln()
        ..writeln(message.text.trim())
        ..writeln();
    }

    return buffer.toString();
  }

  /// La nota del proyecto: el centro del grafo.
  ///
  /// Sin ella, en Obsidian cada conversación sería un punto suelto —un enlace a
  /// una nota que no existe no dibuja nada— y no habría un grafo por proyecto,
  /// que es justo lo que se pide.
  static String project(
    String projectName,
    String folderPath,
    List<ConversationRecord> conversations, {
    required bool wikilinks,
  }) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('proyecto: $projectName')
      ..writeln('carpeta: $folderPath')
      ..writeln('tags: [nexus, proyecto]')
      ..writeln('---')
      ..writeln()
      ..writeln('# $projectName')
      ..writeln()
      ..writeln('Conversaciones de Nexus sobre `$folderPath`.')
      ..writeln();

    // De la más reciente hacia atrás: lo último es lo que se busca.
    final ordenadas = [...conversations]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    for (final record in ordenadas) {
      final name = fileName(record).replaceAll('.md', '');
      final link = wikilinks ? '[[$name]]' : '[${record.title}]($name.md)';
      buffer.writeln('- ${_date(record.startedAt)} · $link');
    }

    return buffer.toString();
  }

  static String _date(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)}';
  }

  /// Un nombre de archivo que sobreviva a cualquier sistema: sin acentos, sin
  /// barras, sin dos puntos. Los dos puntos importan más de lo que parece —
  /// rompen el archivo en Windows y confunden a Obsidian en los enlaces.
  static String _slug(String value) {
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    var slug = value.toLowerCase();
    acentos.forEach((from, to) => slug = slug.replaceAll(from, to));
    slug = slug
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    if (slug.length > 60) slug = slug.substring(0, 60);
    slug = slug.replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'conversacion' : slug;
  }

  static String _quote(String value) => '"${value.replaceAll('"', r'\"')}"';
}

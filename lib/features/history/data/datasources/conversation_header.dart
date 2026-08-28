import 'dart:convert';
import 'dart:io';

import 'package:nexus/features/history/domain/entities/conversation_summary.dart';

/// La cabecera de una nota, leída **sin leer la nota**.
///
/// Es la pieza que hace que listar cueste poco. Una conversación archivada son
/// unos cientos de líneas de Markdown, pero lo que necesita una lista —título,
/// fecha, proyecto, identificador— cabe en los primeros bytes del archivo, en
/// el frontmatter. Antes había dos sitios leyendo notas enteras para quedarse
/// con eso: el lector del vault y la nota de proyecto, cada uno con su parser.
/// Ahora los dos piden aquí.
abstract final class ConversationHeader {
  /// Cuánto se lee de cada nota.
  ///
  /// El frontmatter que escribe Nexus ronda los 300 bytes con el título más
  /// largo que deja pasar (70 caracteres) y una ruta de proyecto profunda. Se
  /// pide un orden de magnitud más para que quepan también las cabeceras de La
  /// Oficina, que trae claves propias. Lo que no quepa en 4 KB no es una
  /// cabecera nuestra.
  static const bytes = 4096;

  /// Los campos del frontmatter, o `null` si el archivo no empieza por uno.
  ///
  /// `null` no es un error: en un vault de Obsidian la inmensa mayoría de las
  /// notas no son conversaciones, y descartarlas por los primeros tres bytes
  /// es justo el ahorro que se busca.
  static Future<Map<String, String>?> read(File file) async {
    final bytes = <int>[];
    // `openRead` con un tope: el resto del archivo no llega a salir del disco.
    // Si la nota es más corta, se para sola.
    await for (final chunk in file.openRead(0, ConversationHeader.bytes)) {
      bytes.addAll(chunk);
    }
    // `allowMalformed` porque el tope puede caer en mitad de un carácter de
    // varios bytes. Ese carácter está más allá de la cabecera; romper la
    // lectura entera por él sería perder la nota por donde no importa.
    return fields(utf8.decode(bytes, allowMalformed: true));
  }

  /// Lo mismo sobre un texto que ya se tiene en la mano.
  static Map<String, String>? fields(String content) {
    if (!content.startsWith('---')) return null;
    final end = content.indexOf('\n---', 3);
    if (end == -1) return null;

    final campos = <String, String>{};
    for (final line in content.substring(3, end).split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      var value = line.substring(colon + 1).trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
        value = value.substring(1, value.length - 1);
      }
      campos[key] = value;
    }
    return campos;
  }

  /// La ficha de una nota, leyendo solo su cabecera.
  ///
  /// Es el atajo que usan los dos sitios que listan: el lector del vault y la
  /// nota de proyecto. `null` si el archivo no es una conversación.
  static Future<ConversationSummary?> summaryOf(File file) async {
    final campos = await read(file);
    return campos == null ? null : summaryFrom(campos, file.path);
  }

  /// La ficha que sale de unos campos ya leídos.
  ///
  /// Se aceptan las dos formas de fechar que hay en el vault: `fecha`, que
  /// escribe Nexus, y `actualizada`, que escribe La Oficina.
  static ConversationSummary? summaryFrom(
    Map<String, String> front,
    String path,
  ) {
    final project = front['proyecto'];
    if (project == null || project.isEmpty) return null;

    final when =
        DateTime.tryParse(front['fecha'] ?? '') ??
        DateTime.tryParse(front['actualizada'] ?? '');
    if (when == null) return null;

    return ConversationSummary(
      id: front['id'] ?? path,
      folderPath: project,
      startedAt: when.toLocal(),
      title: front['titulo'] ?? 'Conversación sin título',
      // Lo escriben las dos apps en la cabecera. Si no está —una nota de una
      // versión de Nexus anterior a esto— se dice que no consta en vez de leer
      // el archivo entero para contarlo, que es justo lo que se quiere evitar.
      turns: int.tryParse(front['mensajes'] ?? '') ?? 0,
      profileName: front['perfil'],
      sourcePath: path,
    );
  }
}

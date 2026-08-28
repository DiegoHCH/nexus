import 'dart:io';

import 'package:nexus/features/history/data/datasources/conversation_header.dart';
import 'package:nexus/features/history/data/repositories/conversation_markdown.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';

/// Escribe las conversaciones como Markdown, una carpeta por proyecto.
///
/// Sirve para los dos destinos de disco —una carpeta cualquiera y un vault de
/// Obsidian— porque son lo mismo: archivos de texto. Lo único que cambia es
/// [wikilinks], y no es un detalle estético: es lo que hace que Obsidian
/// dibuje **un grafo por proyecto** en vez de notas sueltas.
///
/// Queda así en el disco:
///
/// ```
/// <destino>/Nexus/workspace/workspace.md          ← el centro del grafo
/// <destino>/Nexus/workspace/2026-08-12-mira-....md
/// <destino>/Nexus/otro-proyecto/otro-proyecto.md  ← su propio grafo, aparte
/// ```
class MarkdownArchive implements ConversationArchive {
  const MarkdownArchive({required this.root, required this.wikilinks});

  /// La carpeta que eligió el usuario.
  final String root;

  final bool wikilinks;

  /// Dónde va cada conversación: `<destino>/<perfil>/<proyecto>/`.
  ///
  /// Es la convención que ya usa el vault de La Oficina, y por eso se adopta
  /// tal cual en vez de inventar otra: si las dos apps escriben en la misma
  /// carpeta con dos organizaciones distintas, acabas con el mismo proyecto en
  /// dos sitios y ninguna lista completa. Sin perfil no se mete un nivel
  /// vacío — el proyecto cuelga directamente del destino.
  String _pathFor(ConversationRecord record) {
    final profile = record.profileName;
    return profile == null || profile.isEmpty
        ? '$root/${record.projectName}'
        : '$root/$profile/${record.projectName}';
  }

  @override
  Future<void> save(ConversationRecord record) async {
    // Una conversación en la que nadie llegó a decir nada no es historial.
    if (record.isEmpty) return;

    final directory = Directory(_pathFor(record));
    await directory.create(recursive: true);

    final file = File(
      '${directory.path}/${ConversationMarkdown.fileName(record.summary)}',
    );
    await file.writeAsString(
      ConversationMarkdown.conversation(record, wikilinks: wikilinks),
    );

    await _updateProjectNote(directory, record);
  }

  /// Rehace la nota del proyecto leyendo lo que hay en su carpeta.
  ///
  /// Se reconstruye del disco y no de una lista en memoria a propósito: así
  /// sobrevive a reiniciar la app, y una conversación archivada hace tres días
  /// sigue enlazada aunque este proceso no sepa que existió.
  ///
  /// De cada vecina se lee **solo la cabecera**. Enlazarlas necesita título y
  /// fecha, nada más; leer los archivos enteros para eso costaba, en un
  /// proyecto con doscientas conversaciones y una charla de treinta turnos,
  /// seis mil lecturas completas.
  Future<void> _updateProjectNote(
    Directory directory,
    ConversationRecord record,
  ) async {
    final note = File('${directory.path}/${record.projectName}.md');
    final entries = <ConversationSummary>[];

    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      if (entity.path == note.path) continue;
      final parsed = await ConversationHeader.summaryOf(entity);
      if (parsed == null) continue;
      entries.add(parsed);
    }

    await note.writeAsString(
      ConversationMarkdown.project(
        record.projectName,
        record.folderPath,
        entries.isEmpty ? [record.summary] : entries,
        wikilinks: wikilinks,
      ),
    );
  }
}

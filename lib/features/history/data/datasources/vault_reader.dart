import 'dart:io';

import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/conversation_header.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';

/// Lee las conversaciones que ya hay en la carpeta o el vault elegido.
///
/// No solo las que escribe Nexus: **también las de La Oficina**, que deja sus
/// notas en el mismo sitio con la misma forma —`vault/perfil/proyecto/`, con
/// frontmatter y los turnos en encabezados—. Son conversaciones sobre los
/// mismos repos y con el mismo Claude; esconderlas porque las escribió otra app
/// sería una frontera que solo existe en el código.
///
/// Lo que las une es el campo `proyecto` del frontmatter: lleva la **ruta
/// completa** de la carpeta, así que se puede filtrar por ella sin depender de
/// cómo se llamen los directorios.
///
/// ## Por qué esto guarda estado
///
/// [list] se llama **en cada turno** —al archivar se refresca el historial— y
/// un vault de Obsidian de verdad son miles de notas. Antes cada llamada leía
/// y parseaba todas, enteras, en el hilo que dibuja el orbe. Ahora se lee solo
/// la cabecera, y de una vez para otra se releen únicamente las notas cuya
/// fecha de modificación cambió. Por eso hay una instancia viva —la del
/// proveedor— en vez de un `const` que se construye en cada uso.
class VaultReader {
  VaultReader();

  /// Hasta dónde se baja buscando notas: `perfil/proyecto/nota.md` son tres, y
  /// se deja una de margen. Sin tope, un vault grande se recorre entero en cada
  /// apertura del historial.
  static const _maxDepth = 4;

  /// Lo leído la vez anterior, por ruta. Guarda también las notas que **no**
  /// son conversaciones: recordar que un archivo no lo era ahorra tanto como
  /// recordar que lo era, y en un vault son la mayoría.
  final _cache = <String, _Leida>{};

  /// [folderPath] a `null` trae **todo el vault**, que es lo que hace falta
  /// para enseñarlo por perfiles: un perfil abarca varios proyectos.
  Future<List<ConversationSummary>> list(
    String root, {
    String? folderPath,
  }) async {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      _cache.clear();
      return const [];
    }

    final vistas = <String, _Leida>{};
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      if (_depthOf(root, entity.path) > _maxDepth) continue;
      // `_memoria.md` y las notas de proyecto no son conversaciones.
      final name = entity.path.split('/').last;
      if (name.startsWith('_')) continue;

      final stat = await entity.stat();
      final antes = _cache[entity.path];
      // Fecha **y** tamaño: en un sistema de archivos con marca de segundo, dos
      // escrituras seguidas dentro del mismo segundo son indistinguibles por la
      // fecha sola, y archivar es exactamente eso.
      if (antes != null &&
          antes.modified == stat.modified &&
          antes.size == stat.size) {
        vistas[entity.path] = antes;
        continue;
      }

      final campos = await ConversationHeader.read(entity);
      vistas[entity.path] = _Leida(
        modified: stat.modified,
        size: stat.size,
        summary: campos == null
            ? null
            : ConversationHeader.summaryFrom(campos, entity.path),
      );
    }

    // Se reemplaza en vez de mezclar: lo que ya no está en el disco tampoco
    // tiene que seguir ocupando memoria, y esto es lo que lo poda.
    _cache
      ..clear()
      ..addAll(vistas);

    final records = <ConversationSummary>[];
    for (final leida in vistas.values) {
      final summary = leida.summary;
      if (summary == null) continue;
      if (folderPath != null && summary.folderPath != folderPath) continue;
      records.add(summary);
    }

    records.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return records;
  }

  /// La conversación entera de una nota. Es lo que se paga **al abrir una**, no
  /// al listarlas.
  static Future<ConversationRecord?> readOne(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    return parse(await file.readAsString(), fallbackId: path, sourcePath: path);
  }

  static int _depthOf(String root, String path) =>
      path.substring(root.length).split('/').where((p) => p.isNotEmpty).length;

  /// Saca una conversación de una nota. Devuelve `null` si no lo es.
  static ConversationRecord? parse(
    String content, {
    required String fallbackId,
    String? sourcePath,
  }) {
    final front = ConversationHeader.fields(content);
    if (front == null) return null;
    final project = front['proyecto'];
    if (project == null || project.isEmpty) return null;

    final when =
        DateTime.tryParse(front['fecha'] ?? '') ??
        DateTime.tryParse(front['actualizada'] ?? '');
    if (when == null) return null;

    return ConversationRecord(
      id: front['id'] ?? fallbackId,
      folderPath: project,
      startedAt: when.toLocal(),
      profileName: front['perfil'],
      sourcePath: sourcePath,
      messages: _messages(content),
      title: front['titulo'],
    );
  }

  /// Los turnos salen de los encabezados de segundo nivel.
  ///
  /// Se acepta cómo los escribe cada app: Nexus pone `## Tú` y `## Nexus`; La
  /// Oficina, `## 👤 Tú → dev` y `## 🤖 dev`, con el nombre del agente. Lo que
  /// se mira es si el encabezado te nombra a ti; todo lo demás lo dijo la
  /// máquina, se llame como se llame.
  static List<ChatMessage> _messages(String content) {
    final messages = <ChatMessage>[];
    final lines = content.split('\n');
    ChatAuthor? author;
    var spoken = false;
    final buffer = StringBuffer();

    void flush() {
      final quien = author;
      if (quien == null) return;
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        messages.add(ChatMessage(author: quien, text: text, spoken: spoken));
      }
      buffer.clear();
    }

    for (final line in lines) {
      if (line.startsWith('## ')) {
        flush();
        final heading = line.substring(3);
        author = heading.contains('Tú') || heading.contains('👤')
            ? ChatAuthor.user
            : ChatAuthor.nexus;
        spoken = heading.contains('por voz');
        continue;
      }
      if (author != null) buffer.writeln(line);
    }
    flush();

    return messages;
  }
}

/// Una nota ya mirada: cómo estaba el archivo y qué salió de su cabecera.
class _Leida {
  const _Leida({
    required this.modified,
    required this.size,
    required this.summary,
  });

  final DateTime modified;
  final int size;

  /// `null` cuando la nota no es una conversación.
  final ConversationSummary? summary;
}

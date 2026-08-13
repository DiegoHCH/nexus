import 'dart:io';

import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';

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
class VaultReader {
  const VaultReader();

  /// Hasta dónde se baja buscando notas: `perfil/proyecto/nota.md` son tres, y
  /// se deja una de margen. Sin tope, un vault grande se recorre entero en cada
  /// apertura del historial.
  static const _maxDepth = 4;

  /// [folderPath] a `null` trae **todo el vault**, que es lo que hace falta
  /// para enseñarlo por perfiles: un perfil abarca varios proyectos.
  Future<List<ConversationRecord>> read(
    String root, {
    String? folderPath,
  }) async {
    final directory = Directory(root);
    if (!directory.existsSync()) return const [];

    final records = <ConversationRecord>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      if (_depthOf(root, entity.path) > _maxDepth) continue;
      // `_memoria.md` y las notas de proyecto no son conversaciones.
      final name = entity.path.split('/').last;
      if (name.startsWith('_')) continue;

      final record = parse(
        await entity.readAsString(),
        fallbackId: entity.path,
      );
      if (record == null) continue;
      if (folderPath != null && record.folderPath != folderPath) continue;
      records.add(record);
    }

    records.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return records;
  }

  static int _depthOf(String root, String path) =>
      path.substring(root.length).split('/').where((p) => p.isNotEmpty).length;

  /// Saca una conversación de una nota. Devuelve `null` si no lo es — en un
  /// vault hay muchas notas y casi ninguna es esto.
  static ConversationRecord? parse(
    String content, {
    required String fallbackId,
  }) {
    final front = _frontmatter(content);
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
      messages: _messages(content),
      title: front['titulo'],
    );
  }

  static Map<String, String> _frontmatter(String content) {
    if (!content.startsWith('---')) return const {};
    final end = content.indexOf('\n---', 3);
    if (end == -1) return const {};

    final fields = <String, String>{};
    for (final line in content.substring(3, end).split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      var value = line.substring(colon + 1).trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
        value = value.substring(1, value.length - 1);
      }
      fields[key] = value;
    }
    return fields;
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

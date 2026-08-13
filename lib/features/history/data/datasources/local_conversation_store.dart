import 'dart:convert';
import 'dart:io';

import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:path_provider/path_provider.dart';

/// Las conversaciones guardadas dentro de la app, para poder volver a leerlas.
///
/// Vive **aparte del destino que elija el usuario** y siempre está encendido.
/// Si el historial de Nexus dependiera del vault de Obsidian o de Notion,
/// elegir «en ningún sitio» —o quedarse sin red— dejaría la app sin memoria de
/// lo que hiciste. El destino externo es para leerlo fuera; esto es para
/// leerlo aquí.
class LocalConversationStore {
  const LocalConversationStore();

  /// JSON y una carpeta por proyecto: se puede abrir con cualquier editor si
  /// algún día hace falta rescatar algo a mano, y ver de un vistazo qué
  /// proyecto ocupa qué.
  Future<Directory> _folderFor(String folderPath) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}/conversaciones/${_slug(folderPath)}',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> save(ConversationRecord record) async {
    if (record.isEmpty) return;
    final directory = await _folderFor(record.folderPath);
    final file = File('${directory.path}/${record.id}.json');
    await file.writeAsString(
      jsonEncode({
        'id': record.id,
        'carpeta': record.folderPath,
        'fecha': record.startedAt.toIso8601String(),
        if (record.model != null) 'modelo': record.model,
        if (record.contextTokens != null) 'contexto': record.contextTokens,
        if (record.profileName != null) 'perfil': record.profileName,
        'mensajes': [
          for (final message in record.messages)
            {
              'autor': message.author.name,
              'texto': message.text,
              'hablado': message.spoken,
            },
        ],
      }),
    );
  }

  /// Lo guardado de esa carpeta, de lo más reciente hacia atrás.
  ///
  /// Un archivo ilegible se salta en vez de tumbar la lista: puede venir de una
  /// versión anterior, y perder el historial entero por una conversación rota
  /// sería un mal cambio.
  Future<List<ConversationRecord>> list(String folderPath) async {
    final directory = await _folderFor(folderPath);
    final records = <ConversationRecord>[];

    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final record = _decode(await entity.readAsString());
      if (record != null) records.add(record);
    }

    records.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return records;
  }

  /// Todas las conversaciones guardadas, de todas las carpetas. Es lo que pide
  /// la vista por perfiles: ahí no se mira un proyecto, se mira una cuenta.
  Future<List<ConversationRecord>> listAll() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/conversaciones');
    if (!root.existsSync()) return const [];

    final records = <ConversationRecord>[];
    await for (final folder in root.list()) {
      if (folder is! Directory) continue;
      await for (final entity in folder.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final record = _decode(await entity.readAsString());
        if (record != null) records.add(record);
      }
    }

    records.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return records;
  }

  Future<void> delete(ConversationRecord record) async {
    final directory = await _folderFor(record.folderPath);
    final file = File('${directory.path}/${record.id}.json');
    if (file.existsSync()) await file.delete();
  }

  ConversationRecord? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final when = DateTime.tryParse(decoded['fecha'] as String? ?? '');
      if (when == null) return null;
      return ConversationRecord(
        id: decoded['id'] as String? ?? '',
        folderPath: decoded['carpeta'] as String? ?? '',
        startedAt: when,
        model: decoded['modelo'] as String?,
        contextTokens: (decoded['contexto'] as num?)?.toInt(),
        profileName: decoded['perfil'] as String?,
        messages: [
          for (final message
              in decoded['mensajes'] as List<dynamic>? ?? const [])
            if (message is Map<String, dynamic>)
              ChatMessage(
                author: message['autor'] == 'user'
                    ? ChatAuthor.user
                    : ChatAuthor.nexus,
                text: message['texto'] as String? ?? '',
                spoken: message['hablado'] as bool? ?? false,
              ),
        ],
      );
    } on FormatException {
      return null;
    }
  }

  /// La ruta entera aplanada: dos proyectos pueden llamarse igual y estar en
  /// sitios distintos, así que el nombre de la carpeta no sirve como identidad.
  static String _slug(String folderPath) => folderPath
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

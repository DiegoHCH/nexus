import 'dart:convert';
import 'dart:io';

import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:path_provider/path_provider.dart';

/// Las conversaciones guardadas dentro de la app, para poder volver a leerlas.
///
/// Vive **aparte del destino que elija el usuario** y siempre está encendido.
/// Si el historial de Nexus dependiera del vault de Obsidian o de Notion,
/// elegir «en ningún sitio» —o quedarse sin red— dejaría la app sin memoria de
/// lo que hiciste. El destino externo es para leerlo fuera; esto es para
/// leerlo aquí.
///
/// ## El índice
///
/// Cada carpeta lleva un `_index.json` con la ficha de sus conversaciones:
/// identificador, fecha, título y cuántos turnos. Listar lee ese archivo y
/// nada más; los JSON de las conversaciones solo se abren **al abrir una**.
///
/// Antes no lo había, y listar significaba decodificar todas las conversaciones
/// con todos sus mensajes para luego quedarse con treinta —o para paginar y
/// volver a pagarlo entero en la página siguiente—. Con el historial
/// refrescándose en cada turno, era el trabajo que más crecía con el uso.
///
/// El índice **no es la verdad**: la verdad son los JSON. Si se pierde, se
/// borra a mano o se queda descuadrado, se rehace leyéndolos. Por eso se
/// comprueba en cada lectura que sus identificadores sean los mismos archivos
/// que hay en la carpeta, que cuesta un listado sin abrir nada.
class LocalConversationStore {
  const LocalConversationStore();

  /// El nombre del índice empieza por `_` para que se distinga de un vistazo de
  /// las conversaciones que tiene al lado.
  static const _indexFile = '_index.json';

  /// Sube cuando cambie lo que se guarda de cada ficha. Un índice de otra
  /// versión no se intenta interpretar: se rehace.
  static const _indexVersion = 1;

  /// JSON y una carpeta por proyecto: se puede abrir con cualquier editor si
  /// algún día hace falta rescatar algo a mano, y ver de un vistazo qué
  /// proyecto ocupa qué.
  Future<Directory> _folderFor(String folderPath) async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/conversaciones/${_slug(folderPath)}');
  }

  Future<void> save(ConversationRecord record) async {
    if (record.isEmpty) return;
    final directory = await _folderFor(record.folderPath);
    await directory.create(recursive: true);
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

    // El índice se actualiza **aquí**, con la conversación delante: es el único
    // momento en que el título y el número de turnos están resueltos sin leer
    // nada del disco.
    //
    // Se toma el índice **sin cotejarlo con la carpeta**. Cotejar aquí lo daba
    // siempre por descuadrado —el archivo que se acaba de escribir todavía no
    // está en él— y cada conversación nueva acababa releyendo el proyecto
    // entero. Que el índice cuadre con el disco se comprueba al listar, que es
    // donde importa.
    final fichas = await _paraEscribir(directory)
      ..removeWhere((ficha) => ficha.id == record.id)
      ..add(record.summary);
    await _writeIndex(directory, fichas);
  }

  /// Lo guardado de esa carpeta, de lo más reciente hacia atrás.
  Future<List<ConversationSummary>> list(String folderPath) async {
    final directory = await _folderFor(folderPath);
    final fichas = await _index(directory);
    fichas.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return fichas;
  }

  /// Todas las conversaciones guardadas, de todas las carpetas. Es lo que pide
  /// la vista por perfiles: ahí no se mira un proyecto, se mira una cuenta.
  Future<List<ConversationSummary>> listAll() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/conversaciones');
    if (!root.existsSync()) return const [];

    final fichas = <ConversationSummary>[];
    await for (final folder in root.list()) {
      if (folder is! Directory) continue;
      fichas.addAll(await _index(folder));
    }

    fichas.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return fichas;
  }

  /// La conversación entera. Es lo que se paga al abrir una, no al listarlas.
  Future<ConversationRecord?> read(ConversationSummary ficha) async {
    final directory = await _folderFor(ficha.folderPath);
    final file = File('${directory.path}/${ficha.id}.json');
    if (!file.existsSync()) return null;
    return _decode(await file.readAsString());
  }

  Future<void> delete(ConversationSummary ficha) async {
    final directory = await _folderFor(ficha.folderPath);
    final file = File('${directory.path}/${ficha.id}.json');
    if (file.existsSync()) await file.delete();

    final fichas = await _paraEscribir(directory)
      ..removeWhere((otra) => otra.id == ficha.id);
    await _writeIndex(directory, fichas);
  }

  /// El índice de esa carpeta, rehecho si no está o no cuadra con el disco.
  ///
  /// Cuadrar es que los identificadores del índice sean exactamente los
  /// archivos que hay: eso se comprueba listando la carpeta, sin abrir ninguno.
  /// Cubre el caso real —alguien borra un JSON a mano, o llega desde una
  /// versión de la app que no escribía índice— sin devolver el coste que se
  /// acaba de quitar.
  Future<List<ConversationSummary>> _index(Directory directory) async {
    if (!directory.existsSync()) return [];

    final enDisco = await _idsEnDisco(directory);
    final fichas = await _readIndex(directory);
    if (fichas != null && _sameIds(fichas, enDisco)) return fichas;

    final rehecho = await _rebuild(directory, enDisco);
    await _writeIndex(directory, rehecho);
    return rehecho;
  }

  /// El índice sobre el que se va a escribir. A diferencia de [_index], no se
  /// coteja con la carpeta: quien llama acaba de cambiarla.
  Future<List<ConversationSummary>> _paraEscribir(Directory directory) async =>
      await _readIndex(directory) ??
      await _rebuild(directory, await _idsEnDisco(directory));

  /// Qué conversaciones hay, por el nombre de sus archivos. Se lista la
  /// carpeta; no se abre ninguna.
  Future<Set<String>> _idsEnDisco(Directory directory) async {
    final ids = <String>{};
    if (!directory.existsSync()) return ids;
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.path.split('/').last;
      if (name == _indexFile) continue;
      ids.add(name.substring(0, name.length - '.json'.length));
    }
    return ids;
  }

  static bool _sameIds(List<ConversationSummary> fichas, Set<String> enDisco) {
    final delIndice = {for (final ficha in fichas) ficha.id};
    // Por conjuntos y no por longitudes: un índice con la misma ficha repetida
    // tiene el número de entradas que toca y aun así está mal.
    return delIndice.length == fichas.length &&
        delIndice.length == enDisco.length &&
        delIndice.containsAll(enDisco);
  }

  /// Lee el índice. `null` si no está o no se entiende — las dos cosas se
  /// arreglan igual, rehaciéndolo, así que no hace falta distinguirlas.
  Future<List<ConversationSummary>?> _readIndex(Directory directory) async {
    final file = File('${directory.path}/$_indexFile');
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != _indexVersion) return null;
      final crudas = decoded['conversaciones'];
      if (crudas is! List) return null;

      final fichas = <ConversationSummary>[];
      for (final cruda in crudas) {
        if (cruda is! Map<String, dynamic>) return null;
        final when = DateTime.tryParse(cruda['fecha'] as String? ?? '');
        final id = cruda['id'] as String?;
        if (when == null || id == null || id.isEmpty) return null;
        fichas.add(
          ConversationSummary(
            id: id,
            folderPath: cruda['carpeta'] as String? ?? '',
            startedAt: when,
            title: cruda['titulo'] as String? ?? 'Conversación sin título',
            turns: (cruda['turnos'] as num?)?.toInt() ?? 0,
            profileName: cruda['perfil'] as String?,
            model: cruda['modelo'] as String?,
            contextTokens: (cruda['contexto'] as num?)?.toInt(),
          ),
        );
      }
      return fichas;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeIndex(
    Directory directory,
    List<ConversationSummary> fichas,
  ) async {
    if (!directory.existsSync()) return;
    final file = File('${directory.path}/$_indexFile');
    await file.writeAsString(
      jsonEncode({
        'version': _indexVersion,
        'conversaciones': [
          for (final ficha in fichas)
            {
              'id': ficha.id,
              'carpeta': ficha.folderPath,
              'fecha': ficha.startedAt.toIso8601String(),
              'titulo': ficha.title,
              'turnos': ficha.turns,
              if (ficha.profileName != null) 'perfil': ficha.profileName,
              if (ficha.model != null) 'modelo': ficha.model,
              if (ficha.contextTokens != null) 'contexto': ficha.contextTokens,
            },
        ],
      }),
    );
  }

  /// El camino caro, y por eso el excepcional: abrir cada conversación para
  /// volver a sacarle la ficha.
  ///
  /// Un archivo ilegible se salta en vez de tumbar la lista: puede venir de una
  /// versión anterior, y perder el historial entero por una conversación rota
  /// sería un mal cambio.
  Future<List<ConversationSummary>> _rebuild(
    Directory directory,
    Set<String> ids,
  ) async {
    final fichas = <ConversationSummary>[];
    for (final id in ids) {
      final file = File('${directory.path}/$id.json');
      if (!file.existsSync()) continue;
      final record = _decode(await file.readAsString());
      if (record != null) fichas.add(record.summary);
    }
    return fichas;
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

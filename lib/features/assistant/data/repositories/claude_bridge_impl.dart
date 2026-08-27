import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/datasources/project_context_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';
import 'package:nexus/features/assistant/data/repositories/tool_activity_reader.dart';
import 'package:nexus/features/assistant/domain/usecases/mcp_permissions.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';

class ClaudeBridgeImpl implements ClaudeBridge {
  const ClaudeBridgeImpl(
    this._dataSource, [
    this._projectContext = const ProjectContextDataSource(),
  ]);

  final ClaudeCliDataSource _dataSource;

  /// Lo que Claude debería saber antes de empezar. Se lee **en cada encargo**,
  /// no una vez: editar el `CLAUDE.md` a media conversación tiene que valer
  /// para el siguiente.
  final ProjectContextDataSource _projectContext;

  /// `manual` deniega la escritura —también la que intente colarse por Bash,
  /// medido contra el CLI real— y `acceptEdits` la concede sin preguntar, que
  /// es lo único viable sin nadie delante para aprobar.
  static String _permissionMode({required bool canEdit}) =>
      canEdit ? 'acceptEdits' : 'manual';

  @override
  Stream<ClaudeEvent> ask(
    String instruction, {
    required String workingDirectory,
    required bool canEdit,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? claudeProfile,
    String? model,
    String? effort,
    String? artifactsFolder,
    String? carpetaDePruebas,
    List<String> disallowedTools = const [],
    String? language,
  }) async* {
    /// Algo que **no** era un fallo: la respuesta ya empezó y reintentar
    /// duplicaría trabajo ya hecho.
    var emitted = false;

    /// Los fallos se retienen mientras el reintento siga siendo posible.
    ///
    /// Sin esto el reintento de abajo no llegaba a saltar nunca, y el motivo es
    /// fino: con una sesión que ya no existe, el CLI **no muere callado**.
    /// Escupe una línea `{"type":"result","is_error":true}` y **luego** sale con
    /// 1 —medido contra el binario—, esa línea se traduce a `ClaudeFailed`, y
    /// con eso `emitted` quedaba en `true`. O sea que el propio fallo desarmaba
    /// la red que estaba puesta para atraparlo. Reteniéndolos, un intento que
    /// solo produjo fallos sigue siendo reintentable.
    final withheld = <ClaudeEvent>[];

    /// El prompt de la **última petición**, que es el contexto de verdad.
    ///
    /// El `usage` del `result` no sirve para esto: es del turno entero, y un
    /// turno con herramientas hace **varias peticiones**, cada una reenviando
    /// el contexto completo. Sumarlas cuenta lo mismo muchas veces. Medido
    /// contra el binario con un turno de cuatro peticiones: la última pedía
    /// 32.898 tokens y el `result` reportaba 61.594, casi el doble. Con turnos
    /// largos eso pasaba del 100 % de la ventana — se vio un «132 %», que es lo
    /// que destapó esto.
    int? contextoVivo;

    try {
      final context = await _projectContext.read(workingDirectory);
      // **Qué sabe Claude antes de empezar, dicho una vez por encargo.**
      //
      // Va aparte de la línea del CLI porque es otra pregunta: aquella dice cómo se
      // lanzó y esta qué se le puso delante. Y hace falta porque las reglas que un
      // repo declara pueden no existir o no caber, y sin verlo el síntoma es trabajo
      // que ignora una regla sin que nadie sepa por qué.
      debugPrint(
        'claude · ${context.rules.length} archivos de reglas · '
        '${context.rules.fold(0, (t, f) => t + f.content.length)} caracteres'
        '${context.sharedContext == null ? '' : ' · con contexto compartido'}',
      );

      await for (final json in _dataSource.run(
        instruction,
        workingDirectory: workingDirectory,
        permissionMode: _permissionMode(canEdit: canEdit),
        // La carpeta de documentos viaja como carpeta alcanzable, y no es
        // opcional: **medido contra el binario**, sin `--add-dir` la escritura
        // fuera del directorio de trabajo se deniega —aparece en
        // `permission_denials`— y Claude termina pidiendo un permiso que en una
        // sesión headless no hay quien conceda. Decirle dónde guardar sin darle
        // acceso es prometer algo que no puede cumplir.
        //
        // Es la única excepción a la regla de «ninguna otra carpeta»: no es
        // otro proyecto en el que colarse, es el cajón de salida que el usuario
        // eligió a propósito.
        extraDirectories: [
          ...extraDirectories,
          if (artifactsFolder != null && artifactsFolder.isNotEmpty)
            artifactsFolder,
        ],
        resumeSessionId: resumeSessionId,
        configDir: claudeProfile,
        model: model,
        effort: effort,
        // Los servidores MCP del perfil de **esta** carpeta, con permiso explícito.
        // Sin ellos, en headless toda llamada MCP se deniega sola: no hay nadie que
        // apruebe el diálogo, así que preguntar por el calendario acababa en «no puedo
        // consultarlo» con el conector conectado y sano.
        // **Y un conector nuevo no entra en una carpeta de solo lectura hasta que se
        // sepa qué escribe.** Autorizarlo entero dejaría escribir hacia fuera desde una
        // carpeta que promete no escribir, porque la lista de negación es por nombre y
        // no puede adivinar herramientas que no conoce. Los servidores del propio
        // usuario van siempre: los eligió él y son procesos suyos.
        herramientasMcp: [
          for (final servidor in McpPermissions.permitidosPara(
            claudeProfile,
            puedeEscribir: canEdit,
          ))
            'mcp__$servidor',
        ],
        // Los comandos bloqueados de la carpeta y, **si no puede escribir**, las
        // herramientas MCP que actúan fuera de la máquina.
        //
        // Esto último es la parte que conviene entender: el modo de solo lectura
        // garantiza **el disco** —lo hace el CLI y está medido— y hacia fuera de la
        // máquina lo único que protege es esa lista. Sin ella, permitir el conector de
        // correo para poder leerlo dejaría también mandarlo.
        disallowedTools: [
          ...disallowedTools,
          if (!canEdit) ...McpPermissions.escrituraDeFuera,
        ],
        appendSystemPrompt: ProjectContextPrompt.compose(
          rules: context.rules,
          sharedContext: context.sharedContext,
          artifactsFolder: artifactsFolder,
          carpetaDePruebas: carpetaDePruebas,
          // La cuenta sale **de aquí** y no de un parámetro nuevo: es donde el
          // perfil de la carpeta y el destino de los documentos se encuentran por
          // primera vez, y derivarla más arriba obligaría a llevarla de la mano por
          // tres sitios que no la usan.
          artifactsAccount: ClaudeProfile.nameFromPath(claudeProfile),
          language: language,
        ),
      )) {
        // Cada mensaje del asistente es una petición: su `usage` dice cuánto
        // contexto llevaba **esa**. La última gana.
        if (json['type'] == 'assistant') {
          final usage =
              (json['message'] as Map<String, dynamic>?)?['usage']
                  as Map<String, dynamic>?;
          if (usage != null) contextoVivo = _promptTokens(usage);
        }
        for (final event in _decode(json, workingDirectory)) {
          if (resumeSessionId != null && !emitted && event is ClaudeFailed) {
            withheld.add(event);
            continue;
          }
          emitted = true;
          // El fin de turno sale con el contexto de la última petición, no con
          // el acumulado que trae el `result`.
          yield switch (event) {
            ClaudeTurnCompleted() when contextoVivo != null =>
              ClaudeTurnCompleted(
                result: event.result,
                costUsd: event.costUsd,
                durationMs: event.durationMs,
                turnTokens: event.turnTokens,
                contextTokens: contextoVivo,
              ),
            _ => event,
          };
        }
      }
      // Terminó sin excepción: lo retenido era un fallo de verdad y se cuenta.
      for (final event in withheld) {
        yield event;
      }
    } catch (e) {
      // Una sesión guardada puede haber caducado, haberse borrado, o **vivir en
      // otra cuenta**: la memoria es por carpeta y las sesiones son de la pareja
      // carpeta + cuenta, así que cambiarle el perfil a una carpeta deja
      // apuntando a un sitio donde esa sesión no está. Ahí `--resume` falla y no
      // se recupera solo: sin esto, esa carpeta quedaba inservible para siempre
      // —cada encargo moría con «No conversation found with session ID»—.
      //
      // Perder la memoria es molesto; dejar al usuario sin respuesta por eso,
      // inaceptable. Se reintenta una vez sin ella, y el `init` del intento
      // bueno trae una sesión nueva que sustituye a la muerta, así que la
      // carpeta se cura sola.
      if (resumeSessionId != null && !emitted) {
        yield* ask(
          instruction,
          workingDirectory: workingDirectory,
          canEdit: canEdit,
          extraDirectories: extraDirectories,
          claudeProfile: claudeProfile,
          model: model,
          effort: effort,
          artifactsFolder: artifactsFolder,
          disallowedTools: disallowedTools,
        );
        return;
      }
      yield ClaudeFailed(e.toString());
    }
  }

  /// Cuánto contexto llevaba una petición.
  ///
  /// La caché cuenta: son tokens que ya están en la ventana aunque no se
  /// vuelvan a enviar, y no contarlos haría parecer vacía una conversación
  /// larga.
  static int _promptTokens(Map<String, dynamic> usage) {
    int count(String key) => (usage[key] as num?)?.toInt() ?? 0;
    return count('input_tokens') +
        count('cache_creation_input_tokens') +
        count('cache_read_input_tokens');
  }

  /// Traduce una línea de `stream-json` a los [ClaudeEvent] que la interfaz
  /// necesita, o a nada si es ruido (rate limits, contador de tokens de
  /// "thinking", el estado "requesting").
  ///
  /// Devuelve una lista y no un solo evento porque **un mensaje puede traer
  /// varias herramientas a la vez**: Claude pide leer tres archivos en el
  /// mismo turno y los tres llegan en el mismo `assistant`.
  List<ClaudeEvent> _decode(
    Map<String, dynamic> json,
    String workingDirectory,
  ) {
    switch (json['type']) {
      case 'system':
        if (json['subtype'] != 'init') return const [];
        return [
          ClaudeSessionStarted(
            sessionId: json['session_id'] as String? ?? '',
            model: json['model'] as String? ?? '',
          ),
        ];

      case 'stream_event':
        final event = json['event'] as Map<String, dynamic>?;
        if (event?['type'] != 'content_block_delta') return const [];
        final delta = event?['delta'] as Map<String, dynamic>?;
        if (delta?['type'] != 'text_delta') return const [];
        return [ClaudeTextDelta(delta?['text'] as String? ?? '')];

      // El texto de este mensaje ya llegó como `text_delta`; lo que aquí
      // interesa son los bloques `tool_use`, que traen el detalle completo
      // —qué archivo, qué comando— justo antes de ejecutarse.
      case 'assistant':
        final content =
            (json['message'] as Map<String, dynamic>?)?['content']
                as List<dynamic>?;
        // Verificado contra el binario: los pasos de un subagente llegan como
        // mensajes `assistant` normales, marcados con el `tool_use_id` de la
        // delegación que los originó. Sin leerlo, el trabajo del subagente
        // aparecía al mismo nivel que el del principal, indistinguible.
        final parentId = json['parent_tool_use_id'] as String?;
        return [
          for (final block in content ?? const [])
            if (block is Map<String, dynamic> && block['type'] == 'tool_use')
              ?ToolActivityReader.read(
                block,
                workingDirectory: workingDirectory,
                parentId: parentId,
              ),
        ];

      // El resultado de una herramienta vuelve como mensaje de usuario: es la
      // señal de que aquella acción terminó.
      case 'user':
        final content =
            (json['message'] as Map<String, dynamic>?)?['content']
                as List<dynamic>?;
        return [
          for (final block in content ?? const [])
            if (block is Map<String, dynamic> && block['type'] == 'tool_result')
              if (block['tool_use_id'] case final String id)
                ClaudeToolFinished(id, output: _resultText(block['content'])),
        ];

      case 'result':
        if (json['is_error'] == true) {
          return [
            ClaudeFailed(json['result'] as String? ?? 'Error desconocido'),
          ];
        }
        final usage = json['usage'] as Map<String, dynamic>? ?? const {};
        int count(String key) => (usage[key] as num?)?.toInt() ?? 0;
        final prompt = _promptTokens(usage);

        return [
          ClaudeTurnCompleted(
            result: json['result'] as String? ?? '',
            costUsd: (json['total_cost_usd'] as num?)?.toDouble(),
            durationMs: json['duration_ms'] as int?,
            turnTokens: prompt + count('output_tokens'),
            contextTokens: prompt,
          ),
        ];

      default:
        return const [];
    }
  }

  /// El resultado de una herramienta llega como texto suelto o como lista de
  /// bloques, según la herramienta. Se recorta aquí y no en la interfaz porque
  /// un `cat` de un archivo grande no tiene por qué viajar entero hasta la
  /// pantalla para acabar oculto detrás de unos puntos suspensivos.
  static String? _resultText(Object? content) {
    const limit = 1200;

    final raw = switch (content) {
      String text => text,
      List<dynamic> blocks =>
        blocks
            .whereType<Map<String, dynamic>>()
            .where((block) => block['type'] == 'text')
            .map((block) => block['text'] as String? ?? '')
            .join('\n'),
      _ => '',
    };

    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= limit
        ? trimmed
        : '${trimmed.substring(0, limit)}\n…';
  }
}

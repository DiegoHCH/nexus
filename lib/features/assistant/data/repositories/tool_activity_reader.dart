import 'package:nexus/features/assistant/domain/entities/claude_event.dart';

/// Traduce un bloque `tool_use` del CLI a una frase que se pueda leer de un
/// vistazo mientras el trabajo ocurre.
///
/// El texto imita al mockup —«Corriendo git status en front-mobile-b2c»,
/// «Leyendo lib/stocks/data/stocks_datasource.dart»— porque el objetivo de esta
/// columna no es auditar, es que dos minutos de trabajo no parezcan un cuelgue.
abstract final class ToolActivityReader {
  /// Herramientas que modifican archivos con seguridad. `Bash` no está: puede
  /// escribir o no, y marcarlo siempre de rojo enseñaría a ignorar el aviso.
  static const _writingTools = {'Write', 'Edit', 'MultiEdit', 'NotebookEdit'};

  /// Cuánto comando cabe antes de estorbar más de lo que informa.
  static const _maxCommandLength = 70;

  /// [parentId] es el `parent_tool_use_id` del mensaje: viene puesto cuando el
  /// paso lo dio un subagente, y es lo que permite colgarlo de la delegación
  /// que lo creó en vez de mezclarlo con los del principal.
  static ClaudeToolUsed? read(
    Map<String, dynamic> block, {
    required String workingDirectory,
    String? parentId,
  }) {
    final id = block['id'] as String?;
    final name = block['name'] as String?;
    if (id == null || name == null) return null;

    final input = block['input'] as Map<String, dynamic>? ?? const {};
    return ClaudeToolUsed(
      id: id,
      description: _describe(name, input, workingDirectory),
      writes: _writingTools.contains(name),
      detail: _detail(name, input),
      parentId: parentId,
    );
  }

  /// Lo que se ejecuta literalmente. Para `Bash` es el comando entero —que en
  /// la línea va recortado— y para el resto la ruta o el patrón completos.
  static String? _detail(String name, Map<String, dynamic> input) {
    final value = switch (name) {
      'Bash' => input['command'] as String?,
      'Read' ||
      'Write' ||
      'Edit' ||
      'MultiEdit' => input['file_path'] as String?,
      'Grep' || 'Glob' => input['pattern'] as String?,
      'WebFetch' => input['url'] as String?,
      // El encargo entero, que es lo único que cuenta qué se llevó el
      // subagente: su trabajo ocurre en otro contexto y de él solo vuelve el
      // resultado.
      'Task' || 'Agent' => input['prompt'] as String?,
      _ => null,
    };
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _describe(
    String name,
    Map<String, dynamic> input,
    String workingDirectory,
  ) {
    String path(String key) =>
        _relative(input[key] as String? ?? '', workingDirectory);

    return switch (name) {
      'Read' => 'Leyendo ${path('file_path')}',
      'Write' => 'Escribiendo ${path('file_path')}',
      'Edit' || 'MultiEdit' => 'Editando ${path('file_path')}',
      'NotebookEdit' => 'Editando ${path('notebook_path')}',
      // El comando, no la `description`. Esta última la escribe Claude en
      // inglés y produce líneas como «Corriendo Read repo registry», que
      // mezcla dos idiomas y encima miente sobre el verbo: la herramienta era
      // Bash. El mockup enseña el comando —«Corriendo git status»— y tiene
      // razón, porque es lo que de verdad se ejecuta.
      'Bash' =>
        'Corriendo ${_shorten(input['command'] as String? ?? input['description'] as String? ?? '')}',
      'Grep' => 'Buscando «${_shorten(input['pattern'] as String? ?? '')}»',
      'Glob' =>
        'Buscando archivos ${_shorten(input['pattern'] as String? ?? '')}',
      // Los dos nombres, no uno: el CLI llama a esta herramienta `Task` en
      // unas sesiones y `Agent` en otras. Atarse a uno deja la delegación
      // medio invisible según con cuál toque —salía como «Usando Agent», sin
      // decir qué encargó—, y delegar es justo lo que hay que ver: es trabajo
      // que se va a otro contexto.
      'Task' || 'Agent' => 'Delegando: ${_shorten(_delegationSummary(input))}',
      'WebFetch' => 'Consultando ${_shorten(input['url'] as String? ?? '')}',
      'WebSearch' =>
        'Buscando en la web «${_shorten(input['query'] as String? ?? '')}»',
      'TodoWrite' => 'Ordenando la lista de tareas',
      _ => 'Usando $name',
    };
  }

  /// Qué se delegó, en una línea. `description` es lo que Claude escribe para
  /// resumir el encargo; cuando no la manda se cae al tipo de subagente, y
  /// como último recurso a la primera línea del encargo — antes que dejar
  /// «Delegando:» sin nada detrás.
  static String _delegationSummary(Map<String, dynamic> input) {
    final description = (input['description'] as String?)?.trim();
    if (description != null && description.isNotEmpty) return description;

    final type = (input['subagent_type'] as String?)?.trim();
    if (type != null && type.isNotEmpty) return type;

    final prompt = (input['prompt'] as String?)?.trim() ?? '';
    if (prompt.isEmpty) return 'una tarea';
    final firstLine = prompt.split('\n').first.trim();
    return firstLine.isEmpty ? 'una tarea' : firstLine;
  }

  /// Rutas relativas a la carpeta de trabajo: la ruta absoluta ocupa media
  /// columna y la parte que identifica el archivo queda al final, fuera de la
  /// vista.
  static String _relative(String path, String workingDirectory) {
    if (path.isEmpty) return '';
    if (workingDirectory.isNotEmpty && path.startsWith(workingDirectory)) {
      final relative = path.substring(workingDirectory.length);
      return relative.startsWith('/') ? relative.substring(1) : relative;
    }
    return path;
  }

  static String _shorten(String value) {
    final flat = value.replaceAll('\n', ' ').trim();
    if (flat.length <= _maxCommandLength) return flat;
    return '${flat.substring(0, _maxCommandLength)}…';
  }
}

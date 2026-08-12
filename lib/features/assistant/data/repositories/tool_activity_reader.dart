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

  static ClaudeToolUsed? read(Map<String, dynamic> block, {required String workingDirectory}) {
    final id = block['id'] as String?;
    final name = block['name'] as String?;
    if (id == null || name == null) return null;

    final input = block['input'] as Map<String, dynamic>? ?? const {};
    return ClaudeToolUsed(
      id: id,
      description: _describe(name, input, workingDirectory),
      writes: _writingTools.contains(name),
      detail: _detail(name, input),
    );
  }

  /// Lo que se ejecuta literalmente. Para `Bash` es el comando entero —que en
  /// la línea va recortado— y para el resto la ruta o el patrón completos.
  static String? _detail(String name, Map<String, dynamic> input) {
    final value = switch (name) {
      'Bash' => input['command'] as String?,
      'Read' || 'Write' || 'Edit' || 'MultiEdit' => input['file_path'] as String?,
      'Grep' || 'Glob' => input['pattern'] as String?,
      'WebFetch' => input['url'] as String?,
      _ => null,
    };
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _describe(String name, Map<String, dynamic> input, String workingDirectory) {
    String path(String key) => _relative(input[key] as String? ?? '', workingDirectory);

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
      'Bash' => 'Corriendo ${_shorten(input['command'] as String? ?? input['description'] as String? ?? '')}',
      'Grep' => 'Buscando «${_shorten(input['pattern'] as String? ?? '')}»',
      'Glob' => 'Buscando archivos ${_shorten(input['pattern'] as String? ?? '')}',
      'Task' => 'Delegando: ${_shorten(input['description'] as String? ?? '')}',
      'WebFetch' => 'Consultando ${_shorten(input['url'] as String? ?? '')}',
      'WebSearch' => 'Buscando en la web «${_shorten(input['query'] as String? ?? '')}»',
      'TodoWrite' => 'Ordenando la lista de tareas',
      _ => 'Usando $name',
    };
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

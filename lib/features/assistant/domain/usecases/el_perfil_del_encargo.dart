import 'dart:convert';
import 'dart:io';

/// Bajo qué perfil de Claude Code corre un encargo, dicho en el prompt.
///
/// **Existe porque la sesión no lo sabía y lo adivinaba mal.** Nexus elige el
/// perfil por carpeta y lo pasa como `CLAUDE_CONFIG_DIR`, pero nada se lo decía
/// al modelo: preguntarle «¿qué versión del plugin tienes?» acababa en «vive en
/// `~/.claude/plugins` y no tengo acceso», con el plugin puesto en
/// `~/.claude-work` y el de fábrica sin sesión abierta siquiera. La respuesta no
/// era «no puedo»: era una carpeta equivocada dicha con seguridad.
///
/// Y no se arregla dándole acceso de lectura a la carpeta del perfil, que es lo
/// primero que apetece: ahí viven las credenciales, el historial de **todos**
/// los proyectos y las sesiones de las otras cuentas. Una carpeta de solo
/// lectura no puede abrir eso para contestar una pregunta de inventario. Lo que
/// hace falta lo sabe Nexus, así que lo dice Nexus.
abstract final class ElPerfilDelEncargo {
  /// La carpeta del perfil con el que va a correr el encargo.
  ///
  /// Repite la regla de `ClaudeEnvironment.forProfile` a propósito: sin perfil
  /// elegido **no se inventa la variable**, así que el CLI usa la que traiga el
  /// entorno y, si no trae ninguna, el directorio de fábrica. Decir aquí otra
  /// cosa sería nombrar en el prompt una carpeta distinta de la que se va a
  /// usar, que es el fallo original con el signo cambiado.
  static String? carpeta(String? configDir) {
    if (configDir != null && configDir.isNotEmpty) return configDir;
    final env = Platform.environment;
    final delEntorno = env['CLAUDE_CONFIG_DIR'];
    if (delEntorno != null && delEntorno.isNotEmpty) return delEntorno;
    final home = env['HOME'];
    return home == null || home.isEmpty ? null : '$home/.claude';
  }

  /// `null` si no se sabe ni la carpeta — y entonces callar es lo honesto.
  ///
  /// **Se lee del archivo y no del CLI**, igual que los permisos MCP y por el
  /// mismo motivo: esto va en la ruta de cada encargo y `claude plugin list`
  /// arranca un proceso. Para el catálogo el CLI es la única fuente —los
  /// marketplaces se clonan y se actualizan solos—, pero para el inventario de
  /// lo puesto el archivo **es** la fuente: es el que el propio CLI escribe.
  ///
  /// Y se lee **en cada encargo, sin caché**: poner un plugin con la app
  /// abierta tiene que valer para el siguiente encargo y no pedir un reinicio
  /// que nadie adivina.
  /// El texto va en español y a pelo **a propósito**: esto no se pinta, se
  /// concatena en el `appendSystemPrompt` de cada encargo. Es una instrucción
  /// para un modelo, no interfaz, y el idioma de los prompts es una decisión
  /// aparte — la misma que ya se tomó para la instrucción de sistema de la voz.
  static Future<String?> describir(String? configDir) async {
    final dir = carpeta(configDir);
    if (dir == null) return null;

    final puestos = await _plugins(dir);
    return 'Corres con el perfil de Claude Code $dir '
        '(es el `CLAUDE_CONFIG_DIR` de esta sesión), y esa carpeta no está entre '
        'las que puedes leer: lo que sigue es todo lo que sabes de ella. '
        '${puestos.isEmpty ? 'No tiene ningún plugin puesto.' : 'Plugins puestos: ${puestos.join(', ')}.'}';
  }

  /// Los plugins del perfil, como `id versión`.
  ///
  /// El formato es el `version: 2` del archivo: cada identificador apunta a una
  /// **lista** de instalaciones, una por alcance —`user`, `project`—, así que
  /// puede haber más de una del mismo plugin. Se enseñan todas con su alcance
  /// cuando pasa, porque «tengo la 0.2.179» y «tengo dos y una es vieja» son
  /// respuestas distintas.
  ///
  /// Cualquier sorpresa leyéndolo devuelve la lista vacía en vez de tumbar el
  /// encargo: el inventario es un extra del prompt, no el encargo.
  static Future<List<String>> _plugins(String dir) async {
    final file = File('$dir/plugins/installed_plugins.json');
    if (!file.existsSync()) return const [];
    try {
      final leido = jsonDecode(await file.readAsString());
      if (leido is! Map) return const [];
      final plugins = leido['plugins'];
      if (plugins is! Map) return const [];

      final lineas = <String>[];
      for (final entry in plugins.entries) {
        final instalaciones = entry.value;
        if (instalaciones is! List) continue;
        for (final instalacion in instalaciones) {
          if (instalacion is! Map) continue;
          final version = instalacion['version'];
          final scope = instalacion['scope'];
          lineas.add(
            '${entry.key}'
            '${version == null ? '' : ' $version'}'
            // El alcance solo cuando hay más de uno del mismo plugin: decir
            // «(user)» en el caso normal es ruido en un texto que viaja en cada
            // encargo.
            '${instalaciones.length > 1 && scope != null ? ' ($scope)' : ''}',
          );
        }
      }
      lineas.sort();
      return lineas;
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }
}

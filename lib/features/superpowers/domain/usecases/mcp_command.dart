import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';

/// Cómo se le habla al CLI para poner y quitar servidores, y cómo se lee lo que
/// contesta.
///
/// Se arma aquí y no en el data source para poder probarlo sin lanzar procesos:
/// un argumento mal puesto no falla, hace algo distinto —`-e` en el sitio
/// equivocado se lo come el comando del servidor— y eso no se ve mirándolo.
abstract final class McpCommand {
  /// Solo lo que el CLI acepta como nombre. Se comprueba antes de llamar
  /// porque estos argumentos acaban en un proceso: un nombre con espacios o
  /// comillas es la puerta de entrada a que la orden diga otra cosa.
  static bool validName(String name) =>
      RegExp(r'^[\w.-]{1,40}$').hasMatch(name);

  /// `claude mcp add -s user …`
  ///
  /// El alcance es **user** y no proyecto: aquí se configura la cuenta, que es
  /// la unidad que ya organiza el modelo, el esfuerzo y la memoria. Un servidor
  /// puesto por proyecto viviría en un `.mcp.json` dentro del repo, que es una
  /// decisión del repo y no de esta app.
  static List<String>? add({
    required String name,
    String? url,
    List<String> command = const [],
    List<String> env = const [],
  }) {
    if (!validName(name)) return null;

    if (url != null && url.trim().isNotEmpty) {
      return [
        'mcp',
        'add',
        '-s',
        'user',
        '--transport',
        'http',
        name,
        url.trim(),
      ];
    }
    if (command.isEmpty) return null;

    return [
      'mcp',
      'add',
      '-s',
      'user',
      name,
      // Las variables van **antes** del `--`: después, el CLI las toma por
      // argumentos del propio servidor y la clave de API acaba en su línea de
      // comandos en vez de en su entorno.
      for (final pair in env)
        if (validEnv(pair)) ...['-e', pair],
      '--',
      ...command,
    ];
  }

  static bool validEnv(String pair) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=.+$').hasMatch(pair);

  static List<String>? remove(String name) =>
      validName(name) ? ['mcp', 'remove', '-s', 'user', name] : null;

  /// Lo que devuelve `claude mcp list`: `nombre: destino - estado`.
  ///
  /// Se parsea con el nombre **no ávido** porque los conectores de la cuenta se
  /// llaman «claude.ai Atlassian Rovo» —con espacios— y sus destinos son URLs
  /// con `https://`, o sea con otros dos puntos dentro.
  static List<McpServer> parseList(String output) {
    final pattern = RegExp(r'^(.+?):\s+(\S+.*?)\s+-\s+(.+)$');
    final servers = <McpServer>[];

    for (final line in output.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) continue;
      final name = match.group(1)!.trim();
      servers.add(
        McpServer(
          name: name,
          spec: match.group(2)!.trim(),
          status: _statusOf(match.group(3)!),
          // Los de la cuenta llegan con la sesión de claude.ai y no están en el
          // archivo del perfil, así que no se pueden quitar desde aquí.
          fromAccount: name.startsWith('claude.ai '),
        ),
      );
    }
    return servers;
  }

  static McpStatus _statusOf(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('connected')) return McpStatus.connected;
    if (text.contains('auth')) return McpStatus.needsAuth;
    return McpStatus.failed;
  }
}

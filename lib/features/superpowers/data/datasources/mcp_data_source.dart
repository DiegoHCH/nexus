import 'dart:convert';
import 'dart:io';

import 'package:nexus/core/platform/binario_en_el_path.dart';
import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';
import 'package:nexus/features/superpowers/domain/usecases/mcp_command.dart';

/// Los servidores MCP de una cuenta.
///
/// Se **leen del archivo** y se **cambian por el CLI**, y esa asimetría es la
/// decisión: escribir el `.claude.json` a mano obligaría a reimplementar la
/// semántica de alcances de Claude Code —user, proyecto, local— y a mantenerla
/// al día con cada versión suya. Leerlo, en cambio, es instantáneo; pedirle la
/// lista al CLI tarda casi un minuto porque comprueba la salud de cada uno.
class McpDataSource {
  const McpDataSource();

  /// ¿Está el binario que pide un servidor de comando?
  ///
  /// Aquí y no en el panel aunque la cuenta la eche [BinarioEnElPath]: pasando por
  /// el data source entra por un provider, y una prueba de la pantalla puede
  /// decir que sí o que no sin depender de lo que haya instalado en el Mac que
  /// corre la suite.
  bool hayBinario(String nombre) => BinarioEnElPath.hay(nombre);

  /// La lista rápida: lo que hay puesto, sin saber si responde.
  Future<List<McpServer>> list(String configDir) async {
    final file = File('$configDir/.claude.json');
    if (!file.existsSync()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      final servers = decoded['mcpServers'];
      if (servers is! Map) return const [];

      return [
        for (final entry in servers.entries)
          McpServer(name: '${entry.key}', spec: _specOf(entry.value)),
      ];
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  /// La lista lenta: la que ve el CLI de verdad.
  ///
  /// Trae además **los conectores de la cuenta de claude.ai**, que no están en
  /// el archivo de ningún perfil y aquí son mayoría —en este Mac, quince frente
  /// a tres—. Sin esto, la pantalla diría que la cuenta tiene tres manos cuando
  /// tiene dieciocho.
  Future<List<McpServer>?> check(String configDir) async {
    try {
      final result = await Process.run(
        'claude',
        ['mcp', 'list'],
        environment: ClaudeEnvironment.forProfile(configDir),
        includeParentEnvironment: false,
      );
      if (result.exitCode != 0) return null;
      return McpCommand.parseList('${result.stdout}');
    } on ProcessException {
      return null;
    }
  }

  /// `null` si salió bien; el error del CLI si no.
  ///
  /// Se devuelve su texto en vez de un booleano porque lo que dice es
  /// accionable —«ya existe uno con ese nombre», «no se pudo resolver el
  /// comando»— y esconderlo detrás de «no se pudo» obliga a abrir la terminal
  /// para averiguar qué pasó.
  Future<String?> add(
    String configDir, {
    required String name,
    String? url,
    List<String> command = const [],
    List<String> env = const [],
  }) {
    final args = McpCommand.add(
      name: name,
      url: url,
      command: command,
      env: env,
    );
    return _run(configDir, args);
  }

  /// El mismo servidor en **varias cuentas de una vez**.
  ///
  /// Por lo mismo que las skills: un servidor puesto en un solo perfil no existe para
  /// las carpetas del otro, y el encargo corre con el perfil de su carpeta. La
  /// diferencia es que aquí el síntoma es peor de leer — «no puedo consultar tu
  /// calendario» no se parece a un problema de cuentas.
  ///
  /// Los errores van por cuenta: el CLI dice cosas accionables —«ya existe uno con ese
  /// nombre»— y da información que puesta en montón se pierde.
  Future<Map<String, String>> addEn(
    List<String> configDirs, {
    required String name,
    String? url,
    List<String> command = const [],
    List<String> env = const [],
  }) async {
    final fallos = <String, String>{};
    for (final configDir in configDirs) {
      final error = await add(
        configDir,
        name: name,
        url: url,
        command: command,
        env: env,
      );
      if (error != null) fallos[configDir] = error;
    }
    return fallos;
  }

  Future<String?> remove(String configDir, String name) =>
      _run(configDir, McpCommand.remove(name));

  Future<String?> _run(String configDir, List<String>? args) async {
    if (args == null) return 'Datos inválidos';
    try {
      final result = await Process.run(
        'claude',
        args,
        environment: ClaudeEnvironment.forProfile(configDir),
        includeParentEnvironment: false,
      );
      if (result.exitCode == 0) return null;
      final error = '${result.stderr}'.trim();
      return error.isEmpty ? '${result.stdout}'.trim() : error;
    } on ProcessException catch (error) {
      return error.message;
    }
  }

  static String _specOf(Object? server) {
    if (server is! Map) return '';
    final url = server['url'];
    if (url is String && url.isNotEmpty) return url;
    return [
      if (server['command'] case final command?) '$command',
      ...?(server['args'] as List?)?.map((arg) => '$arg'),
    ].join(' ');
  }
}

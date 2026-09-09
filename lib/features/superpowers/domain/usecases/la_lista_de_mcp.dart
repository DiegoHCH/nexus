import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';

/// La lista de servidores MCP de una cuenta, **junta**.
///
/// 🔴 **Reportado mirando la pantalla:** «no se están listando todos los MCP que
/// tengo en mi cuenta; solo se listan los de usuario y no los de claude.ai». Y
/// era exacto. Medido en este Mac, con el mismo perfil:
///
/// - `<perfil>/.claude.json` → `mcpServers`: **5**. Es lo que la pantalla
///   enseñaba, porque leer el archivo es instantáneo.
/// - `claude mcp list` → **20**: esos cinco y **quince conectores
///   `claude.ai …`** —Gmail, Slack, Calendar, Drive, Notion, Jira…—.
///
/// Los quince **no están en ningún archivo del perfil**: llegan con la sesión de
/// claude.ai, y el único rastro en disco es `claudeAiMcpEverConnected`, que es un
/// registro de «alguna vez conectó» —seis nombres de los quince— y no la lista.
/// Así que la pantalla no se dejaba nada por descuido: enseñaba la única lista
/// que podía leer sin pagar un minuto de espera.
///
/// El arreglo no es leer otro archivo, porque no existe: es **recordar** lo que
/// el CLI contestó la última vez y volver a preguntárselo por detrás. Con eso la
/// lista sale completa al abrir, y sin quedarse mirando un minuto.
abstract final class LaListaDeMcp {
  /// Cuánto vale lo recordado antes de volver a preguntar.
  ///
  /// Seis horas y no seis minutos: lo que cambia aquí lo cambias tú —conectar un
  /// conector en claude.ai, poner un servidor— y eso no pasa cada rato. Lo que
  /// sí pasa es abrir Ajustes varias veces en una tarde, y cada vez cuesta
  /// **casi un minuto** de procesos porque el CLI comprueba la salud de cada
  /// servidor, uno por uno.
  ///
  /// Y hay botón: quien acaba de conectar algo no espera seis horas, pulsa.
  static const seRecuerdaDurante = Duration(hours: 6);

  /// Si toca volver a preguntarle al CLI.
  ///
  /// Sin nada recordado, sí — es la primera vez y la lista estaría a medias, que
  /// es justo el fallo que esto viene a cerrar.
  static bool hayQuePreguntar(DateTime? comprobado, {DateTime? ahora}) {
    if (comprobado == null) return true;
    final momento = ahora ?? DateTime.now();
    return momento.difference(comprobado).abs() >= seRecuerdaDurante;
  }

  /// Los tres orígenes en una sola lista.
  ///
  /// **El archivo manda sobre lo recordado, y lo comprobado sobre los dos**: es
  /// el orden de lo más fresco. Un servidor que quitaste hace un minuto sigue en
  /// lo recordado de hace una hora, así que lo recordado **no puede añadir
  /// servidores tuyos** — solo los de la cuenta, que son los que el archivo no
  /// puede saber. Sin esa regla, quitar uno lo dejaba en pantalla hasta la
  /// siguiente comprobación, y con su botón de quitar puesto.
  ///
  /// Primero los tuyos y después los de la cuenta: sobre los tuyos se puede
  /// actuar —quitarlos— y sobre los otros no, y una lista mezclada obliga a
  /// mirar la etiqueta de cada fila para saber qué se puede tocar.
  static List<McpServer> junta({
    required List<McpServer> delArchivo,
    List<McpServer> recordados = const [],
    List<McpServer>? comprobados,
  }) {
    // Lo comprobado es la verdad entera del CLI: si está, sustituye a lo
    // recordado por completo en vez de sumarse —o un conector desconectado en
    // claude.ai seguiría apareciendo—.
    final deFuera = [
      for (final server in comprobados ?? recordados)
        if (server.fromAccount) server,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Y la salud, cuando se sabe, se le pega a los del archivo: son los mismos
    // servidores vistos por dos ventanas distintas.
    final salud = {
      for (final server in comprobados ?? const <McpServer>[])
        server.name: server.status,
    };

    return [
      for (final server in delArchivo)
        if (salud[server.name] case final estado?)
          McpServer(name: server.name, spec: server.spec, status: estado)
        else
          server,
      ...deFuera,
    ];
  }

  /// Cuántos de la lista son de la cuenta, para poder decirlo en una línea.
  static int deLaCuenta(List<McpServer> lista) =>
      lista.where((server) => server.fromAccount).length;
}

import 'dart:convert';
import 'dart:io';

/// Qué herramientas MCP puede usar un encargo, y cuáles no.
///
/// **Existe porque en headless nadie aprueba nada.** Con alguien delante, Claude pide
/// permiso para cada herramienta y se le concede; sin nadie —que es todo lo que hace
/// Nexus— la llamada se deniega sola. El síntoma no se parece a un problema de permisos:
/// se preguntaba «¿qué reuniones tengo hoy?» y contestaba que no podía consultar el
/// calendario, con el servidor de Calendar conectado y respondiendo. Medido: el mismo
/// `claude -p` con `--allowedTools mcp__claude_ai_Google_Calendar` contesta las reuniones
/// y sin él las deniega, y **el modo de permisos no influye** — con `acceptEdits` falla
/// igual, así que no es el interruptor de «puede editar».
abstract final class McpPermissions {
  /// Los servidores MCP de un perfil, tal como se nombran en las herramientas.
  ///
  /// Se leen **del archivo y no del CLI**: pedirle la lista a `claude mcp list` tarda
  /// casi un minuto porque comprueba la salud de cada servidor, y esto va en la ruta de
  /// cada encargo.
  ///
  /// Dos sitios y no uno: `mcpServers` son los que se configuraron a mano, y
  /// `claudeAiMcpEverConnected` los conectores de la cuenta de claude.ai — que **son
  /// mayoría y son los que importan** aquí (Calendar, Gmail, Drive, Slack). Mirar solo
  /// el primero deja fuera justo los que se querían usar.
  static List<String> servidoresDe(String? configDir) {
    if (configDir == null || configDir.isEmpty) return const [];
    final file = File('$configDir/.claude.json');
    if (!file.existsSync()) return const [];
    try {
      final leido = jsonDecode(file.readAsStringSync());
      if (leido is! Map) return const [];

      final nombres = <String>{};
      final propios = leido['mcpServers'];
      if (propios is Map) nombres.addAll(propios.keys.map((k) => '$k'));

      // Una **lista** y no un mapa, al contrario que la de arriba. Se acepta también
      // como mapa: el formato es de otro programa y puede cambiar de versión.
      final deLaCuenta = leido['claudeAiMcpEverConnected'];
      if (deLaCuenta is List) nombres.addAll(deLaCuenta.map((k) => '$k'));
      if (deLaCuenta is Map) nombres.addAll(deLaCuenta.keys.map((k) => '$k'));

      return [for (final n in nombres) comoSeLlamaLaHerramienta(n)];
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  /// El nombre del servidor tal como aparece en sus herramientas.
  ///
  /// **Los puntos y los espacios pasan a `_`, y el resto se queda.** No es «todo lo que
  /// no sea alfanumérico»: los guiones se conservan —`docs-context` da
  /// `mcp__docs-context__query-docs`— y lo que cambia es `claude.ai Google Calendar` →
  /// `claude_ai_Google_Calendar`. Sacado de los nombres reales de las herramientas, no
  /// de suponer una regla.
  static String comoSeLlamaLaHerramienta(String servidor) =>
      servidor.replaceAll(RegExp(r'[.\s]'), '_');

  /// Las herramientas MCP que **actúan fuera de la máquina**, para negarlas cuando la
  /// carpeta es de solo lectura.
  ///
  /// **Es una lista por nombre, así que es incompleta por naturaleza**, y conviene que
  /// eso quede dicho aquí y no descubrirlo el día que importe: lo que garantiza el modo
  /// de solo lectura es **el disco** —eso lo hace el CLI y está medido—, y hacia fuera
  /// de la máquina lo único que protege es esta lista. Un conector nuevo trae sus
  /// herramientas de escritura y no aparecerá aquí hasta que alguien lo añada.
  ///
  /// Se niegan por nombre completo porque el comodín no aplica: se probó
  /// `--allowedTools "mcp__*"` contra el CLI real y no autoriza nada.
  ///
  /// La denegación gana al permiso —también probado—, así que permitir el servidor entero
  /// y negar estas es seguro y no hay que enumerar las de lectura.
  static const escrituraDeFuera = <String>[
    // Calendario: crear o borrar una reunión le llega a otras personas.
    'mcp__claude_ai_Google_Calendar__create_event',
    'mcp__claude_ai_Google_Calendar__delete_event',
    'mcp__claude_ai_Google_Calendar__update_event',
    'mcp__claude_ai_Google_Calendar__respond_to_event',
    // Correo: mandar es irreversible, y lo demás cambia lo que otro ve.
    'mcp__claude_ai_Gmail__send_message',
    'mcp__claude_ai_Gmail__reply',
    'mcp__claude_ai_Gmail__forward',
    'mcp__claude_ai_Gmail__create_draft',
    'mcp__claude_ai_Gmail__update_draft',
    'mcp__claude_ai_Gmail__trash_message',
    'mcp__claude_ai_Gmail__trash_thread',
    // Drive: escribe y, peor, comparte.
    'mcp__claude_ai_Google_Drive__create_file',
    'mcp__claude_ai_Google_Drive__update_file',
    'mcp__claude_ai_Google_Drive__copy_file',
    'mcp__claude_ai_Google_Drive__trash_file',
    'mcp__claude_ai_Google_Drive__share_file',
    // Slack: escribir en un canal lo lee un equipo.
    'mcp__claude_ai_Slack__slack_send_message',
    'mcp__claude_ai_Slack__slack_send_message_draft',
    'mcp__claude_ai_Slack__slack_schedule_message',
    'mcp__claude_ai_Slack__slack_create_conversation',
    'mcp__claude_ai_Slack__slack_create_canvas',
    'mcp__claude_ai_Slack__slack_update_canvas',
    'mcp__claude_ai_Slack__slack_add_reaction',
    // Jira y Confluence: quedan en el historial de un ticket de otro.
    'mcp__claude_ai_Atlassian_Rovo__createJiraIssue',
    'mcp__claude_ai_Atlassian_Rovo__editJiraIssue',
    'mcp__claude_ai_Atlassian_Rovo__addCommentToJiraIssue',
    'mcp__claude_ai_Atlassian_Rovo__transitionJiraIssue',
    'mcp__claude_ai_Atlassian_Rovo__addWorklogToJiraIssue',
    'mcp__claude_ai_Atlassian_Rovo__createConfluencePage',
    'mcp__claude_ai_Atlassian_Rovo__updateConfluencePage',
    'mcp__claude_ai_Atlassian_Rovo__createConfluenceFooterComment',
    'mcp__claude_ai_Atlassian_Rovo__createConfluenceInlineComment',
    'mcp__claude_ai_Atlassian_Rovo__createIssueLink',
  ];
}

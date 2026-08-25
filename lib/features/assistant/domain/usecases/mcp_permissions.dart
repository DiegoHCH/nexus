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
  /// Los servidores MCP de un perfil, **separados por procedencia**.
  ///
  /// Se leen **del archivo y no del CLI**: pedirle la lista a `claude mcp list` tarda
  /// casi un minuto porque comprueba la salud de cada servidor, y esto va en la ruta de
  /// cada encargo. Y se lee **en cada encargo, sin caché**, para que un servidor
  /// instalado con la app abierta entre en el siguiente en vez de pedir un reinicio que
  /// nadie adivina.
  ///
  /// Dos sitios y no uno, y ahí estaba media causa del fallo: `mcpServers` son los que
  /// se configuraron a mano y `claudeAiMcpEverConnected` los conectores de la cuenta de
  /// claude.ai — que **son mayoría y son los que importan** (Calendar, Gmail, Drive,
  /// Slack). Mirar solo el primero deja fuera justo los que se querían usar.
  ///
  /// La separación no es burocrática: los del usuario suelen ser procesos locales
  /// —documentación, memoria— y los conectores **actúan sobre servicios de fuera**. El
  /// riesgo de conceder de más está todo en los segundos.
  ///
  /// La distinción no es burocrática: los de `mcpServers` los puso el usuario a mano y
  /// suelen ser procesos locales —documentación, memoria—, mientras los conectores de la
  /// cuenta **actúan sobre servicios de fuera**: correo, calendario, canales de un
  /// equipo. El riesgo de conceder de más está todo en los segundos.
  static ({List<String> propios, List<String> deLaCuenta}) porProcedencia(
    String? configDir,
  ) {
    if (configDir == null || configDir.isEmpty) {
      return (propios: const [], deLaCuenta: const []);
    }
    final file = File('$configDir/.claude.json');
    if (!file.existsSync()) return (propios: const [], deLaCuenta: const []);
    try {
      final leido = jsonDecode(file.readAsStringSync());
      if (leido is! Map) return (propios: const [], deLaCuenta: const []);

      final propios = <String>{};
      final suyos = leido['mcpServers'];
      if (suyos is Map) propios.addAll(suyos.keys.map((k) => '$k'));

      final deLaCuenta = <String>{};
      final conectores = leido['claudeAiMcpEverConnected'];
      if (conectores is List) deLaCuenta.addAll(conectores.map((k) => '$k'));
      if (conectores is Map) {
        deLaCuenta.addAll(conectores.keys.map((k) => '$k'));
      }

      return (
        propios: [for (final n in propios) comoSeLlamaLaHerramienta(n)],
        deLaCuenta: [for (final n in deLaCuenta) comoSeLlamaLaHerramienta(n)],
      );
    } on FormatException {
      return (propios: const [], deLaCuenta: const []);
    } on FileSystemException {
      return (propios: const [], deLaCuenta: const []);
    }
  }

  /// Los conectores cuyas escrituras están catalogadas en [escrituraDeFuera].
  ///
  /// Sale de los nombres de esa lista, así que desde que hay ahí una herramienta
  /// de un servidor propio —`maestro`— este conjunto trae también su nombre. Es
  /// inocuo y conviene decir por qué: esto solo filtra los conectores de la
  /// cuenta, que llegan con el prefijo `claude.ai `, y ninguno se llama así.
  ///
  /// De aquí sale la regla que cierra el agujero: **un conector nuevo no se autoriza en
  /// una carpeta de solo lectura hasta que se sepa qué escribe.** Antes se autorizaba
  /// entero, así que instalar un conector mañana podía escribir hacia fuera desde una
  /// carpeta que promete no escribir — la lista de negación es por nombre y no puede
  /// adivinar herramientas que no conoce.
  ///
  /// Falla del lado seguro y no del cómodo: se pierde que el conector nuevo funcione en
  /// solo lectura —en una carpeta que puede escribir va igual— y se gana que la promesa
  /// de solo lectura no dependa de que alguien se acuerde de actualizar una lista.
  static Set<String> get conectoresCatalogados => {
    for (final herramienta in escrituraDeFuera) herramienta.split('__')[1],
  };

  /// Los servidores que puede usar un encargo, según si la carpeta puede escribir.
  ///
  /// Los del propio usuario van siempre: los eligió él y son procesos suyos. Los
  /// conectores de la cuenta van todos si la carpeta puede escribir, y solo los
  /// catalogados si no — ver [conectoresCatalogados].
  static List<String> permitidosPara(
    String? configDir, {
    required bool puedeEscribir,
  }) {
    final (propios: propios, deLaCuenta: deLaCuenta) = porProcedencia(
      configDir,
    );
    final catalogados = conectoresCatalogados;
    return [
      ...propios,
      ...deLaCuenta.where((c) => puedeEscribir || catalogados.contains(c)),
    ];
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
    // **Maestro, que no es un conector de la cuenta y aun así sale de la
    // máquina.** Todo lo suyo es local —mirar la pantalla del emulador, correr un
    // flow— salvo esta: `run_on_cloud` **sube el binario de la app** a los
    // servidores de mobile.dev para ejecutarla allí. Una carpeta que promete no
    // escribir no puede mandar fuera lo que compiló.
    //
    // Es la primera de esta lista que no viene de `claude.ai `, y eso descoloca
    // un poco al leerla: los servidores del propio usuario van permitidos siempre
    // —ver [permitidosPara]—, así que para uno suyo la única forma de recortarle
    // una herramienta es negarla aquí. La denegación gana al permiso, medido.
    'mcp__maestro__run_on_cloud',
  ];
}

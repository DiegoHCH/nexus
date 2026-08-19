/// Un servidor MCP configurado en una cuenta.
///
/// Un MCP es lo que le da a Claude manos fuera del disco: Jira, Slack, un
/// navegador, la documentación de una librería. Se configuran por cuenta —igual
/// que el modelo o el esfuerzo— y hasta ahora Nexus los usaba sin poder
/// enseñarlos: este Mac ya tenía tres puestos en `work`.
class McpServer {
  const McpServer({
    required this.name,
    required this.spec,
    this.status = McpStatus.unknown,
    this.fromAccount = false,
  });

  final String name;

  /// La URL, o el comando con sus argumentos. Lo que identifica al servidor
  /// para quien lo mira: dos con el mismo nombre y distinto destino son cosas
  /// distintas.
  final String spec;

  final McpStatus status;

  /// Los conectores de la cuenta de claude.ai, que llegan con la sesión y **no
  /// están en el archivo del perfil**. Se marcan porque no se pueden quitar
  /// desde aquí: se gestionan en claude.ai, y ofrecer un botón que no funciona
  /// sería peor que no ofrecerlo.
  final bool fromAccount;
}

enum McpStatus {
  /// Se leyó del archivo y no se ha comprobado. Es el estado normal de la
  /// lista rápida: comprobar la salud de todos tarda casi un minuto.
  unknown,
  connected,

  /// Contesta, pero hay que iniciar sesión en él.
  needsAuth,
  failed,
}

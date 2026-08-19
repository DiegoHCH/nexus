/// Una entrada del catálogo: un servidor que se puede poner de un clic.
class McpCatalogEntry {
  const McpCatalogEntry({
    required this.name,
    required this.what,
    this.url,
    this.command = const [],
  });

  final String name;

  /// Para qué sirve, en una línea. Sin esto la lista es una fila de nombres
  /// propios que no dicen nada a quien no los conoce ya.
  final String what;

  final String? url;
  final List<String> command;
}

/// Los cuatro que se ofrecen hechos.
///
/// **Corto y verificado, a propósito.** La Oficina tuvo que retirar una entrada
/// —Nano Banana— después de comprobar contra la API que el <i>free tier</i> de
/// imagen que prometía no existe: la ficha ofrecía 500 imágenes gratis al día y
/// solo llevaba a un 429 seguro. La lección que se hereda no es su lista, es
/// que un catálogo curado hay que comprobarlo o se convierte en una lista de
/// promesas.
///
/// Comprobado el 13 ago 2026 contra el registro de npm: `@playwright/mcp`
/// 0.0.79, `chrome-devtools-mcp` 1.7.0, `@upstash/context7-mcp` 4.0.2 y
/// `@modelcontextprotocol/server-filesystem` 2026.7.10 existen y publican
/// versión. Lo que no se comprueba desde aquí es que **funcionen** en tu Mac:
/// eso lo dice el botón de comprobar, que pregunta al CLI de verdad.
abstract final class McpCatalog {
  static const entries = [
    McpCatalogEntry(
      name: 'context7',
      what: 'La documentación al día de cualquier librería',
      command: ['npx', '-y', '@upstash/context7-mcp'],
    ),
    McpCatalogEntry(
      name: 'playwright',
      what: 'Abrir un navegador y usar tu web como la usarías tú',
      command: ['npx', '@playwright/mcp@latest'],
    ),
    McpCatalogEntry(
      name: 'chrome-devtools',
      what: 'Mirar la consola y la red de Chrome mientras depura',
      command: ['npx', 'chrome-devtools-mcp@latest'],
    ),
    McpCatalogEntry(
      name: 'figma',
      what: 'Leer un diseño de Figma sin salir de la conversación',
      url: 'https://mcp.figma.com/mcp',
    ),
  ];
}

/// Una entrada del catálogo: un servidor que se puede poner de un clic.
class McpCatalogEntry {
  const McpCatalogEntry({
    required this.name,
    required this.what,
    this.url,
    this.command = const [],
    this.comoSeInstala,
  });

  final String name;

  /// Para qué sirve, en una línea. Sin esto la lista es una fila de nombres
  /// propios que no dicen nada a quien no los conoce ya.
  final String what;

  final String? url;
  final List<String> command;

  /// Cómo se instala el binario que pide, **cuando no se instala solo**.
  ///
  /// Los de `npx` no lo necesitan: la primera ejecución se lo baja. Esto es para
  /// el que hay que haber instalado antes, y se guarda aquí porque el sitio donde
  /// hace falta —el aviso de que falta— no tiene por qué saberse las
  /// instrucciones de nadie.
  final String? comoSeInstala;
}

/// Los cinco que se ofrecen hechos.
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
///
/// `maestro` se comprobó el 25 ago 2026 contra su documentación, y no contra
/// npm porque no está ahí: se instala aparte y `claude mcp add maestro --
/// maestro mcp` es la forma que documentan. Es **el único del catálogo que
/// exige un binario previo**, y de ahí sale [McpCatalogEntry.comoSeInstala].
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
    // **El playwright del móvil**, y se pone al lado suyo a propósito: es la
    // misma frase con un emulador en vez de un navegador, y quien entiende para
    // qué quiere el uno entiende el otro sin que nadie le explique qué es un
    // flow.
    //
    // Lo que lo hace valer aquí es que su herramienta `run` acepta YAML **en la
    // llamada**, sin archivo. Así una prueba no se escribe a ciegas para ver
    // luego si pasa: se mira la pantalla, se prueba un paso, se corrige, y solo
    // lo que ya pasa se guarda en `.maestro/`. Ese bucle cerrado es el que
    // convierte dictar en voz alta «entra con el usuario de pruebas y comprueba
    // que llega al listado» en una prueba que existe.
    //
    // Dos límites que conviene saber antes de instalarlo, no después: en iOS
    // **solo simulador** —dispositivo físico no—, y el emulador tiene que estar
    // arrancado, que eso sí lo puede hacer Claude por Bash.
    McpCatalogEntry(
      name: 'maestro',
      what:
          'Manejar tu app móvil en un emulador y escribir las pruebas mirándola',
      command: ['maestro', 'mcp'],
      comoSeInstala: 'curl -fsSL "https://get.maestro.mobile.dev" | bash',
    ),
  ];
}

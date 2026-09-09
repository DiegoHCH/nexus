/// Los comandos que se escriben con barra, y **la lista que los cuenta**.
///
/// 🔴 **Nace de una pregunta que no tenía respuesta dentro de la app:** «qué
/// comandos de terminal puedo usar dentro de Nexus, como el `/clear` de
/// Claude». Los había —`!git`, `/imagen`, `/edita`— y estaban solo **en el
/// código**: para saber qué se puede escribir había que leer el enrutado o
/// preguntar. Un atajo que no se puede descubrir es un atajo que no existe.
///
/// Así que hay dos cosas aquí, y la segunda es la que importa:
///
/// 1. Los dos comandos nuevos: `/ayuda`, que enseña esta lista **dentro** de la
///    conversación, y `/olvida`, que es el `/clear` de Claude Code — lo mismo
///    que el botón «Empezar de cero».
/// 2. **El catálogo**, que es de donde sale la ayuda. Una lista escrita a mano
///    en otro sitio se queda vieja el día que alguien añada un atajo, y una
///    ayuda desfasada es peor que ninguna: manda a escribir cosas que no
///    funcionan. Aquí la ayuda **se genera** de lo mismo que reconoce el
///    enrutado, y una prueba comprueba que no falte ninguno.
enum ElComandoDeLaCasa {
  /// La lista, dentro de la app.
  ayuda(['/ayuda', '/help', '/comandos'], conTexto: false),

  /// Empezar de cero en esta carpeta: el `/clear` de la terminal.
  ///
  /// **Se llama `olvida` y acepta `clear`** porque las dos formas llegan: quien
  /// viene de la terminal escribe la segunda sin pensarlo.
  olvida(['/olvida', '/clear', '/olvidar'], conTexto: false),

  /// El parte del día. Ya se pedía hablando —«dame el parte»—, y con barra es
  /// explícito: no depende de acertar la frase.
  parte(['/parte', '/daily'], conTexto: false),

  /// La agenda de hoy, por lo mismo.
  agenda(['/agenda', '/reuniones'], conTexto: false),

  /// Los servidores MCP de la cuenta de esta carpeta, con su estado.
  ///
  /// 🔴 **Pedido con la referencia delante:** «quisiera escribir el `/mcp` y
  /// que me mostrara el listado de MCP en el chat, así como se hace en el CLI,
  /// con su conectado o desconectado». Estaban en Ajustes, y eso es levantarse
  /// de la conversación para responder una pregunta de una línea.
  mcp(['/mcp', '/mcps'], conTexto: false),

  /// Dibujar desde cero. Vive en [LoQueSePideDibujar] —lo reconoce él— y aquí
  /// solo está para que la ayuda lo cuente.
  imagen(['/imagen', '/img'], conTexto: true),

  /// Seguir con la última imagen.
  edita(['/edita', '/editar'], conTexto: true),

  /// Correr git aquí mismo. El único con `!`, y también ajeno: lo reconoce
  /// [ElComandoDirecto].
  git(['!git'], conTexto: true);

  const ElComandoDeLaCasa(this.formas, {required this.conTexto});

  /// Cómo se puede escribir. La primera es la que enseña la ayuda; las demás se
  /// aceptan igual — un atajo que solo entiende una forma de decirse obliga a
  /// recordar cuál, que es justo lo que un atajo viene a evitar.
  final List<String> formas;

  /// Si lleva algo escrito detrás. `/imagen un gato` lo lleva; `/ayuda` no, y
  /// exigirle un espacio y un texto lo dejaría sin funcionar solo.
  final bool conTexto;

  String get comoSeEscribe => formas.first;

  /// El comando que es esta frase, o `null`.
  ///
  /// Los que llevan texto **no** se reconocen aquí: de eso ya se encargan sus
  /// dueños —`LoQueSePideDibujar`, `ElComandoDirecto`— y reconocerlos dos veces
  /// sería tener la precedencia escrita en dos sitios, que es exactamente el
  /// fallo que este repo ya midió tres veces.
  static ElComandoDeLaCasa? deLaFrase(String frase) {
    final limpia = frase.trim().toLowerCase();
    if (limpia.isEmpty) return null;
    for (final comando in values) {
      if (comando.conTexto) continue;
      for (final forma in comando.formas) {
        // Exacto y no por prefijo: `/parte` es el comando y «/parte de lo que
        // hablamos ayer» es otra cosa, que va a Claude como cualquier frase.
        if (limpia == forma) return comando;
      }
    }
    return null;
  }

  /// Los que la ayuda enseña, en el orden en que se enseñan: primero los que se
  /// usan a diario.
  static const enLaAyuda = [
    imagen,
    edita,
    git,
    parte,
    agenda,
    mcp,
    olvida,
    ayuda,
  ];

  /// La lista, ya escrita.
  ///
  /// **Recibe los textos en vez de conocerlos**: el idioma se elige en Ajustes
  /// y esto es dominio. Y se compone del propio catálogo, así que un atajo
  /// nuevo aparece en la ayuda sin que nadie se acuerde de añadirlo — que es
  /// todo el motivo de que el catálogo exista.
  ///
  /// Las formas alternativas van entre paréntesis: `/clear` es lo que escribe
  /// quien viene de la terminal, y no decirlo lo dejaría probando a ciegas.
  static String laLista(
    String titulo,
    String Function(ElComandoDeLaCasa comando) queHace,
  ) {
    final lineas = [
      for (final comando in enLaAyuda)
        '· ${comando.comoSeEscribe}'
            '${comando.conTexto ? ' …' : ''}'
            '${comando.formas.length > 1 ? ' (${comando.formas.skip(1).join(', ')})' : ''}'
            ' — ${queHace(comando)}',
    ];
    return '$titulo\n${lineas.join('\n')}';
  }
}

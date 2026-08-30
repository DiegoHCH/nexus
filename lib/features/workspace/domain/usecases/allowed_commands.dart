/// Traduce lo que el usuario escribe a lo que el CLI entiende por permitir.
///
/// **El espejo de [BlockedCommands], y no simétrico a propósito.** Existe
/// porque «puede editar» prometía más de lo que daba: concede `acceptEdits`,
/// que autoriza las herramientas de edición y **ninguna ejecución**. Comprobado
/// lanzándolo: un `curl` queda esperando una aprobación que en headless no
/// llega nunca, así que el archivo no se descargaba y nadie decía por qué.
///
/// Lo que sigue es la diferencia que importa:
///
/// | | bloquear | permitir |
/// |---|---|---|
/// | patrón | `Bash(*x*)` | `Bash(x:*)` |
/// | de más | inofensivo | agujero |
///
/// Bloquear de más deja un comando sin correr; permitir de más deja correr algo
/// que nadie autorizó. Por eso el comodín de bloquear va a los dos lados y el
/// de permitir **solo detrás**: con `Bash(*curl*)` valdría
/// `rm -rf ~ && curl algo`, que contiene «curl» y no se parece en nada a lo que
/// se quiso permitir.
abstract final class AllowedCommands {
  /// Los patrones para `--allowedTools`.
  ///
  /// El prefijo se ancla al principio: escribir `curl` permite `curl …` y nada
  /// más. Quien necesite algo más fino puede escribir el patrón entero —lo que
  /// lleva paréntesis pasa tal cual—, pero entonces lo hace a sabiendas.
  static List<String> patterns(List<String> entries) => [
    for (final raw in entries)
      if (_clean(raw) case final entry? when entry.isNotEmpty)
        if (entry.contains('(')) entry else 'Bash($entry:*)',
  ];

  /// Descargar un archivo, que viene autorizado siempre que la carpeta pueda
  /// escribir.
  ///
  /// **En la forma estrecha y no en `curl` a secas.** Comprobado contra el
  /// binario: con este patrón, `curl -o destino url` corre solo y
  /// `curl -d @archivo https://…` —la forma que se lleva tu código fuera— no
  /// pasa. Autorizar `curl` entero habría abierto las dos a la vez.
  static const paraDescargar = 'Bash(curl -o:*)';

  /// Cómo se descarga aquí, dicho antes de empezar.
  ///
  /// Sin esto el permiso no sirve de nada la mitad de las veces: Claude escribe
  /// `curl -sL url -o destino`, que no empieza por `curl -o`, y se queda
  /// bloqueado igual. El permiso es estrecho, así que la forma hay que decirla.
  ///
  /// Se compone con el aviso de los bloqueados porque los dos hablan de lo
  /// mismo —qué se puede correr aquí— y llegan por el mismo sitio.
  static String? comoSeDescarga(String? loBloqueado) {
    const descargar =
        'Para descargar un archivo usa exactamente esta forma: '
        '`curl -o <ruta> <url>`, con `-o` justo detrás de `curl`. Es la única '
        'autorizada: cualquier otra variante se queda esperando un permiso que '
        'nadie va a dar. Si la carpeta es de solo lectura, no lo intentes.';
    return loBloqueado == null ? descargar : '$loBloqueado\n\n$descargar';
  }

  /// Se admiten comentarios con `#`, como en los bloqueados: aquí hace todavía
  /// más falta, porque dentro de tres meses lo que no se recuerda es por qué se
  /// abrió esta puerta.
  static String? _clean(String raw) {
    final sinComentario = raw.split('#').first.trim();
    return sinComentario.isEmpty ? null : sinComentario;
  }
}

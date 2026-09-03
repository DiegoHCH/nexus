import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// A qué carpeta va lo que se acaba de decir.
sealed class AQueCarpetaVa {
  const AQueCarpetaVa();
}

/// No se nombró ninguna: va donde vaya por defecto, que decide quien llama.
final class NoSeNombroCarpeta extends AQueCarpetaVa {
  const NoSeNombroCarpeta();
}

/// Se nombró una, y con qué hay que hacer allí.
final class AEstaCarpeta extends AQueCarpetaVa {
  const AEstaCarpeta(this.carpeta, this.tarea);

  final PairedFolder carpeta;

  /// Lo que queda de la frase al quitarle la mención.
  ///
  /// **Puede venir vacía**, y es un caso legítimo y no un error: decir «en el
  /// front mobile» es pedir el cambio de carpeta y nada más. Quien llama decide
  /// si eso es enfocar y esperar o preguntar qué hacer.
  ///
  /// 🔴 **Lo que se quita es el puntero, no el verbo.** «Vete al front mobile»
  /// deja `vete`, y eso es deliberado: adivinar qué verbos son de ir y cuáles
  /// son la tarea es justo la clase de listeza que acaba tragándose un encargo
  /// de verdad. Quien llame decide qué hacer con un resto así — es él quien
  /// sabe si venía de la voz o del teclado.
  final String tarea;
}

/// Se nombró más de una. **No se elige ninguna**, a propósito.
final class SeNombraronVarias extends AQueCarpetaVa {
  const SeNombraronVarias(this.carpetas);
  final List<PairedFolder> carpetas;
}

/// Enrutar por voz sin escucha continua.
///
/// 🔴 **Es el 80 % del valor del spike sin pagar su nudo.** `docs/SPIKE-ESCUCHA.md`
/// cierra diciendo justo esto: «el enrutador por voz —"en qué carpeta" y "qué
/// tarea"— se puede construir y probar con `⌥Espacio` y sin escucha continua. Es
/// el 80 % del valor sin pagar el nudo del micrófono, y el día que la escucha
/// exista, ya la espera».
///
/// Hoy hay que elegir la carpeta a mano **antes** de hablar, y de la carpeta
/// cuelga todo: la cuenta, el modelo, los permisos y el prompt. Decir «en el
/// front mobile, arregla el login» ya dice dónde, y obligar a repetirlo en un
/// desplegable es hacer repetir lo que ya se dijo.
abstract final class ACarpetaVaLoQueDices {
  /// Nombres demasiado cortos no se buscan.
  ///
  /// Mismo criterio y mismo número que [RepoFromInstruction]: una carpeta
  /// llamada `ui` aparecería dentro de cualquier palabra que la contenga, y
  /// enrutar a la carpeta equivocada es peor que no enrutar — desde la que
  /// tocaba se ve todo y desde la que no, nada de lo que importa.
  static const minimoDelNombre = 4;

  static AQueCarpetaVa de(String frase, List<PairedFolder> carpetas) {
    final plano = _aplanar(frase);
    final hallazgos = <({PairedFolder carpeta, int desde, int hasta})>[];

    for (final carpeta in carpetas) {
      final nombre = carpeta.path.split('/').last;
      if (_aplanar(nombre).replaceAll(_separadores, '').length <
          minimoDelNombre) {
        continue;
      }
      final donde = _patronDe(nombre)?.firstMatch(plano);
      if (donde == null) continue;
      hallazgos.add((carpeta: carpeta, desde: donde.start, hasta: donde.end));
    }

    if (hallazgos.isEmpty) return const NoSeNombroCarpeta();
    if (hallazgos.length > 1) {
      return SeNombraronVarias([for (final h in hallazgos) h.carpeta]);
    }

    final hallazgo = hallazgos.single;
    return AEstaCarpeta(
      hallazgo.carpeta,
      _sinLaMencion(frase, hallazgo.desde, hallazgo.hasta),
    );
  }

  static final _separadores = RegExp(r'[\s_\-.]+');

  /// Las palabras que solo estaban ahí para introducir la carpeta.
  ///
  /// Se quitan **solo si van pegadas a la mención**: «en el front mobile,
  /// arregla el login» pierde el «en el», pero «mira en el archivo de
  /// configuración» no pierde nada, porque ahí ese «en» no introducía ninguna
  /// carpeta.
  static final _introducen = RegExp(
    r'(?:\b(?:dentro de|en|del|de|para|sobre|hacia|al|a|in|on|at|to)\b\s+)?'
    r'(?:\b(?:el|la|los|las|the)\b\s+)?$',
  );

  /// Igual de largo que el original, para que el tramo encontrado sirva para
  /// cortar. Bajar acentos uno a uno lo consigue; quitar separadores, no.
  static String _aplanar(String texto) {
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var plano = texto.toLowerCase();
    acentos.forEach((con, sin) => plano = plano.replaceAll(con, sin));
    return plano;
  }

  /// El nombre, tolerando cómo se diga.
  ///
  /// 🔴 **Por voz la transcripción nunca trae los guiones.** `front-mobile-b2c`
  /// se dice «front mobile b2c» y se escribe de las dos formas, así que entre
  /// una palabra y la siguiente vale cualquier separador o ninguno.
  ///
  /// Y con borde a los lados: sin él, una carpeta llamada `core` se encontraría
  /// dentro de «corrige el corenlace», que no la nombraba.
  static RegExp? _patronDe(String nombre) {
    final trozos = _aplanar(nombre)
        .split(_separadores)
        .where((t) => t.isNotEmpty)
        .map(RegExp.escape)
        .toList();
    if (trozos.isEmpty) return null;
    return RegExp(
      r'(?<![a-z0-9])' + trozos.join(r'[\s_\-.]*') + r'(?![a-z0-9])',
    );
  }

  static String _sinLaMencion(String frase, int desde, int hasta) {
    final antes = frase.substring(0, desde);
    final despues = frase.substring(hasta);
    final limpio =
        antes.replaceFirst(_introducen, '') +
        despues.replaceFirst(RegExp(r'^\s*[,:;]\s*'), ' ');
    return limpio.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

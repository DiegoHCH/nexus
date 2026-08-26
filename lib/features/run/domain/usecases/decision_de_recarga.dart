/// Qué hacer con la app corriendo después de un cambio.
enum QueHacer {
  /// El cambio se ve con un hot reload.
  recargar,

  /// Hace falta reiniciar: el reload vuelve a ejecutar `build()` pero **no** los
  /// inicializadores globales ni el `initState` de un `State` que ya existe.
  reiniciar,

  /// No hay recarga posible: toca volver a compilar.
  recompilar,
}

/// La decisión, con el motivo para poder decirlo.
class DecisionDeRecarga {
  const DecisionDeRecarga(this.que, [this.motivo]);

  final QueHacer que;

  /// Por qué. Se enseña porque «reinicié en vez de recargar» sin motivo parece
  /// un capricho de la herramienta.
  final String? motivo;
}

/// **Equivocarse aquí es peor que no recargar.** Si hacía falta reiniciar y solo
/// se recarga, el usuario mira una app que no cambió sin saber por qué, y lo
/// siguiente que hace es dudar del cambio que acaba de pedir. Así que ante la
/// duda se sube de nivel, nunca se baja.
///
/// Se mira **solo lo que cambió** —las líneas `+`/`-` del diff— y no el archivo
/// entero: buscar «class» en un archivo Dart completo daría reinicio casi
/// siempre, porque casi todo archivo Dart declara clases.
///
/// Los patrones vienen medidos de `la-oficina`, que ya pagó este aprendizaje.
abstract final class QueHacerConElCambio {
  /// Lo que no se puede recargar de ninguna manera: si se toca, hay que
  /// recompilar. Nativo, `pubspec.yaml` y los archivos de las plataformas.
  static final rutasQuePidenCompilar = RegExp(
    r'(^|/)pubspec\.yaml$'
    r'|(^|/)(ios|android|macos|windows|linux)/'
    r'|\.(gradle|kts|plist|pbxproj|podspec)$'
    r'|(^|/)Podfile',
  );

  /// Lo que un hot reload **no** aplica, con su motivo.
  static final cambiosQuePidenReiniciar = <(RegExp, String)>[
    (RegExp(r'^\s*(?:void\s+)?main\s*\('), 'cambió main()'),
    (RegExp(r'^\s*enum\s+\w'), 'cambió un enum'),
    (
      RegExp(
        r'^\s*(?:abstract\s+|sealed\s+|mixin\s+)?class\s+\w+[^{]*'
        r'\b(?:extends|implements|with)\b',
      ),
      'cambió la jerarquía de una clase',
    ),
    (RegExp(r'^\s*typedef\s+\w'), 'cambió un typedef'),
    (RegExp(r'^\s*static\s+\w'), 'cambió un valor static'),
    // Declaración **a nivel de archivo**, sin indentar: su inicializador no se
    // vuelve a ejecutar en un reload, y el caso típico es un provider de
    // Riverpod. Tiene que ser declaración y no expresión: un `const SizedBox(…)`
    // indentado dentro del árbol de widgets se recarga sin problema, y por eso el
    // patrón exige columna cero.
    (
      RegExp(r'^(?:const|final|var|late\s+final)\s+\w+'),
      'cambió una variable global',
    ),
    (RegExp(r'\binitState\s*\('), 'cambió initState'),
  ];

  /// Las rutas que nombra un `git diff` unificado.
  static List<String> rutasDelDiff(String diff) => [
    for (final linea in diff.split('\n'))
      if (linea.startsWith('+++ b/')) linea.substring(6).trim(),
  ];

  /// Las líneas añadidas o quitadas, sin las cabeceras del diff.
  ///
  /// Las cabeceras empiezan por `+++`/`---` y hay que descartarlas, o el nombre
  /// del archivo se leería como una línea de código.
  static List<String> lineasCambiadas(String diff) => [
    for (final linea in diff.split('\n'))
      if ((linea.startsWith('+') || linea.startsWith('-')) &&
          !linea.startsWith('+++') &&
          !linea.startsWith('---'))
        linea.substring(1),
  ];

  /// Qué hacer, dadas las rutas tocadas y el diff.
  static DecisionDeRecarga decide({
    required List<String> rutas,
    required String diff,
  }) {
    for (final ruta in rutas) {
      if (rutasQuePidenCompilar.hasMatch(ruta)) {
        return DecisionDeRecarga(
          QueHacer.recompilar,
          'tocó ${ruta.split('/').last}',
        );
      }
    }

    for (final linea in lineasCambiadas(diff)) {
      for (final (patron, motivo) in cambiosQuePidenReiniciar) {
        if (patron.hasMatch(linea)) {
          return DecisionDeRecarga(QueHacer.reiniciar, motivo);
        }
      }
    }

    // Sin nada que mirar no se adivina: el reload es lo barato y lo reversible.
    return const DecisionDeRecarga(QueHacer.recargar);
  }
}

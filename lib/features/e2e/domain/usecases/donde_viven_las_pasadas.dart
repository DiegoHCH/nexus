/// Dónde se guardan las pasadas de pruebas, y cómo se nombran.
///
/// **En la carpeta de documentos del usuario y no en Application Support**, que
/// es donde estaban: enterradas donde nadie las ve. Van al lado de lo que escribe
/// Claude, en `test/`, con una subcarpeta por app — así se pueden abrir, mirar y
/// borrar sin la app, que es lo que se pidió.
///
/// El árbol sigue siendo el índice, con un cambio: **la carpeta lleva el nombre
/// legible del proyecto y no su ruta entera**. Se prefiere que se pueda leer. Dos
/// proyectos que se llamen `app` comparten carpeta, y por eso la ruta completa va
/// **dentro** de cada registro: la atribución sale del dato y no del nombre de la
/// carpeta.
abstract final class DondeVivenLasPasadas {
  /// La carpeta, dentro de la de documentos.
  static const carpeta = 'test';

  /// Lo que Maestro **añade** por su cuenta a la ruta que se le da.
  ///
  /// Comprobado y no supuesto: con `--debug-output /tmp/x` no escribe en
  /// `/tmp/x`, escribe en `/tmp/x/.maestro/tests/<fecha>/<flow>/`. Se trata la
  /// ruta como una casa suya, no como un destino. Empieza por punto, así que su
  /// ruido queda oculto en una carpeta que sí se mira.
  static const loQueAnadeMaestro = '.maestro/tests';

  /// El nombre de carpeta de un proyecto: el último tramo de su ruta.
  static String carpetaDe(String proyecto) {
    final limpio = proyecto.endsWith('/')
        ? proyecto.substring(0, proyecto.length - 1)
        : proyecto;
    final nombre = limpio.split('/').last;
    // Un nombre vacío dejaría archivos en la raíz de `test/`, mezclados con las
    // carpetas. Es un caso de borde de una ruta rara, no una posibilidad real.
    return nombre.isEmpty ? 'proyecto' : nombre;
  }

  /// Dónde van las pasadas de un proyecto.
  static String de({required String raiz, required String proyecto}) =>
      '$raiz/${carpetaDe(proyecto)}';

  /// Cómo se llama el registro de una pasada.
  ///
  /// **Con el flow y la hora, legible**, porque este archivo lo va a ver alguien
  /// en el Finder. Y con `h` en vez de dos puntos: macOS enseña un `:` en un
  /// nombre de archivo como `/`, así que «09:35» aparecería como «09/35» y se
  /// leería como otra carpeta.
  static String nombreDelRegistro({
    required String flow,
    required DateTime cuando,
  }) {
    final f = '${cuando.year}-${_dos(cuando.month)}-${_dos(cuando.day)}';
    final h =
        '${_dos(cuando.hour)}h${_dos(cuando.minute)}${_dos(cuando.second)}';
    return '$flow $f $h';
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}

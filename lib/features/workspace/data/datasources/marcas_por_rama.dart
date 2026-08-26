import 'dart:convert';
import 'dart:io';

/// Lo que comparten las tres marcas que Nexus guarda por carpeta y rama: el plan firmado,
/// la corrida del gate y el cierre.
///
/// **Existe porque la regla del nombre estaba escrita tres veces.** Las tres derivan el
/// archivo de la ruta resuelta —`/var` y `/private/var` son la misma carpeta y eso ya
/// costó un gate que dejó pasar en silencio— y tres copias de esa derivación son tres
/// sitios donde puede dejar de coincidir. Cuando dejen de coincidir, la pantalla leerá un
/// archivo y el gancho otro, y nada fallará.
///
/// Aquí no se decide **qué** hay dentro de cada marca: eso es de cada origen de datos.
/// Solo el nombre, la clave de la rama, y las dos operaciones que valen para las tres —
/// enumerarlas y borrar una rama entera.
abstract final class MarcasPorRama {
  /// Dónde va la firma de una carpeta que no está en un repositorio.
  ///
  /// Con dos puntos porque git los prohíbe en un nombre de rama: así no puede chocar con
  /// una de verdad. Los ganchos en Python usan esta misma cadena.
  static const sinRama = ':sin-rama';

  static String clave(String? rama) =>
      rama == null || rama.isEmpty ? sinRama : rama;

  /// La rama que representa una clave, o `null` si es la reservada.
  static String? rama(String clave) => clave == sinRama ? null : clave;

  /// El archivo de una carpeta, con un nombre legible derivado de su ruta resuelta.
  ///
  /// Legible y no un hash: mirar la carpeta de la cuenta y entender qué hay es la mitad de
  /// poder diagnosticar esto cuando algo va raro.
  static String nombre(String carpeta) {
    var ruta = carpeta;
    try {
      ruta = Directory(carpeta).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Puede no existir todavía —o ser de otra máquina— y entonces lo mejor que se puede
      // hacer es usar la ruta tal cual.
    }
    return ruta
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Todas las carpetas y ramas que hay anotadas en ese directorio de marcas.
  ///
  /// Se lee la carpeta de dentro del archivo y no se deduce del nombre, por lo mismo de
  /// siempre: el nombre es para las personas, el contrato es lo de dentro.
  static Future<Set<({String carpeta, String? rama})>> claves(
    Directory dir,
  ) async {
    if (!dir.existsSync()) return const {};

    final encontradas = <({String carpeta, String? rama})>{};
    for (final entrada in dir.listSync()) {
      if (entrada is! File || !entrada.path.endsWith('.json')) continue;
      final leido = await _leer(entrada);
      final carpeta = leido?['carpeta'];
      if (carpeta is! String || carpeta.isEmpty) continue;
      final ramas = leido!['ramas'];
      if (ramas is! Map) continue;
      for (final clave in ramas.keys) {
        if (clave is String) {
          encontradas.add((carpeta: carpeta, rama: rama(clave)));
        }
      }
    }
    return encontradas;
  }

  /// Quita una rama entera de la marca de esa carpeta.
  ///
  /// El archivo se queda aunque no le quede ninguna rama: puede llevar cosas de la carpeta
  /// —si exige plan, cada cuánto caduca— que no son de ninguna rama y borrarlas sería
  /// apagar un interruptor que nadie tocó.
  static Future<void> borrar(
    Directory dir,
    String carpeta,
    String? rama,
  ) async {
    final archivo = File('${dir.path}/${nombre(carpeta)}.json');
    final leido = await _leer(archivo);
    if (leido == null) return;
    final ramas = leido['ramas'];
    if (ramas is! Map) return;
    if (ramas.remove(clave(rama)) == null) return;
    await archivo.writeAsString('${jsonEncode(leido)}\n');
  }

  static Future<Map<String, Object?>?> _leer(File archivo) async {
    if (!archivo.existsSync()) return null;
    try {
      final leido = jsonDecode(await archivo.readAsString());
      return leido is Map ? leido.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }
}

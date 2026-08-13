/// Qué repo de dentro nombra un encargo.
///
/// Con una carpeta raíz que tiene varios repos, «arregla el login de
/// front-mobile-b2c» dice perfectamente dónde hay que trabajar, y obligar a
/// elegirlo antes en un desplegable es hacerle repetir lo que ya dijo.
///
/// **Con dos candidatos no se elige ninguno**, igual que al cargar el contexto
/// compartido: colocarse en el repo equivocado es peor que quedarse en la raíz,
/// porque desde la raíz se ve todo y desde el repo que no era, nada de lo que
/// importa.
abstract final class RepoFromInstruction {
  /// Nombres demasiado cortos no se buscan: un repo llamado `ui` aparecería
  /// dentro de cualquier palabra que lo contenga.
  static const _minLength = 4;

  /// [repos] son rutas absolutas; devuelve la que nombra el encargo, o `null`.
  static String? resolve(String instruction, List<String> repos) {
    final text = _normalize(instruction);
    final matches = <String>[];

    for (final repo in repos) {
      final name = _normalize(repo.split('/').last);
      if (name.length < _minLength) continue;
      if (text.contains(name)) matches.add(repo);
    }

    if (matches.length != 1) return null;
    return matches.single;
  }

  /// Sin acentos y con los separadores unificados: se dice «front mobile b2c»
  /// hablando y `front-mobile-b2c` escribiendo, y las dos formas tienen que
  /// encontrar el mismo repo — por voz es que la transcripción **nunca** trae
  /// los guiones.
  static String _normalize(String value) {
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ñ': 'n',
    };
    var text = value.toLowerCase();
    acentos.forEach((from, to) => text = text.replaceAll(from, to));
    return text.replaceAll(RegExp(r'[\s_\-.]+'), '');
  }
}

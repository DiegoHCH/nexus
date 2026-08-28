/// Dónde guarda Nexus el clon del repo de pruebas, y por qué ahí.
///
/// **El pedido era «sin descargar al local», y no se puede tal cual.** Tres razones
/// independientes, todas comprobadas contra `global66/automated-test`:
///
/// 1. Los flows **no son autónomos**: `flows/15-login-to-home-flow.yaml` hace
///    `runFlow: commons/setup-authed.yaml`, una ruta relativa a un archivo hermano.
///    El modo `yaml` inline de Maestro —la única vía de correr sin archivos— no
///    resuelve esos `runFlow`.
/// 2. Maestro ejecuta un binario local contra un dispositivo local. Los archivos
///    tienen que estar en un sistema de archivos que ese proceso pueda leer.
/// 3. `run.sh` hace `cd "$(dirname "$0")"` y resuelve todo relativo a ahí.
///
/// **Lo que sí se cumple es el motivo del pedido**, que no era el disco: era no
/// tener que clonar, ni acordarse de hacer pull, ni que un repo del trabajo aparezca
/// en tu workspace. El clon lo gestiona Nexus, vive fuera de tu vista y tú no lo
/// tocas nunca.
///
/// 🔴 **En la carpeta de soporte y NO bajo la raíz de los flows.** La raíz de los
/// flows es tuya: la eliges tú, la abres en el Finder y editas ahí. Un clon de git
/// dentro de una carpeta que alguien edita a mano es cómo se pierde trabajo — un
/// `pull` con cambios locales, un archivo suelto que se borra. Este clon es un
/// detalle de implementación y se guarda como tal.
///
/// Y por el mismo motivo que ya estaba escrito en `RaizDeLosFlows` —«una prueba en
/// un repo del trabajo es un archivo que alguien acaba commiteando sin querer»—:
/// esta carpeta no está dentro de ningún repo tuyo, así que nada de aquí puede
/// colarse en un commit de otro sitio.
abstract final class DondeViveElRepoDePruebas {
  /// La subcarpeta, dentro de la de soporte de la app.
  static const carpeta = 'repos';

  /// El repo por defecto: el de las pruebas de `front-mobile-b2c`.
  static const slugPorDefecto = 'global66/automated-test';

  /// La rama sobre la que se trabaja y contra la que salen los PR.
  static const ramaPorDefecto = 'main';

  /// Dónde vive el clon de un repo. `<soporte>/repos/<owner>--<nombre>`.
  ///
  /// Con `--` y no con `/`: dos niveles de carpeta por cada repo dejarían
  /// `repos/global66/` con un solo hijo casi siempre, y el listado deja de leerse
  /// de un vistazo. El nombre plano es único igual, porque un slug lo es.
  static String de({required String soporte, required String slug}) =>
      '$soporte/$carpeta/${nombreDeCarpeta(slug)}';

  static String nombreDeCarpeta(String slug) =>
      slug.trim().replaceAll('/', '--');

  /// Qué forma tiene un slug de GitHub: `owner/nombre`.
  ///
  /// Vive aquí y no en quien lo elige porque **la ruta se construye aquí**, y una
  /// validación que solo corre al elegir deja fuera el otro camino: lo guardado
  /// en las preferencias, que es un plist en el disco y no un almacén de
  /// confianza. A tres líneas de donde se usa el slug hay un
  /// `delete(recursive: true)`, y esa vecindad merece que comprobar no dependa
  /// de por dónde entró el valor.
  static final _forma = RegExp(r'^[\w.-]+/[\w.-]+$');

  /// El slug si tiene forma de slug; si no, `null`.
  ///
  /// Quien elige puede decir por qué no vale; quien carga se cae al de por
  /// defecto en silencio, porque nadie está mirando.
  static String? valido(String slug) {
    final limpio = slug.trim();
    return _forma.hasMatch(limpio) ? limpio : null;
  }

  /// La URL de clonado. **Por HTTPS y no por SSH**: el `gh` de la máquina ya está
  /// autenticado —se comprobó, con permiso ADMIN sobre el repo— y su credential
  /// helper resuelve el push sin pedir una clave que quizá no exista.
  static String urlDe(String slug) => 'https://github.com/${slug.trim()}.git';

  /// La carpeta de flows dentro del clon. Es lo que se lista y lo que se le pasa a
  /// Maestro.
  static String flowsEn(String clon) => '$clon/flows';

  /// Cómo se llama la rama de un cambio hecho desde Nexus.
  ///
  /// Con fecha y hora porque dos cambios el mismo día son lo normal, y una rama que
  /// ya existe hace fallar el `checkout -b` justo cuando ya escribiste el archivo.
  static String ramaPara({required String flow, required DateTime cuando}) {
    final limpio = flow
        .split('/')
        .last
        .replaceAll(RegExp(r'\.ya?ml$'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final f = '${cuando.year}${_dos(cuando.month)}${_dos(cuando.day)}';
    final h = '${_dos(cuando.hour)}${_dos(cuando.minute)}';
    final nombre = limpio.isEmpty ? 'prueba' : limpio;
    return 'test/$nombre-$f$h';
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}

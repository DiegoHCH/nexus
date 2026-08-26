/// Dónde se guardan las corridas que lanza Nexus, y cómo se vuelve de ahí.
///
/// **El árbol es el índice**, que es la misma técnica de `ArtifactsDataSource`:
/// no se interpreta nada, se entra solo donde se sabe qué hay. Y se puede porque
/// `maestro test` acepta `--debug-output`, así que el sitio lo dictamos nosotros
/// en vez de adivinarlo después.
abstract final class DondeVivenLasCorridas {
  /// Lo que Maestro **añade** por su cuenta a la ruta que se le da.
  ///
  /// Comprobado y no supuesto: con `--debug-output /tmp/x` no escribe en
  /// `/tmp/x`, escribe en `/tmp/x/.maestro/tests/<fecha>/<flow>/`. Se trata la
  /// ruta como una casa suya, no como un destino. Suponer lo contrario dejaría el
  /// índice mirando una carpeta vacía.
  static const loQueAnadeMaestro = '.maestro/tests';

  /// El nombre de carpeta de un proyecto.
  ///
  /// La ruta entera con las barras cambiadas, y no el nombre final: dos
  /// proyectos pueden llamarse `app` y quedarían mezclados en la misma carpeta.
  /// Con esto la carpeta identifica al proyecto y **se puede volver** —el
  /// carácter elegido no aparece en rutas de verdad, así que la vuelta es exacta.
  static String carpetaDe(String proyecto) =>
      proyecto.replaceAll(RegExp(r'^/'), '').replaceAll('/', '·');

  /// Y de vuelta.
  static String proyectoDe(String carpeta) => '/${carpeta.replaceAll('·', '/')}';

  /// A dónde se le dice a Maestro que escriba.
  static String paraLanzar({
    required String raiz,
    required String perfil,
    required String proyecto,
  }) => '$raiz/$perfil/${carpetaDe(proyecto)}';

  /// Y dónde acaban de verdad las corridas de ese proyecto.
  static String dondeAterrizan({
    required String raiz,
    required String perfil,
    required String proyecto,
  }) =>
      '${paraLanzar(raiz: raiz, perfil: perfil, proyecto: proyecto)}'
      '/$loQueAnadeMaestro';
}

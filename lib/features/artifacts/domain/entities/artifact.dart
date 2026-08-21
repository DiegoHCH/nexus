/// Un documento que ha salido de una conversación: un mockup, un informe, una
/// hoja de cálculo.
class Artifact {
  const Artifact({
    required this.path,
    required this.name,
    required this.at,
    this.account,
  });

  final String path;
  final String name;

  /// De qué cuenta salió —`work`, `private`— cuando la carpeta está dividida por
  /// perfil, que es como acaba estando en cuanto se trabaja con dos.
  ///
  /// El comentario de la carpeta decía que un documento «no es de `work` ni de
  /// `private`, es tuyo». Sigue siendo verdad de lo que **es**, y resultó falso de
  /// dónde **vive**: quien trabaja con dos cuentas separa también los documentos, y
  /// una lista que solo mira la raíz enseña cero habiendo treinta y seis.
  final String? account;

  /// Cuándo se escribió por última vez. Ordena la lista, porque lo último que
  /// pediste es lo que vas a querer abrir.
  final DateTime at;

  /// Lo que **el visor de macOS** sabe pintar sin ayuda de nadie: `WKWebView` los
  /// abre todos. Un `.md` no está porque habría que interpretarlo, y un `.zip`
  /// tampoco porque no hay nada que enseñar.
  ///
  /// Esto es una capacidad del visor, **no la definición de un documento**. Eran el
  /// mismo conjunto y por eso un `.md` —lo que más escribe Claude— no existía para
  /// esta parte de la app: ni en la lista del Mac ni en la del teléfono, que sí
  /// sabe enseñar texto.
  static const viewable = {
    '.html',
    '.htm',
    '.pdf',
    '.png',
    '.jpg',
    '.jpeg',
    '.svg',
    '.gif',
  };

  /// Lo que se lee como texto tal cual. Se manda por el canal como una cadena, así
  /// que el teléfono puede enseñarlo aunque el visor del Mac no lo pinte.
  static const textual = {'.md', '.txt', '.csv'};

  /// Qué cuenta como documento producido: lo que alguien puede abrir en algún sitio.
  static const listable = {...viewable, ...textual};

  static bool isViewable(String path) => _extensionEn(path, viewable);

  /// Si es de los que se pueden mandar como texto por el canal. Importa porque
  /// leer un `.png` como cadena no da una imagen: da un error de codificación, y
  /// el teléfono se quedaba con un fallo en vez de con un «esto ábrelo en el Mac».
  static bool isTextual(String path) => _extensionEn(path, textual);

  static bool isListable(String path) => _extensionEn(path, listable);

  static bool _extensionEn(String path, Set<String> extensiones) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return extensiones.contains(path.substring(dot).toLowerCase());
  }
}

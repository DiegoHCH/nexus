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
    // **`.webp` porque es lo que devuelven los modelos.** El Space de FLUX
    // entrega webp, así que sin esto una imagen recién generada no contaba como
    // documento: no salía en la lista, no se podía abrir y no dejaba botón.
    '.webp',
  };

  /// Las que son una imagen y se pueden enseñar como miniatura en el chat.
  ///
  /// Aparte de [viewable] porque no todo lo que el visor abre es una imagen: un
  /// HTML y un PDF también se abren, y meterlos aquí llenaría la conversación de
  /// miniaturas de documentos que se leen, no se miran.
  static const imagenes = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'};

  static bool isImage(String path) => _extensionEn(path, imagenes);

  /// Lo que se lee como texto tal cual. Se manda por el canal como una cadena, así
  /// que el teléfono puede enseñarlo **y pintarlo**.
  ///
  /// El `.html` está aquí porque un HTML es texto: no hacía falta inventar transporte
  /// binario para poder abrirlo en el teléfono, solo mandarlo. De los ciento
  /// dieciocho documentos que había cuando esto se escribió, noventa eran `.md` y
  /// veintiocho `.html` — ni una imagen, ni un PDF—, así que esto cubre todo lo que
  /// existe de verdad y el aviso de «solo en la Mac» queda para lo que aún no hay.
  static const textual = {'.md', '.txt', '.csv', '.html', '.htm'};

  /// Qué cuenta como documento producido: lo que alguien puede abrir en algún sitio.
  ///
  /// `final` y no `const`: los dos conjuntos se solapan —un `.html` lo pinta el visor
  /// del Mac **y** viaja como texto— y un `const` con elementos repetidos no compila.
  /// Que se solapen no es un defecto: son dos preguntas distintas sobre el mismo
  /// archivo.
  static final Set<String> listable = {...viewable, ...textual};

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

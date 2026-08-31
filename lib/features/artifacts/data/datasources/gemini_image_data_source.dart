import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lo que devolvió pedir una imagen: los bytes, o el motivo por el que no.
class ImagenGenerada {
  const ImagenGenerada.ok(this.bytes, this.mime, {this.id}) : problema = null;
  const ImagenGenerada.fallo(this.problema)
    : bytes = null,
      mime = null,
      id = null;

  final Uint8List? bytes;
  final String? mime;
  final String? problema;

  /// El identificador de esta interacción, con el que se le puede pedir un
  /// cambio después. Es lo que evita reenviar el PNG entero en cada vuelta.
  final String? id;

  bool get salio => bytes != null;
}

/// Una imagen que se manda como referencia: «hazlo con este estilo», «cambia
/// esto de aquí».
class ImagenDeReferencia {
  const ImagenDeReferencia(this.bytes, this.mime);

  final Uint8List bytes;
  final String mime;
}

/// Pide una imagen a Gemini.
///
/// **Va contra la Interactions API y no contra `generateContent`**, que la
/// propia documentación marca ya como *legacy*. Son dos formas distintas —otra
/// ruta, otro cuerpo, otra respuesta— así que esto no es un detalle de estilo:
/// escribirlo contra la vieja habría costado descubrirlo en tiempo de ejecución
/// y con dinero de por medio.
class GeminiImageDataSource {
  const GeminiImageDataSource();

  static const _host = 'generativelanguage.googleapis.com';
  static const _ruta = '/v1beta/interactions';

  /// La versión del contrato que se pide. **Va explícita a propósito**: sin
  /// ella la API sirve la que tenga por defecto, y el día que cambie la
  /// respuesta dejaría de parsearse sin que nadie hubiera tocado nada.
  static const revision = '2026-05-20';

  Future<ImagenGenerada> generar({
    required String llave,
    required String descripcion,

    /// Cuál dibuja. Entra por parámetro y no se fija aquí: se elige en Ajustes
    /// porque el precio sale del saldo de quien lo pide, y porque el bueno se
    /// satura y hay que poder bajar a otro sin tocar código.
    required String modelo,

    /// La interacción anterior, para seguir con aquella imagen en vez de
    /// empezar de cero. Se manda el identificador y no el PNG: la API ya tiene
    /// la imagen, y resubirla en cada vuelta sería pagar el viaje dos veces.
    String? seguirDe,
    List<ImagenDeReferencia> referencias = const [],

    /// Tres minutos, y no los noventa segundos de antes: **generar una imagen
    /// tarda de verdad**, y con una edición encadenada o referencias de por
    /// medio, más. Un tope corto no protege de nada aquí — solo convierte un
    /// trabajo que iba bien en un fallo.
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (llave.isEmpty) return const ImagenGenerada.fallo('falta la llave');

    // 🔴 **El tope envuelve la operación entera, y todo lo que salga se
    // atrapa.** Antes el `timeout` colgaba solo de esperar las cabeceras y su
    // `TimeoutException` no la cogía ningún `catch`: se escapaba del data
    // source, del proveedor y del controlador, y como nadie la esperaba, la
    // pantalla se quedaba girando **para siempre** sin decir nada. Reportado
    // esperando delante de ella.
    //
    // Leer el cuerpo tampoco tenía tope, que era la otra mitad del mismo
    // agujero: unas cabeceras rápidas y un cuerpo que no llega cuelgan igual.
    try {
      return await _pedir(
        llave: llave,
        modelo: modelo,
        descripcion: descripcion,
        seguirDe: seguirDe,
        referencias: referencias,
        timeout: timeout,
      ).timeout(timeout);
    } on TimeoutException {
      return ImagenGenerada.fallo(
        'Gemini no contestó en ${timeout.inSeconds}s',
      );
    } on SocketException {
      return const ImagenGenerada.fallo('sin conexión');
    } on HttpException catch (e) {
      return ImagenGenerada.fallo(e.message);
    } on Object catch (e) {
      // Lo que no se reconoce **se cuenta igual**: quien está mirando la
      // pantalla prefiere un nombre raro a un giro eterno.
      return ImagenGenerada.fallo('fallo inesperado: ${e.runtimeType}');
    }
  }

  Future<ImagenGenerada> _pedir({
    required String llave,
    required String modelo,
    required String descripcion,
    required String? seguirDe,
    required List<ImagenDeReferencia> referencias,
    required Duration timeout,
  }) async {
    final cliente = HttpClient()..connectionTimeout = timeout;
    try {
      final peticion = await cliente.postUrl(Uri.https(_host, _ruta));
      peticion.headers
        ..set('x-goog-api-key', llave)
        ..set('Api-Revision', revision)
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      peticion.write(
        jsonEncode({
          'model': modelo,
          'input': [
            {'type': 'text', 'text': descripcion},
            // Las referencias van **detrás del texto**: la instrucción es lo
            // que manda y las imágenes son el material.
            for (final referencia in referencias)
              {
                'type': 'image',
                'mime_type': referencia.mime,
                'data': base64Encode(referencia.bytes),
              },
          ],
          'previous_interaction_id': ?seguirDe,
        }),
      );
      final respuesta = await peticion.close();
      final cuerpo = await respuesta.transform(utf8.decoder).join();
      if (respuesta.statusCode != 200) {
        return ImagenGenerada.fallo(
          loQueSalioMal(cuerpo) ?? 'Gemini respondió ${respuesta.statusCode}',
        );
      }
      return leerLaImagen(cuerpo);
    } finally {
      cliente.close(force: true);
    }
  }

  /// El motivo que da la API, si lo da. Se prefiere al código de estado: «403»
  /// no dice si falta facturación, si la llave es de otro proyecto o si el
  /// modelo no está disponible — y las tres se arreglan distinto.
  static String? loQueSalioMal(String cuerpo) {
    try {
      final leido = jsonDecode(cuerpo);
      if (leido is Map<String, dynamic>) {
        final error = leido['error'];
        if (error is Map<String, dynamic>) return error['message'] as String?;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Saca los bytes de la respuesta.
  ///
  /// Se mira primero `output_image`, que es el atajo que documenta la API, y si
  /// no está se recorren los `steps`. Los dos caminos están escritos porque el
  /// atajo es una comodidad y lo que manda es la lista: si un día no viene, la
  /// imagen sigue estando y sería absurdo dar el turno por fallido.
  static ImagenGenerada leerLaImagen(String cuerpo) {
    final Object? leido;
    try {
      leido = jsonDecode(cuerpo);
    } on FormatException {
      return const ImagenGenerada.fallo('respuesta ilegible de Gemini');
    }
    if (leido is! Map<String, dynamic>) {
      return const ImagenGenerada.fallo('respuesta ilegible de Gemini');
    }

    // El identificador de la interacción, para poder pedirle un cambio luego.
    final id = leido['id'] is String ? leido['id'] as String : null;

    final atajo = leido['output_image'];
    if (atajo is Map<String, dynamic>) {
      final hecha = _desde(atajo['data'], atajo['mime_type'], id);
      if (hecha != null) return hecha;
    }

    final pasos = leido['steps'];
    if (pasos is List) {
      for (final paso in pasos) {
        if (paso is! Map<String, dynamic>) continue;
        final contenido = paso['content'];
        if (contenido is! List) continue;
        for (final trozo in contenido) {
          if (trozo is! Map<String, dynamic>) continue;
          final hecha = _desde(trozo['data'], trozo['type'], id);
          if (hecha != null) return hecha;
        }
      }
    }

    // Sin imagen y sin error: el modelo puede negarse a dibujar algo y
    // contestar con texto. Decirlo es mejor que un «no se pudo» a secas.
    return ImagenGenerada.fallo(_elTextoQueDijo(leido) ?? 'no devolvió imagen');
  }

  static ImagenGenerada? _desde(Object? datos, Object? tipo, String? id) {
    if (datos is! String || datos.isEmpty) return null;
    final mime = tipo is String && tipo.contains('/') ? tipo : 'image/png';
    if (!mime.startsWith('image/')) return null;
    try {
      return ImagenGenerada.ok(base64Decode(datos), mime, id: id);
    } on FormatException {
      return null;
    }
  }

  static String? _elTextoQueDijo(Map<String, dynamic> leido) {
    final pasos = leido['steps'];
    if (pasos is! List) return null;
    for (final paso in pasos) {
      if (paso is! Map<String, dynamic>) continue;
      final contenido = paso['content'];
      if (contenido is! List) continue;
      for (final trozo in contenido) {
        if (trozo is Map<String, dynamic> && trozo['text'] is String) {
          final texto = (trozo['text'] as String).trim();
          if (texto.isNotEmpty) return texto;
        }
      }
    }
    return null;
  }
}

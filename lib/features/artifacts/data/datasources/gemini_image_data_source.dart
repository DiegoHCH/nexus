import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lo que devolvió pedir una imagen: los bytes, o el motivo por el que no.
class ImagenGenerada {
  const ImagenGenerada.ok(this.bytes, this.mime) : problema = null;
  const ImagenGenerada.fallo(this.problema) : bytes = null, mime = null;

  final Uint8List? bytes;
  final String? mime;
  final String? problema;

  bool get salio => bytes != null;
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

  static const modelo = 'gemini-2.5-flash-image';
  static const _host = 'generativelanguage.googleapis.com';
  static const _ruta = '/v1beta/interactions';

  /// La versión del contrato que se pide. **Va explícita a propósito**: sin
  /// ella la API sirve la que tenga por defecto, y el día que cambie la
  /// respuesta dejaría de parsearse sin que nadie hubiera tocado nada.
  static const revision = '2026-05-20';

  Future<ImagenGenerada> generar({
    required String llave,
    required String descripcion,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (llave.isEmpty) return const ImagenGenerada.fallo('falta la llave');

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
          ],
        }),
      );
      final respuesta = await peticion.close().timeout(timeout);
      final cuerpo = await respuesta.transform(utf8.decoder).join();
      if (respuesta.statusCode != 200) {
        return ImagenGenerada.fallo(
          loQueSalioMal(cuerpo) ?? 'Gemini respondió ${respuesta.statusCode}',
        );
      }
      return leerLaImagen(cuerpo);
    } on SocketException {
      return const ImagenGenerada.fallo('sin conexión');
    } on HttpException catch (e) {
      return ImagenGenerada.fallo(e.message);
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

    final atajo = leido['output_image'];
    if (atajo is Map<String, dynamic>) {
      final hecha = _desde(atajo['data'], atajo['mime_type']);
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
          final hecha = _desde(trozo['data'], trozo['type']);
          if (hecha != null) return hecha;
        }
      }
    }

    // Sin imagen y sin error: el modelo puede negarse a dibujar algo y
    // contestar con texto. Decirlo es mejor que un «no se pudo» a secas.
    return ImagenGenerada.fallo(_elTextoQueDijo(leido) ?? 'no devolvió imagen');
  }

  static ImagenGenerada? _desde(Object? datos, Object? tipo) {
    if (datos is! String || datos.isEmpty) return null;
    final mime = tipo is String && tipo.contains('/') ? tipo : 'image/png';
    if (!mime.startsWith('image/')) return null;
    try {
      return ImagenGenerada.ok(base64Decode(datos), mime);
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

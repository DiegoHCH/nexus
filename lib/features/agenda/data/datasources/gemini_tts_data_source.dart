import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lo que devolvió pedir que digan una frase: el audio, o el motivo.
class LoDicho {
  const LoDicho.ok(this.pcm) : problema = null;
  const LoDicho.fallo(this.problema) : pcm = null;

  /// PCM de 16 bits, mono, 24 kHz — **exactamente lo que come el motor de
  /// audio**, que documenta esa frecuencia como no negociable. No hay
  /// conversión de por medio y por eso esto suena sin tocar nada nativo.
  final Uint8List? pcm;
  final String? problema;

  bool get salio => pcm != null;
}

/// Convierte una frase en la voz de Nexus.
///
/// 🔴 **Es una llamada suelta, no una sesión Live.** Y esa es la decisión que
/// hace posible todo esto: la sesión de voz va con la conversación que tiene el
/// foco —hay un solo motor duplex, que es lo que cancela el eco— así que un
/// aviso que necesitara sesión solo podría sonar en la carpeta que tuvieras
/// delante, que es justo cuando menos falta hace.
///
/// Un aviso **no escucha**. Es audio de salida y nada más, así que no necesita
/// foco, ni micrófono, ni el duplex.
///
/// Las voces son las mismas 30 que ya lista `NexusVoice`: el aviso suena con la
/// que elegiste en Ajustes, no con otra.
class GeminiTtsDataSource {
  const GeminiTtsDataSource();

  /// El gratuito del nivel gratuito. Se elige éste y no el Pro porque decir una
  /// frase de dos segundos no necesita el modelo caro, y porque la llave de voz
  /// vive en ese nivel.
  static const modelo = 'gemini-2.5-flash-preview-tts';

  static const _host = 'generativelanguage.googleapis.com';
  static const _ruta = '/v1beta/interactions';
  static const revision = '2026-05-20';

  Future<LoDicho> decir({
    required String llave,
    required String frase,
    required String voz,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (llave.isEmpty) return const LoDicho.fallo('falta la llave');
    if (frase.trim().isEmpty) {
      return const LoDicho.fallo('no hay nada que decir');
    }

    // Todo lo que salga se atrapa, y el tope envuelve la operación entera.
    // Es la lección que dejó la generación de imágenes: un `TimeoutException`
    // que no coge nadie deja la app esperando algo que no va a llegar, y aquí
    // nadie está mirando la pantalla — el fallo sería silencio, sin más.
    try {
      return await _pedir(
        llave: llave,
        frase: frase.trim(),
        voz: voz,
      ).timeout(timeout);
    } on TimeoutException {
      return LoDicho.fallo('no contestó en ${timeout.inSeconds}s');
    } on SocketException {
      return const LoDicho.fallo('sin conexión');
    } on HttpException catch (e) {
      return LoDicho.fallo(e.message);
    } on Object catch (e) {
      return LoDicho.fallo('fallo inesperado: ${e.runtimeType}');
    }
  }

  Future<LoDicho> _pedir({
    required String llave,
    required String frase,
    required String voz,
  }) async {
    final cliente = HttpClient();
    try {
      final peticion = await cliente.postUrl(Uri.https(_host, _ruta));
      peticion.headers
        ..set('x-goog-api-key', llave)
        ..set('Api-Revision', revision)
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      peticion.write(
        jsonEncode({
          'model': modelo,
          'input': frase,
          'response_format': {'type': 'audio'},
          'generation_config': {
            'speech_config': [
              {'voice': voz},
            ],
          },
        }),
      );
      final respuesta = await peticion.close();
      final cuerpo = await respuesta.transform(utf8.decoder).join();
      if (respuesta.statusCode != 200) {
        return LoDicho.fallo(
          loQueSalioMal(cuerpo) ?? 'respondió ${respuesta.statusCode}',
        );
      }
      return leerElAudio(cuerpo);
    } finally {
      cliente.close(force: true);
    }
  }

  /// El motivo que da la API, si lo da. Un código a secas no distingue una
  /// llave de otro proyecto de una voz que no existe.
  static String? loQueSalioMal(String cuerpo) {
    try {
      final leido = jsonDecode(cuerpo);
      if (leido is! Map<String, dynamic>) return null;
      if (leido['error'] case final Map<String, dynamic> error) {
        return error['message'] as String?;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static LoDicho leerElAudio(String cuerpo) {
    final Object? leido;
    try {
      leido = jsonDecode(cuerpo);
    } on FormatException {
      return const LoDicho.fallo('respuesta ilegible');
    }
    if (leido is! Map<String, dynamic>) {
      return const LoDicho.fallo('respuesta ilegible');
    }

    // El atajo que documenta la API, y si no está, los pasos. Los dos caminos
    // por lo mismo que en las imágenes: el atajo es una comodidad y lo que
    // manda es la lista.
    if (leido['output_audio'] case final Map<String, dynamic> atajo) {
      if (_desde(atajo['data']) case final hecho?) return hecho;
    }
    if (leido['steps'] case final List<dynamic> pasos) {
      for (final paso in pasos) {
        if (paso is! Map<String, dynamic>) continue;
        if (paso['content'] case final List<dynamic> contenido) {
          for (final trozo in contenido) {
            if (trozo is! Map<String, dynamic>) continue;
            if (_desde(trozo['data']) case final hecho?) return hecho;
          }
        }
      }
    }
    return const LoDicho.fallo('no devolvió audio');
  }

  static LoDicho? _desde(Object? datos) {
    if (datos is! String || datos.isEmpty) return null;
    try {
      return LoDicho.ok(base64Decode(datos));
    } on FormatException {
      return null;
    }
  }
}

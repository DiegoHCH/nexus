import 'dart:convert';
import 'dart:io';

/// Mandar un mensaje a Slack. Una sola llamada: `chat.postMessage`.
///
/// **Es una puerta de salida nueva**, la quinta, y por eso aparece en la
/// pantalla de «qué sale de la máquina» como las otras cuatro. Lo que cruza por
/// aquí es el parte que escribió Claude — o sea, texto sobre tu trabajo — así
/// que no basta con que funcione: tiene que **verse antes de salir**, y por eso
/// nada se manda solo.
class SlackApi {
  const SlackApi();

  static const _host = 'slack.com';
  static const _ruta = '/api/chat.postMessage';

  /// Qué contestó Slack: `null` si salió, o el motivo si no.
  ///
  /// **Aparte del socket a propósito**, porque aquí está el único fallo con
  /// consecuencias y el socket no tiene ninguno: Slack responde **200 con
  /// `ok: false`** cuando el token está mal o el destino no existe. Leer el
  /// código de estado dejaría a alguien creyendo que su parte se envió, y un
  /// parte que no llegó al daily es peor que no haberlo escrito.
  ///
  /// Y lo que no se entiende **no se da por bueno**: sin `ok` verdadero, es un
  /// fallo. Al revés sería tragarse un cambio de la API en silencio.
  static String? loQueDijo(String cuerpo) {
    final Object? leido;
    try {
      leido = jsonDecode(cuerpo);
    } on FormatException {
      return 'respuesta ilegible de Slack';
    }
    if (leido is! Map<String, dynamic>) return 'respuesta ilegible de Slack';
    if (leido['ok'] == true) return null;
    return (leido['error'] as String?) ?? 'Slack dijo que no';
  }

  /// Manda [texto] a [destino]. Devuelve `null` si salió, o el motivo si no.
  ///
  /// Slack contesta **200 con `ok: false`** cuando el token está mal o el canal
  /// no existe, así que mirar el código de estado no sirve de nada: hay que
  /// leer el cuerpo. Es el fallo clásico de esta API y el que dejaría a alguien
  /// creyendo que su parte se envió.
  Future<String?> mandar({
    required String token,
    required String destino,
    required String texto,
  }) async {
    if (token.isEmpty) return 'falta el token';
    if (destino.trim().isEmpty) return 'falta a quién mandarlo';
    if (texto.trim().isEmpty) return 'no hay nada que mandar';

    final cliente = HttpClient();
    try {
      final peticion = await cliente.postUrl(Uri.https(_host, _ruta));
      peticion.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      peticion.write(
        jsonEncode({
          'channel': destino.trim(),
          'text': texto,
          // Sin desplegar enlaces ni imágenes: un parte es texto, y una vista
          // previa de un repositorio privado en un canal es justo lo que nadie
          // pidió.
          'unfurl_links': false,
          'unfurl_media': false,
        }),
      );

      final respuesta = await peticion.close();
      return loQueDijo(await respuesta.transform(utf8.decoder).join());
    } on SocketException {
      return 'sin conexión';
    } on FormatException {
      return 'respuesta ilegible de Slack';
    } on HttpException catch (fallo) {
      return fallo.message;
    } finally {
      cliente.close(force: true);
    }
  }
}

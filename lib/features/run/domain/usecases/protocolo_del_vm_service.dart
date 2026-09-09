import 'dart:convert';

/// Cómo se le habla al VM service y cómo se lee lo que contesta.
///
/// El hermano de `ProtocoloDelDaemon` para el otro canal, y existe por lo mismo:
/// **hay tres cosas de este protocolo que no se adivinan** y que serían un fallo
/// silencioso cada una. Estaban escritas en [ElErrorQuePintaLaApp] y ahora las
/// necesita también el freno, así que viven una vez:
///
/// 1. Un evento llega como `streamNotify` y **no** como el `streamNotification`
///    que dice la documentación.
/// 2. Las respuestas a lo que pedimos llegan con `id` y **sin** `method`: no son
///    eventos, y leerlas como tal descarta lo que alguien está esperando.
/// 3. Sin un `streamListen` por canal, el VM service **no manda nada**.
abstract final class ProtocoloDelVmService {
  /// Una petición JSON-RPC, con su id.
  static String peticion(
    int id,
    String metodo, [
    Map<String, Object?> params = const {},
  ]) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'method': metodo,
    'params': params,
  });

  /// Apuntarse a un canal. Sin esto no llega nada de él: hay que pedirlo.
  static String escuchar(int id, String canal) =>
      peticion(id, 'streamListen', {'streamId': canal});

  /// El id de la petición que contesta esta línea, o `null` si no es una
  /// respuesta.
  ///
  /// 🔴 **Es lo único que empareja una respuesta con lo que se preguntó.** Se
  /// distingue de un evento por lo que **no** trae: un evento lleva `method`.
  static int? deQuienEs(String linea) {
    final leido = _leido(linea);
    if (leido is! Map) return null;
    if (leido.containsKey('method')) return null;
    final id = leido['id'];
    return id is int ? id : null;
  }

  /// El evento que trae esta línea, o `null` si la línea es otra cosa.
  ///
  /// 🔴 **`streamNotify`, y está medido.** El nombre que se lee en la
  /// documentación del protocolo es «streamNotification»; lo que manda el VM
  /// service de verdad es `streamNotify`. Se capturó el evento crudo de una app
  /// que revienta pintando para verlo: con el nombre de la documentación se
  /// descartaba **todo**, y el síntoma era que los errores del framework no
  /// llegaban — que no se parece a un problema de nombre.
  static Map<Object?, Object?>? elEvento(String linea) {
    final leido = _leido(linea);
    if (leido is! Map) return null;
    if (leido['method'] != 'streamNotify') return null;
    final params = leido['params'];
    if (params is! Map) return null;
    final evento = params['event'];
    return evento is Map ? evento : null;
  }

  /// El `result` de una respuesta, ya venga decodificada o como el texto que
  /// llegó por el socket.
  static Map<Object?, Object?>? elResultado(Object? respuesta) {
    final leido = respuesta is String ? _leido(respuesta) : respuesta;
    if (leido is! Map) return null;
    final resultado = leido['result'];
    return resultado is Map ? resultado : null;
  }

  static Object? _leido(String linea) {
    try {
      return jsonDecode(linea);
    } on FormatException {
      // Por este socket llegan cosas que no son JSON al conectar y al cerrarse.
      // No es un error del protocolo: es que esa línea no era para nosotros.
      return null;
    }
  }
}

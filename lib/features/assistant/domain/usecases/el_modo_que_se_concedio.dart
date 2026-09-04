import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// El modo de permisos que quedó concedido al pulsar «Permitir todo», si alguno.
///
/// **Sale de las sugerencias del propio CLI, no de una decisión nuestra.** Medido
/// contra el binario 2.1.258, un `Write` ofrece esto y nada más:
///
/// ```json
/// {"type": "setMode", "mode": "acceptEdits", "destination": "session"}
/// ```
///
/// O sea que «permitir todo» en una escritura **no** es una lista de permisos: es
/// pedirle al CLI que cambie el modo de la sesión. Y ese cambio vive en el proceso,
/// que muere al acabar el encargo — de ahí que haya que recordarlo por nuestra
/// cuenta para que el siguiente arranque donde quedó el anterior.
///
/// **Lista blanca, y no un filtro de lo peligroso.** Solo `acceptEdits`, y solo con
/// destino `session`. Filtrar por exclusión guardaría cualquier modo que el CLI
/// ofrezca mañana —`bypassPermissions`, por ejemplo—, y eso convertiría un
/// «permítele esto» en «no vuelvas a preguntar nada nunca», que no es lo que nadie
/// pulsó. Un modo que no conocemos vale menos que la pregunta que se ahorra.
///
/// El `addRules` que el CLI ofrece para los comandos se queda fuera a propósito:
/// no está medido cómo viajan sus reglas, y traducir a ciegas un protocolo sin
/// documentar es justo la clase de suposición que aquí acaba en un permiso más
/// ancho del que se concedió. Para eso están los comandos permitidos de la carpeta,
/// que se escriben a sabiendas.
abstract final class ElModoQueSeConcedio {
  static const _conocidos = {'acceptEdits'};

  /// `null` si no se concedió nada, si se concedió solo esta vez, o si lo que
  /// ofreció el CLI no es un modo que sepamos sostener.
  static String? en(RespuestaDePermiso respuesta) {
    if (respuesta is! PermisoConcedido) return null;
    for (final sugerencia in respuesta.permisosNuevos) {
      if (sugerencia['type'] != 'setMode') continue;
      if (sugerencia['destination'] != 'session') continue;
      final modo = sugerencia['mode'];
      if (modo is String && _conocidos.contains(modo)) return modo;
    }
    return null;
  }
}

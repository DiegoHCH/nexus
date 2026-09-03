import 'dart:async';

import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Las preguntas de permiso que están esperando respuesta.
///
/// 🔴 **Nada de esto avisa cuando se rompe.** Un `Completer` que se contesta dos
/// veces lanza; uno que no se contesta nunca deja el turno de `claude -p`
/// esperando para siempre, sin error, sin log y sin nada que mirar — la
/// conversación simplemente se queda quieta. Son exactamente las dos formas de
/// fallar que no dejan rastro, y vivían sueltas dentro de un controlador de
/// 2.159 líneas.
///
/// Aquí no hay estado de pantalla: quién contestó qué y cómo se pinta es del
/// controlador. Esto solo sabe quién espera y cómo se le suelta.
class LasPreguntasEnPie {
  final _esperando =
      <String, ({Completer<RespuestaDePermiso> completer, String cancelado})>{};

  bool get hayAlguna => _esperando.isNotEmpty;

  /// Los identificadores que siguen esperando.
  Iterable<String> get ids => _esperando.keys;

  /// Abre una pregunta y devuelve el futuro que se resolverá al contestarla.
  ///
  /// [cancelado] se resuelve **al encolar** y viaja con el completer. No es
  /// eficiencia: el motivo sale de los textos de la app, y soltar puede ocurrir
  /// dentro de un `onDispose`, donde Riverpod prohíbe leer otro proveedor. Es la
  /// tercera vez que esa regla muerde en esta funcionalidad; tomándolo aquí,
  /// contestar no depende de poder leer nada.
  ///
  /// Una petición con un `id` repetido **suelta a la anterior** en vez de
  /// pisarla: el `request_id` lo pone el CLI y no debería repetirse, pero si
  /// alguna vez lo hace, dejar el completer viejo sin completar cuelga ese turno
  /// para siempre.
  Future<RespuestaDePermiso> abrir(
    PeticionDePermiso peticion, {
    required String cancelado,
  }) {
    _soltar(_esperando.remove(peticion.id));
    final completer = Completer<RespuestaDePermiso>();
    _esperando[peticion.id] = (completer: completer, cancelado: cancelado);
    return completer.future;
  }

  /// Contesta una. `false` si ya no estaba —contestada, cancelada o de otra
  /// conversación—, que es lo que evita el segundo `complete`.
  bool contestar(String id, RespuestaDePermiso respuesta) {
    final espera = _esperando.remove(id);
    if (espera == null || espera.completer.isCompleted) return false;
    espera.completer.complete(respuesta);
    return true;
  }

  /// Suelta a todas con su motivo de cancelación. Idempotente: soltar dos veces
  /// no lanza, que importa porque una de las llamadas viene del `onDispose`.
  void soltarTodas() {
    if (_esperando.isEmpty) return;
    for (final espera in _esperando.values) {
      _soltar(espera);
    }
    _esperando.clear();
  }

  void _soltar(
    ({Completer<RespuestaDePermiso> completer, String cancelado})? espera,
  ) {
    if (espera == null || espera.completer.isCompleted) return;
    espera.completer.complete(PermisoDenegado(espera.cancelado));
  }
}

import 'package:meta/meta.dart';

/// Recuerda qué peticiones ya se atendieron, para que un reenvío no las repita.
///
/// **Es la pieza que evita que un encargo escriba dos veces en tus archivos.** Si
/// el WebSocket cae después de que el escritorio recibió el encargo pero antes de
/// confirmarlo, el móvil lo reenvía; sin esto, `claude -p` con `acceptEdits` corre
/// dos veces sobre los mismos archivos.
///
/// Vive en el protocolo y no en la app —ficha `lo3`— porque es una propiedad del
/// canal: cualquier cosa que se pida por aquí la necesita, no solo los encargos.
///
/// Con caducidad y no para siempre: la memoria de un servidor que nunca olvida
/// crece sin tope, y un `clientMsgId` de hace tres días no se va a reenviar. El TTL
/// es lo que convierte «recordar» en «recordar lo que puede volver».
class Deduplicator {
  Deduplicator({required this.ttl, DateTime Function()? reloj})
    : _reloj = reloj ?? DateTime.now;

  /// Cuánto se recuerda una petición.
  ///
  /// Generoso a propósito: tiene que cubrir el peor reintento imaginable de un
  /// móvil con mala cobertura, y el coste de recordar de más es unos bytes,
  /// mientras el coste de olvidar de menos es un encargo repetido.
  final Duration ttl;

  /// Inyectable: la caducidad **es** temporal, y probarla con el reloj de verdad
  /// significaría esperar.
  final DateTime Function() _reloj;

  final _vistas = <String, DateTime>{};

  /// Registra la petición y dice si **ya se había visto**.
  ///
  /// Devuelve `true` la primera vez. Un `false` no significa «rechaza»: significa
  /// «contéstale que ya la tienes y no la ejecutes otra vez».
  bool aceptar(String id) {
    _limpiar();
    if (_vistas.containsKey(id)) return false;
    _vistas[id] = _reloj();
    return true;
  }

  /// Si se recuerda, sin registrarla.
  bool conocida(String id) {
    _limpiar();
    return _vistas.containsKey(id);
  }

  @visibleForTesting
  int get recordadas {
    _limpiar();
    return _vistas.length;
  }

  /// Se limpia al consultar y no con un temporizador: un temporizador tendría que
  /// cancelarse al cerrar el servidor, y olvidarse de eso deja el proceso vivo.
  /// Aquí no hay nada que cancelar.
  void _limpiar() {
    final ahora = _reloj();
    _vistas.removeWhere((_, cuando) => ahora.difference(cuando) > ttl);
  }
}

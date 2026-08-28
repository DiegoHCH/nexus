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
///
/// **Y con tope de entradas, además del TTL.** La caducidad acota el tiempo pero
/// no la cantidad: dentro de la misma ventana de diez minutos, un cliente puede
/// mandar identificadores nuevos tan rápido como quiera. Los dos límites hacen
/// falta porque acotan cosas distintas.
class Deduplicator {
  Deduplicator({
    required this.ttl,
    this.maximo = 4096,
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now;

  /// Cuántas peticiones se recuerdan como mucho.
  ///
  /// Cuatro mil son muchas más de las que caben en una ventana de TTL de uso
  /// normal —un encargo por vez, y los reintentos de un móvil con mala
  /// cobertura son unos pocos— así que en la práctica nunca se toca. Está para
  /// el caso en que sí: entonces se olvida lo más viejo, que es también lo que
  /// menos probable es que vuelva.
  final int maximo;

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
    _recortar();
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

  /// Deja el recuerdo dentro del tope, tirando lo más antiguo.
  ///
  /// Por orden de inserción, que en un `Map` de Dart es el orden de iteración y
  /// aquí coincide con el orden temporal: lo primero que entró es lo primero que
  /// se va. Recorrer buscando la fecha más vieja daría lo mismo y costaría más.
  void _recortar() {
    while (_vistas.length > maximo) {
      _vistas.remove(_vistas.keys.first);
    }
  }
}

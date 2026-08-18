/// Las paradas del tour, en orden.
///
/// Son cuatro y no siete a propósito: **solo lo que un recién llegado tiene de
/// verdad en pantalla**. La columna de actividad aparece únicamente mientras hay
/// trabajo, y los artefactos cuando Claude ha producido alguno — señalar un hueco
/// vacío y decir «aquí verás cosas» es peor que no señalar nada, así que eso se
/// cuenta en la guía y no aquí.
enum TourStop {
  /// El orbe: hablarle, y el atajo global.
  orb,

  /// La caja de escribir, con los adjuntos.
  composer,

  /// El muelle de conversaciones: hasta tres a la vez.
  dock,

  /// La barra de arriba, donde aparecen contexto y cupo.
  topBar,
}

/// Por dónde va el tour.
///
/// `null` en [stop] significa que no está corriendo — ni terminado ni saltado,
/// simplemente no toca. Se distingue de «terminado» porque terminado se guarda
/// en disco y esto es de esta sesión.
class TourState {
  const TourState({this.stop, this.pending = const [], this.total = 0});

  /// La parada que se está enseñando, si alguna.
  final TourStop? stop;

  /// Las que quedan después de esta. Se calcula al arrancar, mirando **cuáles
  /// están montadas**: una parada sin su ancla en pantalla no se enseña.
  final List<TourStop> pending;

  /// Cuántas paradas tiene este tour, fijadas al arrancar.
  ///
  /// Vive aquí y no se recalcula en cada paso a propósito: si se contaran las
  /// anclas presentes cada vez, «paso 2 de 4» pasaría a «paso 3 de 3» solo
  /// porque una pieza dejó de estar en pantalla.
  final int total;

  bool get running => stop != null;

  /// Cuál va, contando la actual. `0` si no está corriendo.
  int get index => stop == null ? 0 : total - pending.length;
}

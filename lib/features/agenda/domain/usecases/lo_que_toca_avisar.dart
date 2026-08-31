import 'package:nexus/features/agenda/domain/entities/reunion.dart';

/// Qué hay que decir ahora mismo, y con qué palabras.
///
/// Vive fuera de todo lo demás porque son **reglas y no fontanería**: qué
/// cuenta como reunión, cuándo entra en la ventana y cómo no repetirse. Son las
/// tres cosas que se rompen sin que nadie se entere — un aviso que no suena no
/// deja rastro— así que están aquí, puras y cubiertas.
abstract final class LoQueTocaAvisar {
  /// Las que entran en la ventana y todavía no se avisaron.
  ///
  /// La ventana se abre en [antes] y **se cierra al empezar la reunión**: pasada
  /// la hora, avisar ya no ayuda a llegar — y si la app estuvo cerrada toda la
  /// mañana, al abrirla no tiene que soltar los seis avisos que se perdió.
  static List<Reunion> ahora(
    List<Reunion> agenda, {
    required DateTime cuando,
    required Duration antes,
    required Set<String> yaAvisadas,
  }) {
    final limite = cuando.add(antes);
    return [
      for (final reunion in agenda)
        if (reunion.esUnaReunion &&
            !yaAvisadas.contains(reunion.id) &&
            !reunion.comienza.isBefore(cuando) &&
            !reunion.comienza.isAfter(limite))
          reunion,
    ]..sort((a, b) => a.comienza.compareTo(b.comienza));
  }

  /// Lo que se dice en voz alta.
  ///
  /// Título y hora, y nada más. Leer la descripción sacaría por el altavoz
  /// cosas que no quieres con alguien delante, y los nombres de los invitados
  /// tampoco: quien oye el aviso no siempre está solo.
  ///
  /// Los minutos se cuentan **redondeando hacia arriba**: a falta de cuatro
  /// minutos y medio, «en cinco minutos» es verdad y «en cuatro» te haría llegar
  /// tarde. Y menos de un minuto se dice como lo que es.
  static String comoSeDice(
    Reunion reunion, {
    required DateTime cuando,
    required String Function(String titulo, int minutos) plantilla,
    required String Function(String titulo) ahoraMismo,
  }) {
    final faltan = reunion.comienza.difference(cuando);
    final minutos = (faltan.inSeconds / 60).ceil();
    if (minutos <= 0) return ahoraMismo(reunion.titulo);
    return plantilla(reunion.titulo, minutos);
  }
}

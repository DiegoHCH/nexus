import 'package:nexus/features/agenda/domain/entities/reunion.dart';
import 'package:nexus/features/agenda/domain/usecases/la_jornada.dart';

/// Qué se contesta a «¿qué tengo hoy?», con la agenda que ya está en memoria.
///
/// Vive aquí y no en el vigilante porque las tres salidas son **decisiones y no
/// formato**, y cada una dice algo distinto:
///
/// - fuera de jornada la agenda está borrada, así que «no tienes reuniones»
///   sería mentir sobre un día que sí las tuvo;
/// - dentro de jornada y sin nada, sí se puede decir que no hay;
/// - y lo que se enseña son **solo las reuniones de verdad** —las que tienen
///   invitados—, porque el calendario lleva «comer» y «foco» y contarlos como
///   agenda es el mismo ruido que ya se decidió no avisar.
///
/// Los textos entran por parámetro: el dominio no conoce `NexusStrings`.
abstract final class LoQueSeContestaDeLaAgenda {
  static String respuesta(
    List<Reunion> agenda, {
    required DateTime cuando,
    required String fueraDeJornada,
    required String vacia,
    required String Function(int cuantas) cabecera,
  }) {
    if (!LaJornada.dentro(cuando)) return fueraDeJornada;

    final reuniones = lasQueCuentan(agenda);
    if (reuniones.isEmpty) return vacia;

    return [
      cabecera(reuniones.length),
      for (final reunion in reuniones)
        '- ${laHora(reunion.comienza)} · ${reunion.titulo}',
    ].join('\n');
  }

  /// Las reuniones de verdad, en orden de reloj.
  static List<Reunion> lasQueCuentan(List<Reunion> agenda) => [
    for (final reunion in agenda)
      if (reunion.esUnaReunion) reunion,
  ]..sort((a, b) => a.comienza.compareTo(b.comienza));

  /// `HH:mm` con el cero delante. A mano y no con `intl`: es la hora local del
  /// reloj de esta máquina, no una fecha que haya que localizar.
  static String laHora(DateTime cuando) =>
      '${cuando.hour.toString().padLeft(2, '0')}:'
      '${cuando.minute.toString().padLeft(2, '0')}';
}

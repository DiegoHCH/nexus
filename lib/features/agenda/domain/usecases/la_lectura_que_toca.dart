import 'package:nexus/features/agenda/domain/usecases/la_jornada.dart';

/// Qué hacer con la agenda en este momento.
///
/// Las cuatro salidas son distintas de verdad, y confundir dos de ellas ya
/// costó un fallo: [esperarALaCarpeta] **no marca el ancla** y [leerla] sí, así
/// que tratarlas igual haría que la lectura del arranque se diera por hecha
/// con la cuenta equivocada.
enum QueHacerConLaAgenda {
  /// Fin de semana o pasada la hora de cierre: lo que quede en memoria es la
  /// lista de una jornada que terminó y sirve para contestar mal.
  olvidarla,

  /// Ya está leída para este ancla, o no hay carpeta configurada. No se
  /// consulta y no se toca lo que hay.
  dejarlaComoEsta,

  /// La carpeta está elegida pero el workspace todavía no la trae. Se espera al
  /// siguiente tic **sin marcar el ancla**: son treinta segundos y no cuestan
  /// una consulta, porque aquí todavía no se ha llamado a nadie.
  esperarALaCarpeta,

  /// Toca preguntarle al calendario.
  leerla,
}

/// Cuándo se sale a leer el calendario, y qué pasa con lo que ya había.
///
/// 🔴 **Estaba dentro del vigilante, y por eso no lo cubría nada.** Son cuatro
/// decisiones encadenadas cuyo error no se ve —una lectura de más gasta cupo de
/// la suscripción, una de menos deja la mañana sin avisos— y el suelo de
/// cobertura del CI solo mira `domain`, así que ahí arriba se libraban por
/// dónde estaba el archivo y no por lo que hacen.
abstract final class LaLecturaQueToca {
  static ({QueHacerConLaAgenda que, DateTime? ancla}) para({
    required DateTime ahora,
    required DateTime? leidoDesde,
    required String? carpeta,
    required bool carpetaEmparejada,
  }) {
    final ancla = LaJornada.anclaPara(ahora);
    if (ancla == null) {
      return (que: QueHacerConLaAgenda.olvidarla, ancla: null);
    }
    if (leidoDesde == ancla) {
      return (que: QueHacerConLaAgenda.dejarlaComoEsta, ancla: ancla);
    }
    if (carpeta == null || carpeta.isEmpty) {
      return (que: QueHacerConLaAgenda.dejarlaComoEsta, ancla: ancla);
    }
    if (!carpetaEmparejada) {
      return (que: QueHacerConLaAgenda.esperarALaCarpeta, ancla: ancla);
    }
    return (que: QueHacerConLaAgenda.leerla, ancla: ancla);
  }
}

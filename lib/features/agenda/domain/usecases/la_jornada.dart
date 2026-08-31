/// Cuándo se mira el calendario y cuándo se deja de mirar.
///
/// Vive aparte del vigilante porque son **reglas de jornada, no fontanería**, y
/// porque son las que deciden cuántas veces se le pregunta a la cuenta. Una
/// regla equivocada aquí no se ve: se traduce en consultas que nadie pidió o en
/// avisos que no llegan.
abstract final class LaJornada {
  /// A qué hora se vuelve a leer la agenda del día. Lo que se programa de un
  /// día para otro ya está puesto; lo que se programe después se pide a mano.
  static const relectura = 8;

  /// A qué hora se olvida.
  ///
  /// 🔴 **La agenda se borra, no solo se deja de avisar.** Lo que queda en
  /// memoria a las siete de la tarde es la lista de reuniones de una jornada
  /// que terminó: sirve para contestar mal —«hoy no tienes reuniones», cuando
  /// las tuviste— y para nada más.
  static const acaba = 18;

  /// De lunes a viernes. Preguntarle a la cuenta un sábado es gastar un encargo
  /// para que conteste lo que ya se sabe.
  static bool esLaborable(DateTime cuando) => cuando.weekday <= DateTime.friday;

  static bool dentro(DateTime cuando) =>
      esLaborable(cuando) && cuando.hour < acaba;

  /// El ancla de lectura que toca, o `null` si ahora no toca ninguna — fin de
  /// semana, o pasada la hora de cierre.
  ///
  /// Dos por día laborable como mucho: el arranque y las ocho. Anclarlo solo a
  /// las ocho deja sin avisos a quien abre la app a las siete; leer solo al
  /// arrancar deja fuera lo que se programe de un día para otro.
  static DateTime? anclaPara(DateTime ahora) {
    if (!dentro(ahora)) return null;
    return ahora.hour >= relectura
        ? DateTime(ahora.year, ahora.month, ahora.day, relectura)
        : DateTime(ahora.year, ahora.month, ahora.day);
  }
}

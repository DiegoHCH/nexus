/// Reconoce cuándo lo que se escribió es «¿qué tengo hoy?».
///
/// **Se compara la frase entera contra una lista cerrada**, igual que el parte
/// del día y por el mismo motivo: buscar «reunión» dentro del texto convertiría
/// «arregla el bug de la pantalla de reuniones» en una consulta de agenda, y
/// secuestrar trabajo de verdad es mucho peor que no reconocer una forma de
/// preguntar. Lo que no encaje sigue su camino de siempre, hacia Claude.
abstract final class LoQueSePreguntaDeLaAgenda {
  static bool loEstanPidiendo(String frase) =>
      _comoSePide.contains(_sinAdornos(frase));

  /// Las formas que se reconocen. Cortas a propósito: son las que se escriben
  /// **para preguntar esto y nada más**.
  static const _comoSePide = {
    'que reuniones tengo',
    'que reuniones tengo hoy',
    'reuniones de hoy',
    'mis reuniones',
    'mis reuniones de hoy',
    'que tengo hoy',
    'que hay hoy',
    'mi agenda',
    'mi agenda de hoy',
    'la agenda',
    'la agenda de hoy',
    'agenda',
    'agenda de hoy',
    'que tengo en la agenda',
  };

  /// Sin tildes, sin signos y en minúsculas: «¿Qué reuniones tengo hoy?» y «que
  /// reuniones tengo hoy» son la misma pregunta.
  static String _sinAdornos(String frase) {
    const conTilde = 'áéíóúüñ';
    const sinTilde = 'aeiouun';
    var limpia = frase.trim().toLowerCase();
    for (var i = 0; i < conTilde.length; i++) {
      limpia = limpia.replaceAll(conTilde[i], sinTilde[i]);
    }
    return limpia.replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
  }
}

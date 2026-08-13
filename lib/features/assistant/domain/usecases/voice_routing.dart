/// Qué puede contestar el modelo de voz por su cuenta, decidido **aquí** y no
/// por él.
///
/// La regla del producto es que todo va a Claude —«tú pones la voz, Claude pone
/// el trabajo»— y hasta ahora eso era una instrucción en el prompt: el modelo la
/// cumplía casi siempre, y en la zona gris contestaba de memoria sin avisar. Se
/// intentó cerrarlo por la vía limpia, pidiéndole al servicio que **obligue** a
/// llamar a una herramienta: la API de voz no lo admite —probado con
/// `toolConfig` en la raíz, dentro de `generationConfig`, y como `toolChoice`;
/// las tres veces contesta «Unknown name» y corta la conexión—. Así que la
/// comprobación se hace de este lado.
///
/// La lista es corta y deliberadamente literal. Lo que no esté en ella va a
/// Claude aunque el modelo ya haya contestado: equivocarse llamando cuesta unos
/// segundos, y equivocarse contestando de memoria cuesta un dato falso dicho con
/// seguridad.
abstract final class VoiceRouting {
  /// Cortesía y control de la conversación: saludos, despedidas, gracias,
  /// «para», «espera», «repite». Nada que hable del Mac, del proyecto o del
  /// mundo entra aquí.
  static final _smallTalk = RegExp(
    r'^(hola|buenas|buenos d[ií]as|buenas tardes|buenas noches|qu[eé] tal|'
    r'c[oó]mo est[aá]s|hey|oye|nexus|gracias|much[ií]simas gracias|vale|ok|'
    r'okey|perfecto|gen(i)?al|adi[oó]s|hasta luego|chao|nos vemos|para|'
    r'p[aá]rate|espera|esp[eé]rate|silencio|c[aá]llate|repite|rep[ií]telo|'
    r'otra vez|no te entend[ií]|qu[eé] dijiste|'
    r'hi|hello|hey there|thanks|thank you|thanks a lot|okay|cool|bye|'
    r'goodbye|see you|stop|wait|hold on|be quiet|repeat|say that again|'
    r'what did you say)\b',
    caseSensitive: false,
  );

  /// Una frase corta y sin verbo de encargo. El tope de palabras importa:
  /// «hola, mira el historial de git» empieza como un saludo y **no** lo es.
  static const _maxSmallTalkWords = 4;

  /// `true` si esto tenía que haber pasado por Claude.
  static bool needsClaude(String utterance) {
    final clean = utterance
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[¿?¡!.,;:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return false;
    if (clean.split(' ').length > _maxSmallTalkWords) return true;
    return !_smallTalk.hasMatch(clean);
  }

  /// Lo que se le entrega al modelo cuando contestó de memoria algo que no le
  /// tocaba. No se le regaña: se le da el dato bueno y que lo cuente él, que es
  /// lo único que el usuario nota.
  static String correction(String answer) =>
      'Esto lo ha respondido Claude, que es quien tiene acceso a esta máquina. '
      'Cuéntaselo tal cual, sin añadir nada de tu parte y sin disculparte:\n\n'
      '$answer';
}

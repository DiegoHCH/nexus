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

  /// 🔴 **Lo que le preguntan sobre sí mismo lo contesta él**, y no por
  /// cortesía: es lo único que Claude **no** sabe. «¿Quién eres?» son dos
  /// palabras que no son un saludo, así que iban a Claude — que contestaba con
  /// verdad quién es *él*, y de ahí el reporte: «si le preguntas quién eres
  /// responde que es Claude, o que es Gemini hablando». La pregunta acababa en
  /// el único sitio que no podía responderla.
  ///
  /// Va **antes** del tope de palabras a propósito: estas preguntas se hacen
  /// largas —«¿tú eres Nexus o eres Claude?»— y con el tope delante volverían a
  /// enrutarse. Quién es lo dice `QuienEsNexus`, en el prompt del sistema.
  static final _quienEres = RegExp(
    r'(qui[eé]n eres|qui[eé]n hablo|con qui[eé]n hablo|c[oó]mo te llamas|'
    r'tu nombre|qu[eé] eres|qu[eé] sos|eres nexus|sos nexus|eres claude|'
    r'eres gemini|eres una? (ia|inteligencia)|qui[eé]n te hizo|'
    r'qu[eé] modelo eres|pres[eé]ntate|h[aá]blame de ti|'
    r'who are you|who am i (talking|speaking) to|what are you|'
    r"what'?s your name|your name|are you nexus|are you claude|are you gemini|"
    r'introduce yourself|tell me about yourself|which model are you)',
    caseSensitive: false,
  );

  /// Lo que sabe hacer, que es la otra mitad de presentarse.
  ///
  /// ⚠️ **Estas van con freno**, y es la parte delicada: «¿qué puedes hacer?»
  /// habla de ella, pero «¿qué puedes hacer con este repositorio?» es un
  /// encargo de los buenos. Enrutar de más cuesta unos segundos; contestar de
  /// memoria sobre esta máquina cuesta un dato falso dicho con seguridad, así
  /// que ante la duda va a Claude. Ver [_apuntaAAlgoDeAqui].
  static final _loQueSabeHacer = RegExp(
    r'(para qu[eé] sirves|qu[eé] sabes hacer|qu[eé] puedes hacer|'
    r'qu[eé] haces t[uú]|what can you do|what do you do)',
    caseSensitive: false,
  );

  /// Si la frase señala algo de esta máquina. Con esto delante, lo de «qué
  /// puedes hacer» ya no habla de ella: habla de lo que hay aquí, y eso lo sabe
  /// Claude y no ella.
  static final _apuntaAAlgoDeAqui = RegExp(
    r'\b(este|esta|esto|estos|estas|mi|mis|aqu[ií]|repo|repositorio|carpeta|'
    r'proyecto|c[oó]digo|rama|archivo|test|prueba|this|these|my|here)\b',
    caseSensitive: false,
  );

  /// Cuántas palabras se le aguantan a una pregunta sobre lo que sabe hacer.
  /// Más que eso ya suele traer un complemento, y el complemento es el encargo.
  static const _maxPalabrasDeLoSuyo = 5;

  /// Si esto es una pregunta sobre sí misma.
  static bool esSobreElla(String utterance) {
    final limpia = _limpia(utterance);
    if (_quienEres.hasMatch(limpia)) return true;
    if (!_loQueSabeHacer.hasMatch(limpia)) return false;
    return limpia.split(' ').length <= _maxPalabrasDeLoSuyo &&
        !_apuntaAAlgoDeAqui.hasMatch(limpia);
  }

  /// Una frase corta y sin verbo de encargo. El tope de palabras importa:
  /// «hola, mira el historial de git» empieza como un saludo y **no** lo es.
  static const _maxSmallTalkWords = 4;

  /// `true` si esto tenía que haber pasado por Claude.
  ///
  /// **Sigue juzgando la transcripción a propósito**, aunque llegue mal. Es un
  /// filtro barato para no montar una ronda entera por un «gracias», y el
  /// destrozo del servicio de voz no lo rompe en la dirección peligrosa: una
  /// frase mal oída sigue siendo larga y sigue sin parecer cortesía, así que
  /// sigue enrutando. Lo que no aguantaba el texto roto era **el contenido** del
  /// encargo, y de eso ya no se encarga (ver [pasaloTu]).
  static bool needsClaude(String utterance) {
    final clean = _limpia(utterance);
    if (clean.isEmpty) return false;
    // Lo suyo, primero: ver [_quienEres] para por qué va delante del tope.
    if (esSobreElla(clean)) return false;
    if (clean.split(' ').length > _maxSmallTalkWords) return true;
    return !_smallTalk.hasMatch(clean);
  }

  /// Sin signos, sin dobles espacios y en minúsculas: lo que llega del servicio
  /// de voz viene puntuado a su gusto.
  static String _limpia(String utterance) => utterance
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[¿?¡!.,;:]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Lo primero que se le dice cuando contestó de memoria: **que lo pase él**.
  ///
  /// 🔴 **Se le pide a él porque él sí te oyó.** La corrección se construía con
  /// la transcripción de lo que dijiste, y esa la escribe el servicio de voz
  /// aparte — y llega mal: «¿qué reuniones tengo para hoy?» se transcribió como
  /// «Este akeroniano es tengo para hoy». El modelo, en cambio, había entendido
  /// perfectamente: contestó las cinco reuniones correctas. Lo que fallaba era
  /// el texto, no la comprensión, y mandarle a Claude ese texto como encargo es
  /// mandarle una frase que nadie dijo.
  ///
  /// No se puede arreglar por configuración: en un modelo de audio nativo el
  /// idioma se autodetecta y `inputAudioTranscription` no acepta parámetros —la
  /// doc de la Live API dice literalmente que fijar un código de idioma no está
  /// soportado ahí—. Así que se deja de depender del texto para lo que importa:
  /// **la instrucción la redacta quien oyó el audio**.
  ///
  /// Es una petición y no una garantía: la API de voz no admite obligar a
  /// llamar a una herramienta —está probado y anotado arriba—, así que si no
  /// hace caso queda el camino de antes. Por eso existe [deLaTranscripcion].
  static const pasaloTu =
      'No contestes de memoria: en este Mac todo lo contesta Claude. Vuelve a '
      'atender lo último que te pedí llamando a pedir_a_claude, redactando la '
      'instrucción con lo que me oíste decir. No te disculpes ni lo comentes: '
      'llama a la herramienta y luego cuenta lo que devuelva.';

  /// El encargo de última hora, cuando el modelo no pasó nada ni pidiéndoselo.
  ///
  /// 🔴 **Va marcado como transcripción, y eso es medio arreglo.** Aquí ya no
  /// queda más que el texto del servicio de voz, que puede estar roto; decirle
  /// a Claude de dónde salió es lo que le permite leer la intención en vez de
  /// tomárselo al pie de la letra. Sin la marca, «Este akeroniano es tengo para
  /// hoy» es una pregunta absurda; con ella, es una frase mal oída que se deja
  /// interpretar.
  static String deLaTranscripcion(String utterance) =>
      'Esto es la transcripción automática de algo que se dijo en voz alta, y '
      'puede tener palabras mal oídas: «$utterance».\n\n'
      'Interpreta qué se estaba pidiendo y respóndelo. Si de verdad no se '
      'entiende qué se pedía, dilo en una frase en vez de adivinar.';

  /// Lo que se le entrega al modelo cuando contestó de memoria algo que no le
  /// tocaba. No se le regaña: se le da el dato bueno y que lo cuente él, que es
  /// lo único que el usuario nota.
  static String correction(String answer) =>
      'Esto lo ha respondido Claude, que es quien tiene acceso a esta máquina. '
      'Cuéntaselo tal cual, sin añadir nada de tu parte y sin disculparte:\n\n'
      '$answer';
}

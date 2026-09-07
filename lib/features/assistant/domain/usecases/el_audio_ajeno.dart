/// Qué hacer con lo que suena alrededor y no iba dirigido a Nexus.
///
/// 🔴 **Pasó, dos corridas seguidas y con la transcripción delante.** Con la
/// sesión de voz abierta, el micrófono recogió conversación de la habitación
/// —«sí, porque el otro muchacho fue el que hizo el servicio en el día»— y el
/// modelo la contestó. Peor todavía: el servicio la tomó por una interrupción y
/// **cortó lo que estaba diciendo** a media frase. Dos de los tres turnos de esa
/// sesión no pasaron por Claude, y ninguno de los dos se le había dicho a nadie.
///
/// Lo que se decide aquí es **quién manda en la interrupción**. Antes la decidía
/// el detector de voz del servicio: cualquier sonido con forma de habla cortaba
/// la respuesta. Ahora el servicio no interrumpe nunca —`NO_INTERRUPTION` en el
/// `setup`— y la decisión es de este lado, con la transcripción en la mano.
///
/// La regla es corta a propósito: **mientras Nexus habla, solo le interrumpe
/// quien le habla a ella**. Dos formas de hacerlo, y las dos son las que
/// cualquiera usa sin que se le explique:
///
/// - **Decirle su nombre.** Es lo que hace todo el mundo con un asistente.
/// - **Una palabra de control**: «para», «espera», «cállate», «repite». Son las
///   que se dicen justo cuando está hablando y hay que poder decirlas.
///
/// Lo que llegue mientras habla y no sea una de las dos, **se ignora entero**:
/// no va a Claude, su respuesta no suena y no cuenta como actividad —así la
/// sesión se cierra sola a los seis segundos en vez de quedarse abierta oyendo
/// la habitación—. Y se dice, que es la otra mitad: un turno tirado en silencio
/// se lee como que la voz no funciona.
///
/// **En silencio no se filtra nada.** Cuando Nexus no está hablando, lo que
/// llega se atiende como siempre: la sesión la abriste tú y lo primero que dices
/// va dirigido a ella por construcción. Exigir el nombre en cada frase
/// convertiría una conversación en una lista de órdenes.
abstract final class ElAudioAjeno {
  /// Palabras con las que se corta a alguien que está hablando.
  ///
  /// **Es a propósito una lista más corta que la de cortesía** de
  /// [VoiceRouting]: «hola» o «gracias» no interrumpen a nadie, y con ellas
  /// dentro cualquier «gracias» de fondo volvería a cortar la respuesta — que es
  /// justo el fallo que esto viene a cerrar.
  static final _deControl = RegExp(
    r'\b(para|p[aá]rate|espera|esp[eé]rate|silencio|c[aá]llate|calla|'
    r'repite|rep[ií]telo|otra vez|d[eé]jalo|olv[ií]dalo|'
    r'stop|wait|hold on|be quiet|quiet|repeat|say that again|never mind)\b',
    caseSensitive: false,
  );

  /// Si esto puede cortar lo que Nexus está diciendo.
  ///
  /// [agente] es cómo se llama ella en esta instalación —se puede cambiar en
  /// Ajustes—, y se acepta también «nexus» a secas: es el nombre del producto y
  /// el que sale solo cuando alguien no recuerda el que puso.
  static bool interrumpe(String frase, {String? agente}) {
    final limpia = _limpia(frase);
    if (limpia.isEmpty) return false;
    if (_deControl.hasMatch(limpia)) return true;
    for (final nombre in {'nexus', ...?_nombre(agente)}) {
      if (RegExp('\\b${RegExp.escape(nombre)}\\b').hasMatch(limpia)) {
        return true;
      }
    }
    return false;
  }

  /// Si este turno se tira: llegó mientras hablaba y no iba con ella.
  static bool seIgnora(
    String frase, {
    required bool estabaHablando,
    String? agente,
  }) =>
      estabaHablando &&
      _limpia(frase).isNotEmpty &&
      !interrumpe(frase, agente: agente);

  static Iterable<String>? _nombre(String? agente) {
    final limpio = _limpia(agente ?? '');
    return limpio.isEmpty ? null : [limpio];
  }

  /// Sin signos y en minúsculas: la transcripción del servicio trae comas y
  /// puntos donde le parece, y «¿nexus?» tiene que valer igual que «nexus».
  static String _limpia(String frase) => frase
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[¿?¡!.,;:«»"]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

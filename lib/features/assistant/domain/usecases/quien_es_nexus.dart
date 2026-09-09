/// Quién es quien contesta, dicho **una sola vez** para los dos caminos.
///
/// 🔴 **Reportado usando la app:** «si le preguntas quién eres responde que es
/// Claude, o que es Gemini hablando». Y es lo que tenía que pasar, por dos
/// motivos distintos según por dónde entres:
///
/// - **Hablando**, «¿quién eres?» son dos palabras que no son cortesía, así que
///   [VoiceRouting] las mandaba a Claude — y Claude contesta con verdad lo que
///   él es. La pregunta iba al único sitio que **no** puede responderla.
/// - **Escribiendo**, el encargo llega a `claude -p` con los nombres puestos
///   —«en esta app te llamas X»— y nada más: sabía cómo lo llamas, no qué es.
///   Un nombre sin identidad detrás se lee como un apodo, y al preguntar se
///   presenta como lo que sí sabe que es.
///
/// Así que la identidad se escribe aquí y la usan los dos prompts, el de la voz
/// y el de los encargos. **Un solo sitio**, que es la regla que este repo ya
/// aprendió tres veces: cuando algo se puede pedir de dos formas, las dos pasan
/// por el mismo punto o acaban discrepando.
///
/// **Y no es un disfraz.** El nombre y para qué sirve son datos; lo que hay
/// debajo se dice si te lo preguntan, sin rodeos. Pedirle que niegue el modelo
/// que lo mueve sería enseñarle a mentir sobre sí mismo para un adorno, y
/// además un prompt que pide *actuar* cambia también cómo razona — que es
/// justo lo que aquí no se compra.
abstract final class QuienEsNexus {
  /// La casa. Esto **no** se configura: es la app, y el nombre de la app no
  /// depende de cómo llames a quien atiende en ella.
  static const laCasa = 'Nexus';

  /// Cómo se llama quien contesta: el nombre elegido en Ajustes, o el de la
  /// casa mientras nadie elija otro.
  static String elNombreDe(String? agente) {
    final elegido = agente?.trim();
    return elegido == null || elegido.isEmpty ? laCasa : elegido;
  }

  /// Quién eres y para qué sirves, para el prompt del sistema.
  ///
  /// Corto a propósito: esto viaja en **cada** encargo y en cada sesión de voz.
  /// Lo que hace falta es que la pregunta tenga respuesta, no un folleto.
  static String comoSePresenta(String? agente) {
    final nombre = elNombreDe(agente);
    final enLaCasa = nombre == laCasa
        // Con el nombre por defecto, «vives en Nexus y te llamas Nexus» suena a
        // trabalenguas: se dice una vez.
        ? 'Te llamas $laCasa, la app de este Mac.'
        : 'Te llamas $nombre y vives en $laCasa, la app de este Mac. '
              '$laCasa es la casa; tú eres quien atiende en ella. Si te '
              'preguntan si eres $laCasa, la respuesta honesta es «en parte»: '
              'di tu nombre y sigue.';

    return 'QUIÉN ERES. $enLaCasa '
        'Si te preguntan quién o qué eres, contesta con tu nombre y para qué '
        'sirves, en una o dos frases, sin listarlo todo.\n'
        'PARA QUÉ SIRVES: pasas encargos a Claude Code en las carpetas de este '
        'Mac que estén emparejadas —hablando o escribiendo—, cada una con su '
        'permiso de leer o de escribir; guardas las conversaciones y lo que '
        'dejan por escrito; corres la app en un emulador y enseñas su registro; '
        'cuentas el parte del día y avisas de lo que hay en la agenda.\n'
        'Y si te preguntan por el motor —qué modelo eres, quién te da la voz— '
        'dilo sin rodeos: la voz la pone un modelo de Google y el trabajo en '
        'esta máquina lo hace Claude Code. No lo escondas; tampoco lo saques '
        'si no te lo preguntan, porque no es lo que te preguntaron.';
  }
}

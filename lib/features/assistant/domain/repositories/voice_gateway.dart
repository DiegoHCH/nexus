import 'dart:typed_data';

import 'package:nexus/features/assistant/domain/entities/voice_event.dart';

/// Los dos ritmos del audio de la conversación.
///
/// Viven en el dominio, y no en el detalle del socket, por lo mismo que
/// [VoiceInput.sampleRate]: no son una opción nuestra, son el contrato del
/// servicio de voz. Entra a 16 kHz y sale a 24 kHz, sin negociación posible.
abstract final class VoiceSessionFormat {
  static const int inputSampleRate = 16000;
  static const int outputSampleRate = 24000;
  static const int channels = 1;
}

/// Quien sabe abrir una conversación de voz. Una implementación por servicio;
/// hoy solo la Live API de Gemini.
/// Con qué se abre una sesión: quién es y qué puede llamar.
///
/// 🔴 **Existe porque no todas las sesiones son una conversación.** La de
/// siempre lleva la persona del asistente y todas sus herramientas, y con eso
/// puesto el modelo se comporta como Nexus entero: a la puerta, al preguntarle
/// dónde trabajar, le contestaba «voy a inicializar el entorno en la carpeta de
/// nexus» —intentando llamar a una herramienta que ahí no pinta nada—.
///
/// Y lo que tenga que decir **no puede ir como nota de sistema**: eso se manda
/// como un turno de usuario, o sea que el modelo lo recibe como si alguien se lo
/// hubiera pedido por teclado. Se vio en pantalla: «Argonauta, me pidieron que
/// dijera eso exactamente». Va en la instrucción del setup, que es donde vive
/// quién es.
sealed class PerfilDeVoz {
  const PerfilDeVoz();
}

/// La de siempre: la conversación entera, con su persona y sus herramientas.
final class ComoUnaConversacion extends PerfilDeVoz {
  const ComoUnaConversacion();
}

/// La puerta del arranque: saluda, pregunta dónde se trabaja, y nada más.
final class ComoLaPuerta extends PerfilDeVoz {
  const ComoLaPuerta({required this.saludo, required this.carpetas});

  /// La frase con la que empieza, ya compuesta con la hora y el nombre.
  final String saludo;

  /// Los nombres que puede reconocer. **Solo para reconocer**: quien valida y
  /// abre es la app, con la lista de verdad.
  final List<String> carpetas;
}

/// Un aviso: dice una frase y se va. Sin herramientas y sin escuchar.
///
/// Nace de que el TTS del nivel gratuito se agota con dos o tres avisos al día
/// —medido: `RPD 13/10`— y el aviso de una reunión que llega en silencio ha
/// dejado de ser un aviso. El Live no se agota en uso normal.
final class ComoUnAviso extends PerfilDeVoz {
  const ComoUnAviso(this.frase);

  /// Lo que hay que decir, **literal**. Que lo diga tal cual es el requisito de
  /// esta sesión: un aviso que se reformula ya no dice la hora ni el título.
  final String frase;
}

abstract class VoiceGateway {
  /// Abre una conversación **nueva**, sin memoria de las anteriores. Lanza si
  /// no hay llave guardada o si el servicio rechaza la conexión.
  /// [perfil] decide quién es el modelo en esta sesión. Ver [PerfilDeVoz].
  Future<VoiceSession> connect({
    PerfilDeVoz perfil = const ComoUnaConversacion(),
  });

  /// Reengancha **la misma conversación** en una conexión nueva, conservando
  /// lo que ya se había hablado.
  ///
  /// No es un lujo: el servicio corta cada conexión al cabo de unos minutos,
  /// así que sin esto una charla larga —o un par de encargos lentos a Claude—
  /// se moriría a media frase. Lanza si esa conversación ya no se puede
  /// recuperar, y entonces lo honesto es cerrar y que el usuario vuelva a
  /// abrir, no seguir con una memoria en blanco disimulando.
  Future<VoiceSession> resume();
}

/// Una conversación abierta. Vive hasta que alguien la cierra.
abstract class VoiceSession {
  /// Todo lo que llega del servicio. Se cierra cuando la sesión termina.
  Stream<VoiceEvent> get events;

  /// Por qué terminó, si terminó de forma anormal. `null` si acabó bien o
  /// sigue viva.
  ///
  /// La sesión **no decide** si eso es un fallo: informa. El servicio corta
  /// conexiones cada pocos minutos, a veces sin despedirse, y quien sabe si
  /// eso importa es quien lleva el ciclo de vida — que puede reengancharse y
  /// seguir como si nada.
  String? get endReason;

  /// Empuja un trozo de micrófono: PCM 16 bits mono a
  /// [VoiceSessionFormat.inputSampleRate].
  void sendAudio(Uint8List pcm);

  /// Dice que el audio se acabó, para que el servicio cierre el turno y conteste.
  ///
  /// **Hace falta porque el detector de turno es automático y mira el audio**: espera
  /// ver silencio para decidir que terminaste de hablar. El micrófono del Mac se lo da
  /// siempre —sigue mandando aunque calles— pero el del teléfono **deja de mandar de
  /// golpe** cuando se cierra, así que el servicio se quedaba esperando un silencio que
  /// nunca llegaba: la sesión moría por inactividad con cero turnos.
  ///
  /// Medido así: 65 trozos entrando, un solo evento del servicio —el del montaje— y
  /// ninguna respuesta.
  void endAudio();

  /// Le mete a la conversación un texto que no vino del micrófono.
  ///
  /// Se usa para corregir al modelo cuando contesta por su cuenta algo que
  /// tenía que haber pasado por Claude: se le entrega la respuesta buena y la
  /// cuenta él. Sin esto, la única forma de meter texto en la conversación
  /// sería fingir que lo dijo el usuario.
  void sendSystemNote(String text);

  /// Devuelve el resultado de un [VoiceToolRequested].
  ///
  /// Es obligatorio contestar siempre, también cuando la herramienta falla:
  /// el modelo se queda esperando esta respuesta y sin ella la conversación
  /// se cuelga en silencio. Por eso [result] admite tanto el resultado como
  /// la explicación del error.
  void sendToolResult({
    required String callId,
    required String name,
    required String result,
  });

  Future<void> close();
}

import 'dart:typed_data';

/// Lo que ocurre dentro de una sesión de voz, ya traducido del JSON crudo de
/// la Live API a algo que el dominio entiende.
///
/// Es deliberadamente parecido a [ClaudeEvent]: los dos modelos entran a la
/// app por la misma forma —un stream de eventos de dominio— aunque por dentro
/// uno sea un proceso y el otro un socket.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// La sesión quedó configurada y acepta audio. Llega una sola vez.
final class VoiceSessionReady extends VoiceEvent {
  const VoiceSessionReady();
}

/// Trozo de la transcripción de **lo que dijo el usuario**, según lo va
/// oyendo el modelo. Llega en pedazos, no frase a frase.
final class VoiceUserTranscript extends VoiceEvent {
  const VoiceUserTranscript(this.text);

  final String text;
}

/// Trozo de la transcripción de **lo que responde el modelo**.
///
/// Lo da la propia API si se pide en el `setup`, así que la franja de
/// subtítulos no transcribe nada por su cuenta: pinta esto.
final class VoiceReplyTranscript extends VoiceEvent {
  const VoiceReplyTranscript(this.text);

  final String text;
}

/// Audio de la respuesta: PCM de 16 bits, mono, a [VoiceSessionFormat.output].
final class VoiceReplyAudio extends VoiceEvent {
  const VoiceReplyAudio(this.pcm);

  final Uint8List pcm;
}

/// El modelo pide ejecutar la herramienta: quiere que Claude haga algo real.
///
/// No sale hacia la interfaz — lo atiende el caso de uso, que es quien tiene
/// el puente a Claude. Lo que la pantalla ve es [VoiceToolStarted] y lo que
/// vaya llegando en [VoiceToolProgress].
final class VoiceToolRequested extends VoiceEvent {
  const VoiceToolRequested({
    required this.callId,
    required this.name,
    required this.arguments,
  });

  final String callId;
  final String name;

  /// Los argumentos tal como los redactó el modelo. Se guardan crudos y sin
  /// interpretar porque **cada herramienta tiene los suyos**: encargar trabajo
  /// lleva una instrucción, crear una skill lleva nombre y propósito. Quien
  /// sabe qué hacer con ellos es el caso de uso, no el traductor del socket.
  final Map<String, dynamic> arguments;
}

/// Empezó el encargo a Claude. La interfaz pasa a "trabajando".
final class VoiceToolStarted extends VoiceEvent {
  const VoiceToolStarted(this.instruction);

  /// La instrucción tal como Gemini la redactó, que no es literalmente lo que
  /// dijiste: la traduce a un encargo de programador. Se muestra porque es
  /// **lo que se va a ejecutar de verdad**, y esconderlo detrás de un
  /// "trabajando…" sería esconder justo la parte revisable.
  final String instruction;
}

/// Una acción concreta de Claude dentro del encargo: qué archivo lee, qué
/// comando corre.
///
/// Va como evento propio y no dentro del texto porque la interfaz lo pinta en
/// otro sitio —la columna «Ahora mismo»— y con otro significado: el texto es
/// lo que cuenta, esto es lo que hace.
final class VoiceToolActivity extends VoiceEvent {
  const VoiceToolActivity({
    required this.id,
    required this.description,
    required this.writes,
    required this.done,
    this.detail,
    this.output,
  });

  final String id;
  final String description;
  final bool writes;
  final bool done;
  final String? detail;
  final String? output;
}

/// Trozo de lo que Claude va contando mientras trabaja.
final class VoiceToolProgress extends VoiceEvent {
  const VoiceToolProgress(this.text);

  final String text;
}

/// Terminó el encargo. El resultado ya viajó de vuelta al modelo, que lo
/// narrará en el siguiente turno hablado.
final class VoiceToolFinished extends VoiceEvent {
  const VoiceToolFinished({
    required this.ok,
    this.turnTokens,
    this.model,
    this.contextTokens,
  });

  final bool ok;

  /// Lo que gastó el encargo y cuánta ventana lleva ocupada la sesión.
  ///
  /// Viajan hasta aquí porque **el medidor de contexto se alimenta del turno de
  /// Claude**, y hablando esos turnos los consume el caso de uso de voz: se
  /// quedaban dentro y la pantalla nunca se enteraba. El efecto era una
  /// conversación hablada entera con la ventana de contexto en «Sin dato»,
  /// mientras que escribiendo lo mismo sí se veía. `null` cuando el encargo
  /// falló o se canceló: ahí no hay medida que dar, y poner cero se leería como
  /// una sesión vacía comprobada.
  final int? turnTokens;

  /// Qué modelo corría, tal como lo dice el `init` del CLI —con su variante de
  /// ventana entre corchetes: `claude-opus-5[1m]`—.
  ///
  /// Viaja con el fin del encargo por lo mismo que los tokens: hablando, el
  /// evento que lo trae **se descartaba**, y sin modelo el medidor daba por
  /// hecha una ventana de 200k. En una sesión de un millón eso multiplicaba el
  /// porcentaje por cinco: 176k de contexto se enseñaban como 88 % cuando eran
  /// el 18 %.
  ///
  /// Es el mismo agujero que ya se tapó una vez con los tokens y se dejó a
  /// medias: se arregló el numerador y se olvidó el denominador.
  final String? model;

  final int? contextTokens;
}

/// El modelo terminó su turno.
final class VoiceTurnCompleted extends VoiceEvent {
  const VoiceTurnCompleted();
}

/// El usuario habló encima: el modelo abandona lo que estaba diciendo.
///
/// Quien reproduzca tiene que tirar lo que le quede en cola al recibir esto,
/// o se seguirá oyendo una respuesta que el modelo ya dio por muerta.
final class VoiceInterrupted extends VoiceEvent {
  const VoiceInterrupted();
}

/// La sesión se cayó o no se pudo abrir.
final class VoiceSessionFailed extends VoiceEvent {
  const VoiceSessionFailed(this.message);

  final String message;
}

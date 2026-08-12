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
    required this.instruction,
  });

  final String callId;
  final String name;
  final String instruction;
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

/// Trozo de lo que Claude va contando mientras trabaja.
final class VoiceToolProgress extends VoiceEvent {
  const VoiceToolProgress(this.text);

  final String text;
}

/// Terminó el encargo. El resultado ya viajó de vuelta al modelo, que lo
/// narrará en el siguiente turno hablado.
final class VoiceToolFinished extends VoiceEvent {
  const VoiceToolFinished({required this.ok});

  final bool ok;
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

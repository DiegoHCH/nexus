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
abstract class VoiceGateway {
  /// Abre una conversación **nueva**, sin memoria de las anteriores. Lanza si
  /// no hay llave guardada o si el servicio rechaza la conexión.
  Future<VoiceSession> connect();

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

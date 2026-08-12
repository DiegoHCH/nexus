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
  /// Abre la sesión y la deja lista para recibir audio. Lanza si no hay
  /// llave guardada o si el servicio rechaza la conexión.
  Future<VoiceSession> connect();
}

/// Una conversación abierta. Vive hasta que alguien la cierra.
abstract class VoiceSession {
  /// Todo lo que llega del servicio. Se cierra cuando la sesión termina.
  Stream<VoiceEvent> get events;

  /// Empuja un trozo de micrófono: PCM 16 bits mono a
  /// [VoiceSessionFormat.inputSampleRate].
  void sendAudio(Uint8List pcm);

  Future<void> close();
}

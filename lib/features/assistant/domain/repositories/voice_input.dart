import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';

/// La entrada de voz: el micrófono troceado en [AudioFrame]s.
abstract class VoiceInput {
  /// Formato que pide la Live API de entrada. Vive en el dominio porque no
  /// es un detalle del paquete de captura: es parte del contrato con el
  /// servicio de voz.
  static const int sampleRate = 16000;
  static const int channels = 1;

  /// `true` si el micrófono está disponible. Pedirlo puede abrir el diálogo
  /// del sistema la primera vez, y macOS lo va a negar si el usuario dice no.
  Future<bool> hasPermission();

  /// Abre el micrófono y emite un frame por cada trozo que llega. Cancelar
  /// la suscripción cierra el micrófono: no se queda abierto de fondo.
  Stream<AudioFrame> listen();
}

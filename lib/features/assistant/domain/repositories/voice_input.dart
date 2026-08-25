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

  /// Avisa de que **el audio se corta aquí**, sin que el flujo termine.
  ///
  /// Existe porque el servicio decide que terminaste de hablar **mirando el audio**:
  /// espera ver silencio. Un micrófono que sigue abierto se lo da solo —las pausas
  /// entre palabras viajan— pero uno que se cierra de golpe deja al servicio esperando
  /// un silencio que ya no llega, y el turno no cierra nunca.
  ///
  /// **No se modela cerrando el flujo**, que sería lo obvio: el flujo tiene que seguir
  /// vivo para que la sesión pueda contestar y para que volver a abrir el micrófono caiga
  /// en la misma sesión en vez de en un stream que nadie lee. Son dos cosas distintas
  /// —«no entra más audio por ahora» y «esta entrada se acabó»— y confundirlas es lo que
  /// dejó una tarde de sesiones con cero turnos.
  ///
  /// El micrófono del Mac no emite nunca: no se pausa, se calla, y callarse ya es
  /// silencio que viaja.
  Stream<void> get pausas;
}

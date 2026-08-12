import 'dart:typed_data';

/// Un trozo de audio capturado del micrófono, en el formato que la Live API
/// espera de entrada: **PCM de 16 bits, 16 kHz, mono**.
///
/// Lleva las dos cosas que se necesitan del mismo trozo y por separado:
/// [pcm] son los bytes crudos, que van tal cual por el socket cuando exista
/// la sesión de voz; [amplitude] es el volumen normalizado 0..1, que es lo
/// único que la interfaz necesita para que el orbe reaccione.
class AudioFrame {
  const AudioFrame({required this.pcm, required this.amplitude});

  final Uint8List pcm;

  /// Volumen del trozo, 0..1, calculado por RMS.
  final double amplitude;
}

import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Envuelve el altavoz de PCM crudo. Lo único que le importa a la app es
/// "suena esto seguido de lo anterior"; el resto de opciones del paquete
/// (categorías de audio de iOS, audio en segundo plano) no aplican aquí.
class PcmPlayerDataSource {
  const PcmPlayerDataSource();

  Future<void> configure({
    required int sampleRate,
    required int channels,
    required int feedThresholdFrames,
    required void Function(int remainingFrames) onNeedsMore,
  }) async {
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: channels);
    await FlutterPcmSound.setFeedThreshold(feedThresholdFrames);
    FlutterPcmSound.setFeedCallback(onNeedsMore);
    // Por defecto el paquete escribe una línea por cada `feed`, y aquí eso
    // son diez líneas por segundo de conversación.
    await FlutterPcmSound.setLogLevel(LogLevel.error);
  }

  /// Encola PCM de 16 bits little-endian.
  Future<void> feed(Uint8List pcm) {
    // `FlutterPcmSound.feed` hace `bytes.buffer.asUint8List()`, que devuelve
    // el **buffer entero** ignorando offset y longitud de la vista. Si aquí
    // entrara un `Uint8List` que es vista de un buffer mayor —y los trozos
    // que llegan del socket lo son— sonaría basura además del audio. La copia
    // exacta lo corta de raíz.
    final exact = Uint8List.fromList(pcm);
    return FlutterPcmSound.feed(PcmArrayInt16(bytes: exact.buffer.asByteData()));
  }

  /// Ceba el primer `feed`: hasta que no se le entrega algo, el paquete no
  /// empieza a pedir más.
  void prime() => FlutterPcmSound.start();

  Future<void> release() => FlutterPcmSound.release();
}

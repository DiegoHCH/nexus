import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nexus/features/assistant/data/datasources/microphone_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';

class VoiceInputImpl implements VoiceInput {
  VoiceInputImpl(this._microphone);

  final MicrophoneDataSource _microphone;

  @override
  Future<bool> hasPermission() => _microphone.hasPermission();

  @override
  Stream<AudioFrame> listen() {
    // Un StreamController propio, y no el stream del paquete a pelo, porque
    // hace falta un gancho de cierre: cuando la interfaz cancela, el
    // micrófono tiene que cerrarse de verdad. Si no, queda abierto de fondo
    // — y con la voz en marcha eso significa el micro abierto hacia Google
    // cuando nadie está hablando.
    late StreamController<AudioFrame> controller;
    StreamSubscription<Uint8List>? subscription;

    Future<void> stopMic() async {
      await subscription?.cancel();
      subscription = null;
      await _microphone.stop();
    }

    controller = StreamController<AudioFrame>(
      onListen: () async {
        try {
          final raw = await _microphone.openStream(
            sampleRate: VoiceInput.sampleRate,
            channels: VoiceInput.channels,
          );
          subscription = raw.listen(
            (chunk) => controller.add(AudioFrame(pcm: chunk, amplitude: _rms(chunk))),
            onError: controller.addError,
            onDone: controller.close,
          );
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      },
      onCancel: stopMic,
    );

    return controller.stream;
  }

  /// RMS de un buffer PCM de 16 bits con signo, little-endian, normalizado
  /// a 0..1 sobre el fondo de escala (32768).
  ///
  /// El RMS crudo de la voz se queda en valores muy bajos frente al fondo de
  /// escala, así que se aplica una raíz para que el orbe se mueva de forma
  /// perceptible en vez de quedarse casi plano.
  double _rms(Uint8List chunk) {
    if (chunk.length < 2) return 0;
    final samples = chunk.buffer.asInt16List(chunk.offsetInBytes, chunk.lengthInBytes ~/ 2);
    var sum = 0.0;
    for (final sample in samples) {
      final normalized = sample / 32768.0;
      sum += normalized * normalized;
    }
    final rms = math.sqrt(sum / samples.length);
    return math.sqrt(rms).clamp(0.0, 1.0);
  }
}

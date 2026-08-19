import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nexus/features/assistant/data/datasources/native_audio_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';

class VoiceInputImpl implements VoiceInput {
  VoiceInputImpl(this._audio);

  final NativeAudioDataSource _audio;

  @override
  Future<bool> hasPermission() => _audio.hasPermission();

  /// Un [StreamController] propio, y no el stream del canal a pelo, porque
  /// hace falta un gancho de cierre: cuando la interfaz cancela, el micrófono
  /// tiene que cerrarse de verdad. Si no, queda abierto de fondo — y con la voz
  /// en marcha eso significa el micro abierto hacia Google cuando nadie está
  /// hablando.
  ///
  /// Ya no hay vigilante de silencio aquí. Existía para detectar por ausencia
  /// de audio que el motor se había muerto en un cambio de configuración; ahora
  /// el motor nativo escucha esa notificación y se reinicia solo, así que
  /// adivinarlo desde Dart sobraba.
  @override
  Stream<AudioFrame> listen() {
    late StreamController<AudioFrame> controller;
    StreamSubscription<Uint8List>? subscription;

    Future<void> stopMic() async {
      await subscription?.cancel();
      subscription = null;
      await _audio.release();
    }

    controller = StreamController<AudioFrame>(
      onListen: () async {
        try {
          await _audio.acquire();
          subscription = _audio.frames.listen((chunk) {
            final pcm = _normalize(chunk);
            controller.add(AudioFrame(pcm: pcm, amplitude: _rms(pcm)));
          }, onError: controller.addError);
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      },
      onCancel: stopMic,
    );

    return controller.stream;
  }
}

/// Copia el trozo a un buffer propio con offset 0 y longitud par.
///
/// Sigue siendo necesario con el motor nativo: al decodificar un
/// `FlutterStandardTypedData`, Dart devuelve una **vista** sobre el buffer del
/// mensaje, con el offset que toque. Eso rompe a cualquier consumidor que lea
/// el PCM como enteros de 16 bits —`asInt16List` exige alineación a 2 bytes y
/// lanza `RangeError` con un offset impar— y además deja el frame expuesto a
/// que el siguiente mensaje pise esos bytes. Con la copia, [AudioFrame.pcm] es
/// siempre un buffer autónomo y alineado.
Uint8List _normalize(Uint8List chunk) {
  final evenLength = chunk.length - (chunk.length.isOdd ? 1 : 0);
  return Uint8List.fromList(Uint8List.sublistView(chunk, 0, evenLength));
}

/// RMS de un buffer PCM de 16 bits con signo, little-endian, normalizado
/// a 0..1 sobre el fondo de escala (32768).
///
/// El RMS crudo de la voz se queda en valores muy bajos frente al fondo de
/// escala, así que se aplica una raíz para que el orbe se mueva de forma
/// perceptible en vez de quedarse casi plano.
double _rms(Uint8List chunk) {
  if (chunk.length < 2) return 0;
  // ByteData en vez de asInt16List: getInt16 no exige alineación a 2 bytes,
  // así que esto no depende de que le llegue un buffer ya normalizado.
  final bytes = ByteData.sublistView(chunk);
  final sampleCount = bytes.lengthInBytes ~/ 2;
  var sum = 0.0;
  for (var i = 0; i < sampleCount; i++) {
    final normalized = bytes.getInt16(i * 2, Endian.little) / 32768.0;
    sum += normalized * normalized;
  }
  final rms = math.sqrt(sum / sampleCount);
  return math.sqrt(rms).clamp(0.0, 1.0);
}

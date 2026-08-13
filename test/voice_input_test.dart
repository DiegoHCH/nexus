import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/native_audio_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/voice_input_impl.dart';

/// El motor nativo, sustituido por trozos escritos a mano.
class _FakeAudio extends NativeAudioDataSource {
  _FakeAudio(this._chunks);

  final Stream<Uint8List> _chunks;
  int acquired = 0;
  int released = 0;

  @override
  Future<void> acquire() async => acquired++;

  @override
  Future<void> release() async => released++;

  @override
  Stream<Uint8List> get frames => _chunks;
}

/// Un bloque de PCM de 16 bits con todas las muestras al mismo valor.
Uint8List pcm(int sample, int samples) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, sample, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test(
    'el micrófono se pide al escuchar y se suelta al dejar de hacerlo',
    () async {
      final audio = _FakeAudio(const Stream.empty());
      final input = VoiceInputImpl(audio);

      final subscription = input.listen().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(audio.acquired, 1);

      await subscription.cancel();
      expect(audio.released, 1);
    },
  );

  // El fallo que costó una tarde: al decodificar lo que manda la plataforma,
  // Dart devuelve una **vista** sobre el buffer del mensaje, con el offset que
  // toque. Leer eso como enteros de 16 bits revienta con `RangeError` si el
  // offset es impar, y además el siguiente mensaje puede pisar esos bytes.
  test('un trozo desalineado se copia a un buffer propio', () async {
    final origen = pcm(1000, 8);
    // Una vista con offset impar es exactamente lo que llegaba del canal.
    final vista = Uint8List.sublistView(origen, 1);

    final input = VoiceInputImpl(_FakeAudio(Stream.value(vista)));
    final frame = await input.listen().first;

    expect(frame.pcm.offsetInBytes, 0);
    expect(frame.pcm.length.isEven, isTrue);
    // Copia, no vista: tocar el original no cambia lo que ya se entregó.
    origen[2] = 0xFF;
    expect(frame.pcm[1], isNot(0xFF));
  });

  test(
    'un trozo de longitud impar pierde el byte suelto, no el bloque',
    () async {
      final impar = Uint8List.fromList([1, 2, 3]);
      final input = VoiceInputImpl(_FakeAudio(Stream.value(impar)));
      final frame = await input.listen().first;

      expect(frame.pcm.length, 2);
    },
  );

  group('el volumen que mueve el orbe', () {
    Future<double> amplitudeOf(Uint8List chunk) async {
      final input = VoiceInputImpl(_FakeAudio(Stream.value(chunk)));
      return (await input.listen().first).amplitude;
    }

    test('el silencio es cero', () async {
      expect(await amplitudeOf(pcm(0, 16)), 0);
    });

    test('el fondo de escala no se pasa de uno', () async {
      final loud = await amplitudeOf(pcm(32767, 16));
      expect(loud, lessThanOrEqualTo(1.0));
      expect(loud, greaterThan(0.9));
    });

    test('más fuerte, más alto — y se nota', () async {
      final bajo = await amplitudeOf(pcm(300, 16));
      final medio = await amplitudeOf(pcm(3000, 16));
      expect(medio, greaterThan(bajo));
      // La raíz está puesta a propósito: sin ella la voz normal se queda
      // pegada al suelo y el orbe no se mueve.
      expect(bajo, greaterThan(0.05));
    });

    test('un trozo demasiado corto no rompe nada', () async {
      expect(await amplitudeOf(Uint8List.fromList([7])), 0);
    });
  });
}

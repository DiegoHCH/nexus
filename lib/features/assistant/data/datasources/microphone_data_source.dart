import 'dart:typed_data';

import 'package:record/record.dart';

/// Envuelve el paquete de grabación. Lo único que le importa a la app es
/// "dame PCM de 16 bits a 16 kHz mono"; el resto de opciones del paquete
/// (bitrate, codecs con contenedor, config de Android/iOS) no aplican aquí.
class MicrophoneDataSource {
  MicrophoneDataSource({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<Stream<Uint8List>> openStream({required int sampleRate, required int channels}) {
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
        // El micro del Mac mete bastante ruido de fondo y de teclado; que el
        // sistema lo limpie antes de que salga hacia el servicio de voz.
        noiseSuppress: true,
        echoCancel: true,
      ),
    );
  }

  Future<void> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}

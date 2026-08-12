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
        // Sin `echoCancel`, y no por gusto: activa el voice processing unit de
        // Apple, que monta un dispositivo agregado de entrada+salida. Crear ese
        // agregado dispara un AVAudioEngineConfigurationChange, AVAudioEngine se
        // para solo, y record_macos no escucha esa notificación ni reinicia el
        // motor — el micro se abre y enmudece a los 600 ms.
        //
        // `noiseSuppress` en macOS se lee pero no se aplica (el delegate solo
        // pasa echoCancel y autoGain a setVoiceProcessingEnabled), así que se
        // deja fuera en vez de fingir una limpieza que no ocurre. El ruido de
        // fondo lo absorbe el VAD del servicio de voz.
      ),
    );
  }

  Future<void> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}

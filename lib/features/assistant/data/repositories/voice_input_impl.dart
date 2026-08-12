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
  Stream<AudioFrame> listen() => _CaptureSession(_microphone).stream;
}

/// Una vuelta de micrófono abierto, con su propio [StreamController].
///
/// El controlador es propio, y no el stream del paquete a pelo, por dos
/// razones: hace falta un gancho de cierre —cuando la interfaz cancela, el
/// micrófono tiene que cerrarse de verdad, o queda abierto de fondo, y con la
/// voz en marcha eso significa el micro abierto hacia Google cuando nadie está
/// hablando— y hace falta poder reabrir la captura por debajo sin que quien
/// escucha se entere.
class _CaptureSession {
  _CaptureSession(this._microphone) {
    _controller = StreamController<AudioFrame>(onListen: _open, onCancel: _close);
  }

  /// Un tap de audio entrega bloques constantemente, también en silencio: a
  /// 16 kHz con bloques de 1024 muestras toca uno cada ~64 ms. Que no llegue
  /// ninguno en este tiempo no es que no hables, es que la captura está
  /// muerta. Se deja holgado para no confundir un tirón del sistema con eso.
  static const _stallTimeout = Duration(milliseconds: 1500);

  /// Reabrir tiene sentido cuando el motor se cayó por un cambio de
  /// configuración; si tras varios intentos sigue sin entrar audio, el
  /// problema es otro y reintentar en bucle solo lo esconde.
  static const _maxReopens = 3;

  final MicrophoneDataSource _microphone;
  late final StreamController<AudioFrame> _controller;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _stallTimer;
  int _reopens = 0;

  Stream<AudioFrame> get stream => _controller.stream;

  Future<void> _open() async {
    try {
      final raw = await _microphone.openStream(
        sampleRate: VoiceInput.sampleRate,
        channels: VoiceInput.channels,
      );
      _subscription = raw.listen(
        _onChunk,
        onError: _controller.addError,
        onDone: _controller.close,
      );
      _armStallTimer();
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
      await _controller.close();
    }
  }

  void _onChunk(Uint8List chunk) {
    _reopens = 0;
    _armStallTimer();
    final pcm = _normalize(chunk);
    _controller.add(AudioFrame(pcm: pcm, amplitude: _rms(pcm)));
  }

  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallTimeout, _onStall);
  }

  /// AVAudioEngine se para solo cuando cambia la configuración del IO unit
  /// —conectar unos AirPods a media escucha, cambiar la salida— y
  /// `record_macos` no escucha esa notificación ni lo reinicia: el tap se
  /// queda mudo para siempre sin lanzar ningún error. Como el fallo no avisa,
  /// la única forma de detectarlo desde aquí es que el audio deje de llegar.
  Future<void> _onStall() async {
    if (_controller.isClosed) return;

    if (_reopens >= _maxReopens) {
      _controller.addError(
        StateError(
          'El micrófono dejó de entregar audio y no volvió tras $_maxReopens intentos.',
        ),
      );
      await _close();
      await _controller.close();
      return;
    }

    _reopens++;
    await _closeMicrophone();
    await _open();
  }

  Future<void> _close() async {
    _stallTimer?.cancel();
    _stallTimer = null;
    await _closeMicrophone();
  }

  Future<void> _closeMicrophone() async {
    await _subscription?.cancel();
    _subscription = null;
    await _microphone.stop();
  }
}

/// Copia el trozo a un buffer propio con offset 0 y longitud par.
///
/// Lo que entrega el micrófono son vistas sobre un buffer compartido y
/// reutilizado, con `offsetInBytes` arbitrario. Eso rompe a cualquier
/// consumidor que lea el PCM como enteros de 16 bits —`asInt16List` exige
/// alineación a 2 bytes y lanza `RangeError` con un offset impar—, y además
/// deja el frame expuesto a que el paquete pise esos bytes en el siguiente
/// chunk. Con la copia, [AudioFrame.pcm] es siempre un buffer autónomo y
/// alineado.
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

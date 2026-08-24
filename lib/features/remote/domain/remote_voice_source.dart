import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';

/// El micrófono del teléfono, visto desde el Mac.
///
/// Es lo que hace que la voz remota **no toque la sesión de voz**: el Mac ya tenía un
/// puerto de entrada de audio, y esto es otra fuente para ese puerto. `lo8` decidió que
/// el audio pasa por el Mac, así que el teléfono no habla con Gemini — le presta el
/// micrófono al Mac, y el Mac hace lo que ya sabía hacer.
///
/// **Vivo mientras alguien sostiene**: [abrir] lo enciende y [cerrar] lo apaga. Entre
/// medias, cada trozo que llega por el canal entra por [entra].
class RemoteVoiceSource {
  StreamController<AudioFrame>? _salida;

  /// Si el teléfono tiene el micrófono abierto ahora mismo.
  bool get activo => _salida != null && !_salida!.isClosed;

  /// El último trozo que se descartó por llegar con el micrófono cerrado, si hubo.
  ///
  /// Se cuenta y no se ignora en silencio: trozos llegando después de cerrar es lo
  /// normal —el teléfono suelta el botón y todavía hay audio en vuelo— pero muchos
  /// seguidos significan que el cierre no llegó, y eso sí es un fallo.
  int descartados = 0;

  Stream<AudioFrame> abrir() {
    // Cerrar lo anterior antes de abrir: dos aperturas seguidas pasan cuando se pierde
    // el `stopVoice`, y dejar el primero colgado tendría dos micrófonos escribiendo en
    // la misma sesión.
    cerrar();
    descartados = 0;
    final salida = _salida = StreamController<AudioFrame>();
    return salida.stream;
  }

  void cerrar() {
    final salida = _salida;
    _salida = null;
    if (salida != null && !salida.isClosed) salida.close();
  }

  /// Un trozo de PCM del teléfono: 16 bits, 16 kHz, mono.
  void entra(Uint8List pcm) {
    final salida = _salida;
    if (salida == null || salida.isClosed) {
      descartados++;
      return;
    }
    salida.add(AudioFrame(pcm: pcm, amplitude: _volumen(pcm)));
  }

  /// El volumen del trozo, 0..1, por RMS.
  ///
  /// **Se calcula aquí y no en el teléfono**: mandarlo por el canal sería un dato más
  /// que puede desincronizarse del audio que acompaña, y el cálculo cuesta menos que
  /// escribir el campo. Es el mismo RMS que hace el micrófono del Mac, así que el orbe
  /// reacciona igual venga la voz de donde venga.
  static double _volumen(Uint8List pcm) {
    if (pcm.length < 2) return 0;
    final muestras = pcm.buffer.asInt16List(
      pcm.offsetInBytes,
      pcm.lengthInBytes ~/ 2,
    );
    var suma = 0.0;
    for (final m in muestras) {
      suma += m * m;
    }
    final rms = math.sqrt(suma / muestras.length);
    return (rms / 32768 * 4).clamp(0.0, 1.0);
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

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

  /// Lo que se oyó en esta sesión, para poder decirlo al cerrar.
  int _trozos = 0;
  double _pico = 0;

  /// Enciende el micrófono del teléfono. **Encender y tomar son dos cosas**: esto lo
  /// enciende, y [flujo] es lo que lee la sesión.
  ///
  /// Estaban juntos —`abrir` devolvía el stream— y eso las hacía chocar: `startVoice`
  /// abría, tiraba el stream a la basura, y cuando la sesión pedía audio volvía a
  /// abrir, cerrando de paso el primero. Los trozos que llegaban en medio entraban al
  /// controlador que nadie escuchaba y **se perdían en silencio** — justo los del
  /// principio de la frase, que es lo que `startVoice` existe para no perder.
  /// Si está entrando audio ahora mismo. **Distinto de que el flujo exista**: al
  /// cerrar el micrófono desde el teléfono se corta la entrada en el acto, pero el
  /// flujo sigue vivo porque la sesión del Mac todavía tiene que contestar.
  bool _entrando = false;

  /// El teléfono cerró el micrófono. **En el acto**, que es lo que se pidió: se deja de
  /// aceptar audio ya, sin esperar a que la sesión termine.
  ///
  /// Y no se cierra el flujo, que es la parte que costó entender: cerrarlo dejaría a la
  /// sesión leyendo un stream terminado justo cuando le queda lo más importante por
  /// hacer —contestar—, y volver a abrir el micrófono crearía un flujo nuevo que la
  /// sesión viva no está leyendo. Eso es exactamente lo que hacía que el segundo audio
  /// de una conversación no llegara a ninguna parte.
  void silenciar() {
    if (!_entrando) return;
    _entrando = false;
    debugPrint(
      'voz · el teléfono cerró el micrófono · $_trozos trozos, '
      'pico ${_pico.toStringAsFixed(2)}'
      '${_pico < 0.02 ? ' — eso es silencio, el micrófono del teléfono no cogió nada' : ''}',
    );
  }

  void abrir() {
    // **Si ya está abierto, se deja.** Ahora que soltar el botón no derriba la sesión,
    // volver a sostener cae sobre una sesión viva que está leyendo *este* stream:
    // crear otro la dejaría escuchando el de antes —cerrado— mientras los trozos
    // nuevos entran a un controlador que nadie lee. Silencio, y de los que no se ven.
    // Si el flujo sigue vivo, se vuelve a dejar entrar audio y ya está: hay una sesión
    // leyéndolo, y darle otro la dejaría escuchando el de antes.
    if (activo) {
      _entrando = true;
      _trozos = 0;
      _pico = 0;
      return;
    }
    // Y si no, se cierra lo que hubiera antes de abrir: un controlador viejo colgado
    // sería un segundo micrófono escribiendo en la misma sesión.
    cerrar();
    descartados = 0;
    _trozos = 0;
    _pico = 0;
    _entrando = true;
    _salida = StreamController<AudioFrame>();
  }

  /// Lo que lee la sesión. **No reabre**: si nadie lo encendió, no hay nada que dar.
  Stream<AudioFrame>? get flujo => _salida?.stream;

  void cerrar() {
    final salida = _salida;
    _salida = null;
    _entrando = false;
    if (salida == null || salida.isClosed) return;
    salida.close();
  }

  /// Un trozo de PCM del teléfono: 16 bits, 16 kHz, mono.
  void entra(Uint8List pcm) {
    final salida = _salida;
    // Con el micrófono cerrado no entra nada, y **se cuenta igual**: unos pocos son la
    // cola normal —se toca cerrar y queda audio en vuelo— y muchos seguidos significan
    // que el cierre no llegó. Es el volumen lo que los separa, así que no contarlos
    // aquí borraría justo la señal.
    if (!_entrando || salida == null || salida.isClosed) {
      descartados++;
      // **Y se dice**, que es lo que este contador prometía y no cumplía: existía
      // para distinguir «unos pocos en vuelo al soltar» de «el cierre no llegó», y
      // sin imprimirlo nunca las dos cosas se veían igual — es decir, no se veían.
      // El primero siempre, y luego de diez en diez: el primero es el que sitúa el
      // momento, y el resto sobra si son los tres de la cola del botón.
      if (descartados == 1 || descartados % 10 == 0) {
        debugPrint(
          'voz · trozo del teléfono descartado, el micrófono está cerrado '
          '($descartados)',
        );
      }
      return;
    }
    final volumen = _volumen(pcm);
    _trozos++;
    if (volumen > _pico) _pico = volumen;
    salida.add(AudioFrame(pcm: pcm, amplitude: volumen));
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

import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// El altavoz del teléfono, para la respuesta que baja del Mac.
///
/// **El mismo formato en que Gemini la canta** —16 bits, 24 kHz, mono— y no uno
/// cualquiera: lo que viaja son muestras ya sintetizadas en el servidor, así que
/// convertirlas aquí sería estropear un audio que ya está bien. Es también por qué la
/// voz suena igual la reproduzca quien la reproduzca: nadie por este camino la elige.
///
/// Detrás de una interfaz por lo mismo que el micrófono: lo que hay que poder ejercitar
/// es **cuándo se abre, qué se le da y cuándo se dice que terminó**, y eso no necesita
/// un altavoz de verdad.
abstract class Altavoz {
  /// Prepara el dispositivo. Idempotente.
  Future<void> preparar();

  /// Encola muestras. No bloquea.
  Future<void> encolar(Uint8List pcm);

  /// Tira lo que quede por sonar. Es lo que hace falta cuando alguien interrumpe: lo
  /// pendiente deja de ser válido, y esperar a que suene es contestar a una pregunta
  /// que ya nadie hizo.
  Future<void> tirar();

  /// Avisa cuando la cola se vació, que es lo que el Mac necesita saber para poder
  /// cerrar la sesión sin cortar la última palabra.
  set alVaciarse(void Function()? alVaciarse);

  Future<void> soltar();
}

class AltavozDelMovil implements Altavoz {
  /// 24 kHz mono: lo que dice el formato de salida de la sesión de voz.
  static const _frecuencia = 24000;

  var _preparado = false;

  @override
  void Function()? alVaciarse;

  @override
  Future<void> preparar() async {
    if (_preparado) return;
    _preparado = true;
    await FlutterPcmSound.setup(sampleRate: _frecuencia, channelCount: 1);
    // El aviso salta cuando la cola baja del umbral **y** cuando se vacía del todo. Con
    // el umbral en cero solo interesa lo segundo: aquí no se rellena bajo demanda —los
    // trozos llegan cuando el Mac los manda— así que lo único que hay que detectar es
    // el final.
    await FlutterPcmSound.setFeedThreshold(0);
    FlutterPcmSound.setFeedCallback((restantes) {
      if (restantes == 0) alVaciarse?.call();
    });
  }

  @override
  Future<void> encolar(Uint8List pcm) async {
    await preparar();
    // Las muestras vienen como bytes del canal y el paquete las quiere como enteros de
    // 16 bits. Es la misma memoria vista de otra forma, no una conversión: copiarla
    // sería pagar por cada trozo de una respuesta entera.
    await FlutterPcmSound.feed(
      PcmArrayInt16(bytes: pcm.buffer.asByteData(pcm.offsetInBytes)),
    );
    FlutterPcmSound.start();
  }

  @override
  Future<void> tirar() async {
    if (!_preparado) return;
    // El paquete no tiene «vaciar la cola», así que se suelta y se vuelve a preparar en
    // el siguiente trozo. Es brusco, y es exactamente lo que se quiere: interrumpir es
    // cortar ya, no esperar a que termine lo que queda.
    _preparado = false;
    await FlutterPcmSound.release();
  }

  @override
  Future<void> soltar() async {
    FlutterPcmSound.setFeedCallback(null);
    if (!_preparado) return;
    _preparado = false;
    await FlutterPcmSound.release();
  }
}

import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';

/// Los altavoces del teléfono, vistos desde el Mac.
///
/// El gemelo de `RemoteVoiceSource`: aquel es otra **fuente** para el puerto de entrada
/// que el Mac ya tenía, y esto es otro **destino** para el de salida. Por eso la sesión
/// de voz no se toca — sigue encolando PCM en un `AudioOutput` y ya está.
///
/// No sabe de transporte: recibe y entrega bytes, igual que el altavoz del Mac. Quien
/// los mete en el canal es el cableado.
class RemoteAudioSink implements AudioOutput {
  RemoteAudioSink({required this.mandar, required this.tirar});

  /// Un trozo de PCM hacia el teléfono.
  final void Function(Uint8List pcm) mandar;

  /// «Deja de sonar y tira lo que te quede.» Hace falta porque una conversación por voz
  /// se interrumpe: lo que quedaba por sonar deja de ser válido, y esperar a que termine
  /// sería contestar a una pregunta que ya nadie hizo.
  final void Function() tirar;

  /// Si hay respuesta sonando en el teléfono ahora mismo.
  ///
  /// **Lo apaga el teléfono, no un reloj de aquí.** Es la decisión que se tomó: quien
  /// reproduce dice cuándo terminó. Estimarlo por bytes y ritmo sería adivinar el jitter
  /// de la red, y adivinar aquí se oye — de menos, corta la última palabra; de más, deja
  /// la sesión abierta escuchando una habitación.
  bool _sonando = false;

  /// El usuario calló la respuesta, o el teléfono se fue. En los dos casos deja de salir
  /// audio, y en los dos el texto sigue: callar no cancela el turno.
  bool _mudo = false;

  /// Lo encolado en esta respuesta, para que [pending] tenga algo que devolver mientras
  /// el teléfono no dice que terminó. 24 kHz mono de 16 bits son 48.000 bytes por
  /// segundo.
  var _encolado = Duration.zero;

  @override
  Future<void> start() async {
    _mudo = false;
    _sonando = false;
    _encolado = Duration.zero;
  }

  @override
  void enqueue(Uint8List pcm) {
    if (_mudo) return;
    _sonando = true;
    _encolado += Duration(microseconds: pcm.lengthInBytes * 1000000 ~/ 48000);
    mandar(pcm);
  }

  /// Se dice siempre, también sin nada encolado aquí: el teléfono puede tener cola de
  /// la que en el Mac ya no se lleva cuenta.
  @override
  Future<void> discard() async {
    _sonando = false;
    _encolado = Duration.zero;
    tirar();
  }

  /// Cuánto queda por sonar.
  ///
  /// Devuelve lo encolado **entero** mientras el teléfono no diga que terminó, y no una
  /// cuenta atrás. Quien pregunta esto lo usa para no cerrar la sesión a media palabra,
  /// así que pasarse solo cuesta esperar otra vuelta —vuelve a preguntar— mientras que
  /// quedarse corto corta la frase. La respuesta verdadera la da [terminoDeSonar].
  @override
  Future<Duration> pending() async => _sonando ? _encolado : Duration.zero;

  @override
  Future<void> stop() async {
    _sonando = false;
    _encolado = Duration.zero;
    _mudo = false;
  }

  /// El teléfono terminó de reproducir.
  void terminoDeSonar() {
    _sonando = false;
    _encolado = Duration.zero;
  }

  /// El usuario calló la respuesta y sigue leyendo.
  ///
  /// Se deja de mandar audio —no tiene sentido gastar el canal en algo que nadie va a
  /// oír— y se le dice al teléfono que tire lo que tenga en cola. **El turno sigue**: el
  /// texto es lo que se estaba leyendo, y es lo que se queda.
  void callar() {
    _mudo = true;
    _sonando = false;
    _encolado = Duration.zero;
    tirar();
  }

  /// El teléfono se fue a media respuesta.
  ///
  /// **La voz se corta y no sigue por ningún sitio**, y en particular no se termina por
  /// los altavoces del Mac: se le estaba diciendo a quien no está delante del Mac, y
  /// soltarla en una habitación vacía es peor que callarse. El texto sigue llegando, que
  /// es lo que se puede leer al volver.
  ///
  /// Y hace falta apagar `_sonando` aquí: sin esto la sesión se quedaría esperando para
  /// siempre un «ya terminé» de un teléfono que no está.
  void seFue() {
    if (_sonando) {
      debugPrint(
        'voz · el teléfono se fue con respuesta sonando · se corta, y el texto sigue',
      );
    }
    _mudo = true;
    _sonando = false;
    _encolado = Duration.zero;
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/la_sesion_de_puerta.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

// La puerta: una sesión de voz **sin carpeta**, que es toda su rareza.
//
// El resto de la app abre voz dentro de una conversación, que tiene carpeta,
// cuenta, modelo y permisos colgando. Aquí no hay nada de eso todavía, porque
// justamente lo que se pregunta es dónde. Sin herramientas, sin puente a Claude
// y sin leer nada: lo único que sale de la máquina es tu voz y los nombres.

const _nexus = PairedFolder(
  path: '/Users/alguien/personal/nexus',
  modality: FolderModality.voice,
);
const _tienda = PairedFolder(
  path: '/Users/alguien/trabajo/front-mobile-b2c',
  modality: FolderModality.textOnly,
);

class _Sesion implements VoiceSession {
  final _eventos = StreamController<VoiceEvent>.broadcast();
  final notas = <String>[];
  final enviado = <Uint8List>[];
  var cerrada = false;

  @override
  Stream<VoiceEvent> get events => _eventos.stream;

  @override
  void sendSystemNote(String text) => notas.add(text);

  @override
  void sendAudio(Uint8List pcm) => enviado.add(pcm);

  final resultados = <String>[];

  @override
  void sendToolResult({
    required String callId,
    required String name,
    required String result,
  }) => resultados.add(result);

  @override
  Future<void> close() async => cerrada = true;

  void emite(VoiceEvent evento) => _eventos.add(evento);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Servicio implements VoiceGateway {
  _Servicio(this.sesion);
  final _Sesion sesion;
  var conexiones = 0;

  /// Qué se mira justo al conectar. Sirve para fijar un **orden**, que es de lo
  /// que aquí depende que el audio suene limpio.
  bool Function()? alConectar;
  bool? micEscuchandoAlConectar;

  ComoSePresentaLaPuerta? comoPuerta;

  @override
  Future<VoiceSession> connect({ComoSePresentaLaPuerta? comoPuerta}) async {
    conexiones++;
    micEscuchandoAlConectar = alConectar?.call();
    this.comoPuerta = comoPuerta;
    return sesion;
  }

  @override
  Future<VoiceSession> resume() => connect();
}

class _Microfono implements VoiceInput {
  final _frames = StreamController<AudioFrame>.broadcast();
  var soltado = false;
  var escuchando = false;

  @override
  Stream<AudioFrame> listen() =>
      (escuchando = true) ? _laFuente() : _laFuente();

  Stream<AudioFrame> _laFuente() => _frames.stream.transform(
    StreamTransformer.fromHandlers(
      handleDone: (sink) {
        soltado = true;
        sink.close();
      },
    ),
  );

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<void> get pausas => const Stream<void>.empty();

  void habla() =>
      _frames.add(AudioFrame(pcm: Uint8List.fromList([1, 2]), amplitude: 0.5));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Altavoz implements AudioOutput {
  final sonado = <Uint8List>[];
  var arrancado = false;
  var parado = false;

  @override
  Future<void> start() async => arrancado = true;
  @override
  void enqueue(Uint8List pcm) => sonado.add(pcm);
  @override
  Future<void> stop() async => parado = true;
  var descartes = 0;

  @override
  Future<void> discard() async => descartes++;
  @override
  Future<Duration> pending() async => Duration.zero;
}

void main() {
  late _Sesion sesion;
  late _Servicio servicio;
  late _Microfono microfono;
  late _Altavoz altavoz;

  setUp(() {
    sesion = _Sesion();
    microfono = _Microfono();
    servicio = _Servicio(sesion)..alConectar = () => microfono.escuchando;
    altavoz = _Altavoz();
  });

  Stream<LoQuePasaEnLaPuerta> abrir() =>
      LaSesionDePuerta(microfono, servicio, altavoz).abrir(
        saludo: 'Buenos días, Argonauta. ¿En dónde vamos a trabajar hoy?',
        carpetas: const [_nexus, _tienda],
      );

  Future<void> vueltas([int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // 🔴 **El saludo va en su instrucción de sistema, no como nota.** Una nota se
  // manda como turno de usuario, y el modelo lo delataba en pantalla:
  // «Argonauta, me pidieron que dijera eso exactamente».
  test('se presenta con su saludo y sus carpetas al conectar', () async {
    final sub = abrir().listen((_) {});
    addTearDown(sub.cancel);
    await vueltas();

    expect(servicio.comoPuerta, isNotNull, reason: 'no es una conversación');
    expect(servicio.comoPuerta!.saludo, contains('Buenos días, Argonauta'));
    expect(servicio.comoPuerta!.carpetas, contains('nexus'));
    expect(
      servicio.comoPuerta!.carpetas,
      contains('front-mobile-b2c'),
      reason: 'las de solo texto también se nombran: decidido a la vista',
    );
  });

  test('y al estar lista solo se le da la señal de arranque', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceSessionReady());
    await vueltas();

    expect(sesion.notas, ['(inicio)']);
    expect(vistos, contains(isA<LaPuertaEstaLista>()));
  });

  // 🔴 **Así es como dice dónde**, y no por la transcripción: medido en vivo, el
  // modelo oía «nexus» y de lo dicho llegaba una sola trama en toda la sesión.
  test('la carpeta llega por la herramienta, y se valida aquí', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(
      const VoiceToolRequested(
        callId: 'c1',
        name: 'elegirCarpeta',
        arguments: {'carpeta': 'nexus', 'tarea': 'mira el último PR'},
      ),
    );
    await vueltas();

    // 🔴 **Todavía no se abre nada.** Se le contesta a la herramienta y se le
    // deja decir «vale, abro nexus»; la interfaz cambia cuando acaba de hablar.
    // Al revés —abriendo ya, con la frase sonando encima— la pantalla se te
    // venía a media palabra. Reportado mirándolo.
    expect(vistos.whereType<LaPuertaEligio>(), isEmpty);
    expect(sesion.resultados.single, contains('nexus'));
    expect(sesion.cerrada, isFalse);
  });

  test('y al acabar de despedirse abre la carpeta y se cierra', () async {
    final sub = abrir().listen((_) {});
    addTearDown(sub.cancel);
    await vueltas();

    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub2 = abrir().listen(vistos.add);
    addTearDown(sub2.cancel);
    await vueltas();

    sesion.emite(
      const VoiceToolRequested(
        callId: 'c1',
        name: 'elegirCarpeta',
        arguments: {'carpeta': 'nexus', 'tarea': 'mira el último PR'},
      ),
    );
    await vueltas();
    expect(vistos.whereType<LaPuertaEligio>(), isEmpty);

    sesion.emite(const VoiceTurnCompleted());
    await vueltas();

    final elegida = vistos.whereType<LaPuertaEligio>().single;
    expect(elegida.carpeta, _nexus);
    expect(elegida.tarea, 'mira el último PR');
    expect(sesion.cerrada, isTrue);
    expect(altavoz.parado, isTrue);
  });

  // Un turno que acaba **sin** haber elegido nada no cierra nada: la puerta
  // sigue preguntando.
  test('un turno cualquiera no la cierra', () async {
    final sub = abrir().listen((_) {});
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceTurnCompleted());
    await vueltas();

    expect(sesion.cerrada, isFalse);
  });

  test('una carpeta que no existe no abre nada: se le dice y sigue', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(
      const VoiceToolRequested(
        callId: 'c1',
        name: 'elegirCarpeta',
        arguments: {'carpeta': 'la de contabilidad'},
      ),
    );
    await vueltas();

    expect(vistos.whereType<LaPuertaEligio>(), isEmpty);
    expect(sesion.cerrada, isFalse);
    expect(sesion.resultados.single, contains('No hay ninguna carpeta'));
  });

  // Lo entrecortado: sin tirar lo que ya estaba en cola, lo viejo se sigue
  // oyendo pisado con lo nuevo. Reportado escuchándolo.
  test('al ser interrumpida se tira el audio que quedaba', () async {
    final sub = abrir().listen((_) {});
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceInterrupted());
    await vueltas();

    expect(altavoz.descartes, 1);
  });

  test('lo que responde suena, y su texto sale como subtítulo', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(VoiceReplyAudio(Uint8List.fromList([9, 9])));
    sesion.emite(const VoiceReplyTranscript('Buenos días'));
    await vueltas();

    expect(altavoz.arrancado, isTrue);
    expect(altavoz.sonado, hasLength(1));
    expect(vistos.whereType<LaPuertaDice>().single.texto, 'Buenos días');
  });

  // 🔴 En cuanto se oye la carpeta, no al final del turno: el nombre aparece
  // entero al decirlo, y esperar añadiría un silencio justo después de que ya
  // se sabe la respuesta.
  // Por transcripción también vale, y **por el mismo camino**: se guarda y se
  // le deja despedirse. Antes esta vía abría de golpe y la pantalla cambiaba
  // sin que dijera nada — reportado escuchándolo.
  test('al oír la carpeta la guarda, y no abre hasta despedirse', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceUserTranscript('trabajemos '));
    sesion.emite(const VoiceUserTranscript('en nexus'));
    await vueltas();

    expect(vistos.whereType<LaPuertaEligio>(), isEmpty);
    expect(sesion.cerrada, isFalse);

    sesion.emite(const VoiceTurnCompleted());
    await vueltas();

    final elegida = vistos.whereType<LaPuertaEligio>().single;
    expect(elegida.carpeta, _nexus);
    expect(elegida.tarea, isEmpty);
    expect(sesion.cerrada, isTrue, reason: 'la puerta se cierra al pasar');
    expect(altavoz.parado, isTrue);
  });

  test('y lo que dijiste además viaja con ella', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceUserTranscript('en nexus, mira el último PR'));
    sesion.emite(const VoiceTurnCompleted());
    await vueltas();

    expect(
      vistos.whereType<LaPuertaEligio>().single.tarea,
      contains('el último PR'),
    );
  });

  test('lo que no nombra ninguna carpeta no elige nada', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceUserTranscript('buenos días, qué tal'));
    await vueltas();

    expect(vistos.whereType<LaPuertaEligio>(), isEmpty);
    expect(sesion.cerrada, isFalse, reason: 'sigue esperando una respuesta');
  });

  // Nunca se queda callada: un servicio que no contesta se ve igual que una app
  // colgada al arrancar, y eso manda a buscar el problema al sitio equivocado.
  test('si el servicio se cae, se dice', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceSessionFailed('se cortó'));
    await vueltas();

    expect(vistos.whereType<LaPuertaSeCayo>().single.motivo, 'se cortó');
    expect(sesion.cerrada, isTrue);
  });

  // 🔴 La lección de `LaSalidaQueSeCancela`, aplicada: con un `async*` esto no
  // pasaría —cancelar no ejecuta sus `finally`— y el micrófono se quedaría
  // abierto cada vez que alguien cierra la pantalla.
  test('cancelar cierra la sesión y para el altavoz', () async {
    final sub = abrir().listen((_) {});
    await vueltas();

    await sub.cancel();
    await vueltas();

    expect(sesion.cerrada, isTrue);
    expect(altavoz.parado, isTrue);
  });

  test('el micro va a la sesión mientras dure', () async {
    final sub = abrir().listen((_) {});
    addTearDown(sub.cancel);
    await vueltas();

    microfono.habla();
    await vueltas();

    expect(sesion.enviado, hasLength(1));
  });

  // 🔴 **El micro se engancha antes de conectar, y no es un detalle de estilo.**
  // El motor de audio nativo monta un grafo distinto según quién lo tenga
  // cogido: enganchando el micrófono después de que empiece a sonar la
  // respuesta, lo remonta a media reproducción. Se oyó — el saludo entrecortado
  // y una conversación normal limpia, porque ahí hablas tú primero y el grafo ya
  // está montado cuando llega el audio.
  test('el micro ya está enganchado cuando se conecta', () async {
    final sub = abrir().listen((_) {});
    addTearDown(sub.cancel);
    await vueltas();

    expect(altavoz.arrancado, isTrue);
    expect(servicio.micEscuchandoAlConectar, isTrue);
  });

  // 🔴 **Media duplex mientras habla**, y está medido: con el micro abierto, el
  // servicio tomaba el ruido de la habitación por una interrupción y cortaba el
  // saludo a media frase. Se transcribió una conversación ajena —«sí, porque el
  // otro muchacho fue el que hizo el servicio en el día»— y con ella se fue el
  // «vale, abro nexus», que ni llegó a sonar.
  test('mientras habla, el micro no se le manda', () async {
    final sub = abrir().listen((_) {});
    addTearDown(sub.cancel);
    await vueltas();

    microfono.habla();
    await vueltas();
    expect(sesion.enviado, hasLength(1), reason: 'callada, sí se le manda');

    sesion.emite(VoiceReplyAudio(Uint8List.fromList([1])));
    await vueltas();
    microfono.habla();
    microfono.habla();
    await vueltas();

    expect(
      sesion.enviado,
      hasLength(1),
      reason: 'hablando ella, el ruido de la habitación no la interrumpe',
    );

    sesion.emite(const VoiceTurnCompleted());
    await vueltas();
    microfono.habla();
    await vueltas();

    expect(sesion.enviado, hasLength(2), reason: 'y al callarse, vuelve');
  });
}

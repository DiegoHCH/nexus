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

  @override
  Future<VoiceSession> connect() async {
    conexiones++;
    return sesion;
  }

  @override
  Future<VoiceSession> resume() => connect();
}

class _Microfono implements VoiceInput {
  final _frames = StreamController<AudioFrame>.broadcast();
  var soltado = false;

  @override
  Stream<AudioFrame> listen() => _frames.stream.transform(
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
  @override
  Future<void> discard() async {}
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
    servicio = _Servicio(sesion);
    microfono = _Microfono();
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

  test(
    'al estar lista se le pide el saludo, con las carpetas que hay',
    () async {
      final vistos = <LoQuePasaEnLaPuerta>[];
      final sub = abrir().listen(vistos.add);
      addTearDown(sub.cancel);
      await vueltas();

      sesion.emite(const VoiceSessionReady());
      await vueltas();

      expect(sesion.notas, hasLength(1));
      expect(sesion.notas.single, contains('Buenos días, Argonauta'));
      expect(sesion.notas.single, contains('nexus'));
      expect(
        sesion.notas.single,
        contains('front-mobile-b2c'),
        reason: 'las de solo texto también se nombran: decidido a la vista',
      );
      expect(vistos, contains(isA<LaPuertaEstaLista>()));
    },
  );

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
  test('al oír la carpeta elige, cierra la sesión y suelta el micro', () async {
    final vistos = <LoQuePasaEnLaPuerta>[];
    final sub = abrir().listen(vistos.add);
    addTearDown(sub.cancel);
    await vueltas();

    sesion.emite(const VoiceUserTranscript('trabajemos '));
    sesion.emite(const VoiceUserTranscript('en nexus'));
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
}

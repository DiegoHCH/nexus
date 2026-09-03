import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/native_audio_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/audio_output_impl.dart';

/// Quién pide el motor, y con qué se monta.
///
/// 🔴 **Un aviso de agenda solo habla, y encendía el micrófono.** `acquire()` no
/// preguntaba a qué venía, así que decir una frase montaba la captura, el
/// cancelador de eco y el dispositivo agregado — con el indicador naranja de
/// macOS puesto toda la frase.
///
/// Lo que se comprueba aquí es el reparto: qué se le pide al nativo y cuándo,
/// que es donde está la decisión. Lo que hace el nativo con ella se prueba en
/// `RunnerTests.swift`, que corre en su propio trabajo del CI.
void main() {
  late List<MethodCall> llamadas;
  late NativeAudioDataSource audio;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    llamadas = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nexus/audio'), (
          call,
        ) async {
          llamadas.add(call);
          return null;
        });
    audio = NativeAudioDataSource();
  });

  List<String> arranques() => [
    for (final llamada in llamadas)
      if (llamada.method == 'start')
        (llamada.arguments as Map)['para'] as String,
  ];

  test('un aviso que solo habla no pide el micrófono', () async {
    await AudioOutputImpl(audio, para: ParaQue.hablar).start();

    expect(arranques(), ['hablar']);
  });

  test('una conversación sí lo pide', () async {
    await AudioOutputImpl(audio, para: ParaQue.conversar).start();

    expect(arranques(), ['conversar']);
  });

  // 🔴 El orden importa y no es el intuitivo: en `hold_voice_conversation` el
  // altavoz se pide **antes** que el micrófono. Si el altavoz de una
  // conversación dijera «hablar», el micrófono llegaría después y obligaría a
  // rehacer el grafo entero — 1,3 s del dispositivo agregado en cada
  // conversación.
  test(
    'el altavoz de una conversación no monta un grafo que haya que rehacer',
    () async {
      await AudioOutputImpl(audio, para: ParaQue.conversar).start();
      await audio.acquire();

      expect(arranques(), [
        'conversar',
      ], reason: 'el segundo no monta nada: lo que hace falta no cambió');
    },
  );

  test(
    'con un aviso sonando, abrir la voz sube el motor a conversar',
    () async {
      await AudioOutputImpl(audio, para: ParaQue.hablar).start();
      await audio.acquire();

      expect(arranques(), ['hablar', 'conversar']);
    },
  );

  test('soltar la conversación con el aviso dentro no baja el grafo', () async {
    await AudioOutputImpl(audio, para: ParaQue.hablar).start();
    await audio.acquire();
    await audio.release();

    expect(
      llamadas.map((l) => l.method),
      isNot(contains('stop')),
      reason:
          'rehacer el grafo con audio en vuelo se oye: sale más barato quedarse '
          'con el de más hasta que lo suelte el último',
    );
  });

  test('el motor se para cuando lo suelta el último', () async {
    final altavoz = AudioOutputImpl(audio, para: ParaQue.hablar);
    await altavoz.start();
    await audio.acquire();
    await audio.release();
    await altavoz.stop();

    expect(llamadas.map((l) => l.method), contains('stop'));
  });

  test('soltar de más no para nada', () async {
    await audio.release();
    await audio.release(para: ParaQue.hablar);

    expect(llamadas.map((l) => l.method), isNot(contains('stop')));
  });

  // 🔴 **Lo que de verdad importa de todo esto: el aviso tiene que sonar.**
  //
  // El cambio a «solo salida» tocó el camino del aviso de agenda, y el motor
  // nativo guardaba `enqueue` con `listening` —que sin micrófono es siempre
  // falso—. Si eso no se hubiera separado de «hay sesión abierta», la agenda
  // habría dejado de hablar en silencio: el motor arranca, el TTS contesta, y
  // no sale nada por el altavoz.
  group('el aviso de agenda suena, y sin micrófono', () {
    test('pidiendo solo salida se puede reproducir', () async {
      final altavoz = AudioOutputImpl(audio, para: ParaQue.hablar);
      await altavoz.start();

      altavoz.enqueue(Uint8List.fromList([1, 2, 3, 4]));

      expect(arranques(), ['hablar']);
      expect(
        llamadas.where((l) => l.method == 'play'),
        hasLength(1),
        reason:
            'si esto no llega, la agenda deja de hablar sin decir nada: el '
            'motor arranca, el TTS contesta y no sale nada por el altavoz',
      );
    });

    test(
      'y se sabe cuánto queda por sonar, que es lo que espera el aviso',
      () async {
        final altavoz = AudioOutputImpl(audio, para: ParaQue.hablar);
        await altavoz.start();

        await altavoz.pending();

        expect(
          llamadas.map((l) => l.method),
          contains('pendingPlaybackMs'),
          reason:
              'el aviso espera a que termine la frase antes de soltar el '
              'altavoz; sin esta medida lo soltaría a media palabra',
        );
      },
    );

    test('antes de arrancar no se reproduce nada', () {
      AudioOutputImpl(
        audio,
        para: ParaQue.hablar,
      ).enqueue(Uint8List.fromList([1]));

      expect(llamadas, isEmpty);
    });
  });
}

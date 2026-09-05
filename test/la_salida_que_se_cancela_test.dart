import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/la_salida_que_se_cancela.dart';

// La trampa de Dart que costó 3,92 GB en un día, fijada en una prueba.
//
// Cancelar un `async*` no ejecuta sus `finally`. Aquí se mide lo uno y lo otro:
// que el generador desnudo no se entera, y que envuelto sí.

Stream<int> _generador(
  StreamController<int> aparcado,
  void Function() alFinal,
) async* {
  yield 1;
  try {
    yield* aparcado.stream;
  } finally {
    alFinal();
  }
}

Future<void> _vueltas([int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // 🔴 La medición que justifica todo el archivo. Si algún día Dart cambia esto,
  // esta prueba falla y hay que celebrarlo, no arreglarla a la ligera.
  test('un async* desnudo NO ejecuta su finally al cancelar', () async {
    final aparcado = StreamController<int>();
    // **Sin esperar el cierre**, y eso ya es parte de la medición: cerrarlo
    // espera al suscriptor que el generador abandonado se llevó consigo, así
    // que un `addTearDown(aparcado.close)` cuelga la prueba los 30 s del tope.
    addTearDown(() => unawaited(aparcado.close()));
    var corrio = false;

    late StreamSubscription<int> sub;
    sub = _generador(aparcado, () => corrio = true).listen((_) {
      unawaited(sub.cancel());
    });
    await _vueltas();

    expect(
      corrio,
      isFalse,
      reason: 'si esto pasa a ser cierto, sobra el envoltorio',
    );
  });

  test('envuelto, cancelar sí dispara el remate', () async {
    final aparcado = StreamController<int>();
    addTearDown(() => unawaited(aparcado.close()));
    var remates = 0;

    final salida = LaSalidaQueSeCancela.de(
      () => _generador(aparcado, () {}),
      alCancelar: () async => remates++,
    );

    late StreamSubscription<int> sub;
    sub = salida.listen((_) => unawaited(sub.cancel()));
    await _vueltas();

    expect(remates, 1);
  });

  test('la fuente no arranca hasta que alguien escucha', () async {
    var arranques = 0;
    final salida = LaSalidaQueSeCancela.de(() {
      arranques++;
      return const Stream<int>.empty();
    }, alCancelar: () async {});

    await _vueltas(3);
    expect(
      arranques,
      0,
      reason: 'lanzar el proceso sin oyente es lanzarlo por nada',
    );

    await salida.drain<void>();
    expect(arranques, 1);
  });

  test('lo que emite la fuente llega entero, y el final también', () async {
    final salida = LaSalidaQueSeCancela.de(
      () => Stream<int>.fromIterable([1, 2, 3]),
      alCancelar: () async {},
    );

    expect(await salida.toList(), [1, 2, 3]);
  });

  test('un error de la fuente llega como error, no como silencio', () async {
    final salida = LaSalidaQueSeCancela.de(
      () => Stream<int>.error(StateError('se cayó')),
      alCancelar: () async {},
    );

    await expectLater(salida, emitsError(isA<StateError>()));
  });
}

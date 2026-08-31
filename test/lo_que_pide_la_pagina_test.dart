import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/platform/lo_que_pide_la_pagina.dart';

/// Lo que las páginas del visor le piden a la app.
///
/// 🔴 Esto existe porque `setMethodCallHandler` es **exclusivo por canal**. Lo
/// tenía puesto el controlador de las pruebas e2e para su botón de parar, así
/// que la ventana de actividad no podía tener el suyo: ponerlo se lo quitaba a
/// la otra, en silencio y sin error. Es el modo de falla que este despachador
/// existe para cerrar, y por eso la primera prueba es que **convivan**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> comoSiPidieran(String que, {String ruta = ''}) {
    final canal = LoQuePideLaPagina.canal;
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          canal.name,
          canal.codec.encodeMethodCall(
            MethodCall('desdeLaPagina', {'que': que, 'ruta': ruta}),
          ),
          (_) {},
        );
  }

  tearDown(LoQuePideLaPagina.olvidarTodo);

  test(
    'dos ventanas piden cosas distintas y cada una recibe la suya',
    () async {
      final oido = <String>[];
      LoQuePideLaPagina.escuchar('parar', (_) => oido.add('e2e'));
      LoQuePideLaPagina.escuchar('detener', (_) => oido.add('actividad'));

      await comoSiPidieran('parar');
      await comoSiPidieran('detener');

      expect(oido, ['e2e', 'actividad']);
    },
  );

  test('la ruta llega entera: es la que dice sobre cuál', () async {
    String? recibida;
    LoQuePideLaPagina.escuchar('detener', (ruta) => recibida = ruta);

    await comoSiPidieran('detener', ruta: '/c1');

    expect(recibida, '/c1');
  });

  test('lo que nadie atiende no revienta', () async {
    LoQuePideLaPagina.escuchar('parar', (_) {});

    // Una página abierta desde ayer puede pedir algo que ya no atiende nadie.
    await expectLater(comoSiPidieran('vete-a-saber'), completes);
  });

  test('quien olvida deja de recibir', () async {
    var veces = 0;
    LoQuePideLaPagina.escuchar('parar', (_) => veces++);
    await comoSiPidieran('parar');

    LoQuePideLaPagina.olvidar('parar');
    await comoSiPidieran('parar');

    expect(veces, 1);
  });
}

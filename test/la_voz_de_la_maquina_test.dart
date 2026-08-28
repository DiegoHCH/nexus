import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/voz_de_la_maquina_impl.dart';

/// La fase 1 de la voz propia: oír y hablar sin salir del Mac.
///
/// Lo que de verdad decide —si el reconocimiento del sistema entiende un encargo
/// técnico— **no se puede probar aquí**: hace falta un micrófono y una persona
/// diciendo «corre el flow de login en el simulador». Lo que sí se puede
/// asegurar es lo otro: que cuando funcione, funcione **sin salir a la red**, y
/// que cuando no pueda, lo diga en vez de degradar en silencio.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final llamadas = <MethodCall>[];
  Object? respuesta;
  Object? lanza;

  setUp(() {
    llamadas.clear();
    respuesta = null;
    lanza = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VozDeLaMaquinaImpl.canal, (call) async {
          llamadas.add(call);
          if (lanza != null) throw lanza!;
          return respuesta;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VozDeLaMaquinaImpl.canal, null),
  );

  group('lo que se le pregunta a la máquina', () {
    test('si puede reconocer sin red', () async {
      respuesta = true;
      expect(await const VozDeLaMaquinaImpl().disponible(), isTrue);
      expect(llamadas.single.method, 'disponible');
    });

    test('el permiso, que es aparte del micrófono', () async {
      respuesta = true;
      expect(await const VozDeLaMaquinaImpl().pedirPermiso(), isTrue);
      expect(llamadas.single.method, 'permiso');
    });

    test('lo que se dijo llega tal cual', () async {
      respuesta = 'corre el flow de login en el simulador';
      expect(
        await const VozDeLaMaquinaImpl().escuchar(),
        'corre el flow de login en el simulador',
      );
    });

    test(
      'hablar manda el texto; una frase vacía no molesta al canal',
      () async {
        await const VozDeLaMaquinaImpl().decir('hola');
        expect(llamadas.single.arguments, {'texto': 'hola'});

        llamadas.clear();
        await const VozDeLaMaquinaImpl().decir('   ');
        expect(llamadas, isEmpty);
      },
    );
  });

  group('cuando no se puede', () {
    // «No disponible» y «falló» se responden distinto a propósito: preguntar si
    // se puede tiene que contestar siempre, y escuchar tiene a alguien delante
    // esperando — un `''` silencioso ahí se leería como «no te entendí» cuando
    // lo que pasó es que este Mac no reconoce sin red.
    test('preguntar si se puede nunca revienta', () async {
      lanza = PlatformException(code: 'lo-que-sea');
      expect(await const VozDeLaMaquinaImpl().disponible(), isFalse);

      lanza = MissingPluginException();
      expect(await const VozDeLaMaquinaImpl().disponible(), isFalse);
    });

    test('escuchar sí sube el fallo, para poder decirlo', () async {
      lanza = PlatformException(
        code: 'sin-reconocimiento-local',
        message: 'Este Mac no reconoce voz sin salir a la red',
      );
      await expectLater(
        const VozDeLaMaquinaImpl().escuchar(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  // La invariante que le da sentido a todo esto, y la única que sobrevive a que
  // alguien toque el Swift sin acordarse del motivo.
  group('el audio no sale de la máquina', () {
    final swift = File('macos/Runner/NexusVozLocal.swift').readAsStringSync();

    test('el reconocimiento se pide en el dispositivo', () {
      expect(swift, contains('requiresOnDeviceRecognition = true'));
      expect(
        swift,
        isNot(contains('requiresOnDeviceRecognition = false')),
        reason:
            'con `false` el audio viaja a los servidores de Apple: sería '
            'cambiar un tercero por otro y no habría cerrado nada',
      );
    });

    test('y si la máquina no puede, se falla en vez de degradar', () {
      // Lo importante no es que compruebe `supportsOnDeviceRecognition`, es que
      // el camino de «no lo soporta» acabe en un error y no en una llamada a la
      // red disfrazada de éxito.
      expect(swift, contains('supportsOnDeviceRecognition'));
      expect(swift, contains('sin-reconocimiento-local'));
    });

    test('el permiso está declarado, o la app revienta al pedirlo', () {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();

      expect(
        plist,
        contains('NSSpeechRecognitionUsageDescription'),
        reason:
            'es un permiso distinto del micrófono y sin esta clave la primera '
            'llamada no pide nada: mata la app',
      );
    });
  });
}

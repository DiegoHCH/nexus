import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/domain/usecases/el_error_que_pinta_la_app.dart';

/// **Los errores del framework, que no salían por ninguna parte.**
///
/// 🔴 Reportado desde el repo del trabajo: «el error en debug, desde Nexus no
/// saltó, y al lanzarlo desde VS Code sí salió». Medido con una app de juguete
/// que revienta pintando, corrida con el mismo comando que usa Nexus
/// —`flutter run --machine`— y capturando las dos salidas:
///
/// - el `print` de la app **sale** por stdout;
/// - una excepción asíncrona sin dueño **sale**, con su traza;
/// - la excepción del framework al pintar —la de la pantalla roja— **no sale**.
///   Ni stdout ni stderr.
///
/// Está escrito en las dos partes: el framework manda esos errores por el VM
/// service (`postEvent('Flutter.Error', …)`, con `structuredErrors` encendido
/// por defecto en debug) y `flutter run` solo los imprime **si no está en modo
/// máquina** (`resident_runner.dart:1247`), porque da por hecho que quien
/// escucha es un IDE.
void main() {
  // Recortado de un evento **de verdad**, capturado del VM service de una app
  // que revienta pintando: el árbol de diagnósticos entero son 6 KB de una sola
  // línea y aquí no aporta nada. Lo que se conserva es la forma: `streamNotify`,
  // el `extensionKind` y el `renderedErrorText`.
  String eventoDeVerdad({
    String texto = 'Another exception was thrown: Bad state: el fallo pintando',
    String clase = 'Flutter.Error',
    String metodo = 'streamNotify',
  }) => jsonEncode({
    'jsonrpc': '2.0',
    'method': metodo,
    'params': {
      'streamId': 'Extension',
      'event': {
        'type': 'Event',
        'kind': 'Extension',
        'extensionKind': clase,
        'timestamp': 1788893463991,
        'extensionData': {
          'description': 'Exception caught by widgets library',
          'errorsSinceReload': 1,
          'renderedErrorText': texto,
        },
      },
    },
  });

  group('lo que dice un error de la app', () {
    test('se lee el texto que el framework ya redactó', () {
      expect(
        ElErrorQuePintaLaApp.loQueDice(eventoDeVerdad()),
        'Another exception was thrown: Bad state: el fallo pintando',
      );
    });

    // 🔴 **La trampa que costó capturar el evento crudo.** La documentación del
    // protocolo llama a esto «streamNotification»; lo que manda el VM service
    // es `streamNotify`. Con el nombre de la documentación no se descartaba un
    // error: se descartaban **todos**, y en silencio.
    test('y el nombre del método es el que manda de verdad', () {
      expect(
        ElErrorQuePintaLaApp.loQueDice(
          eventoDeVerdad(metodo: 'streamNotification'),
        ),
        isNull,
        reason: 'si algún día cambia, esta prueba lo dice',
      );
    });

    test('los demás eventos del canal no son errores', () {
      // Por ese mismo canal viajan los frames, y llegan a sesenta por segundo.
      for (final otro in ['Flutter.Frame', 'Flutter.FirstFrame']) {
        expect(
          ElErrorQuePintaLaApp.loQueDice(eventoDeVerdad(clase: otro)),
          isNull,
          reason: otro,
        );
      }
    });

    test('ni la respuesta a lo que pedimos', () {
      expect(
        ElErrorQuePintaLaApp.loQueDice(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': {'type': 'Success'},
          }),
        ),
        isNull,
      );
    });

    test('y lo que no es JSON no revienta: no es un error, y punto', () {
      for (final basura in ['', 'hola', '{a medias']) {
        expect(ElErrorQuePintaLaApp.loQueDice(basura), isNull, reason: basura);
      }
    });

    test('un evento sin texto redactado tampoco pinta nada', () {
      expect(
        ElErrorQuePintaLaApp.loQueDice(eventoDeVerdad(texto: '  ')),
        isNull,
      );
    });
  });

  group('cuántos errores trae un trozo de registro', () {
    // 🔴 **De un bloque cuenta su primera línea y nada más.** Un fallo con
    // veinte líneas de pila se anunciaría como veinte errores, y un número que
    // exagera se deja de creer igual que uno que se calla.
    test('un bloque con su traza es un error, no veinte', () {
      const bloque = '''
[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: Bad state: x
#0      Culpable.build (package:rojo/main.dart:12:21)
#1      Timer._createTimer (dart:async-patch/timer_patch.dart:18:15)
#2      _Timer._runTimers (dart:isolate-patch/timer_impl.dart:423:19)
''';

      expect(ElErrorQuePintaLaApp.cuantosErrores(bloque), 1);
    });

    // Y llegan pegados, porque el stdout de un proceso no viene en líneas: se
    // parte en pedazos del tamaño que decida el sistema.
    test('dos pegados en el mismo trozo son dos', () {
      expect(
        ElErrorQuePintaLaApp.cuantosErrores(
          '[ERROR:flutter/x.cc(1)] Unhandled Exception: uno\n'
          'flutter: algo por medio\n'
          'Another exception was thrown: dos',
        ),
        2,
      );
    });

    test('y un trozo sin errores no suma nada', () {
      expect(
        ElErrorQuePintaLaApp.cuantosErrores(
          'flutter: el print de la app\n✓ Built rojo.app',
        ),
        0,
      );
    });
  });

  group('por dónde se puede oír', () {
    test('por el socket del depurador, sí', () {
      expect(
        ElErrorQuePintaLaApp.sePuedeOir('ws://127.0.0.1:54541/Xlj15QVQ4_E=/ws'),
        isTrue,
      );
    });

    // Del mismo campo sale la URL de una corrida de web, y ahí no hay VM
    // service al que apuntarse: intentarlo dejaría un error en el registro cada
    // vez que alguien corra en Chrome.
    test('por la URL de una corrida de web, no', () {
      expect(
        ElErrorQuePintaLaApp.sePuedeOir('http://localhost:8080/'),
        isFalse,
      );
      expect(
        ElErrorQuePintaLaApp.sePuedeOir(null),
        isFalse,
        reason: 'todavía está compilando: no lo ha dicho',
      );
    });
  });

  test('apuntarse al canal se pide con su nombre', () {
    final pedido =
        jsonDecode(ElErrorQuePintaLaApp.peticionDeEscucha(7))
            as Map<String, Object?>;

    expect(pedido['method'], 'streamListen');
    expect(pedido['id'], 7);
    expect((pedido['params'] as Map)['streamId'], 'Extension');
  });

  group('qué línea se lee como un error', () {
    test('las tres formas que llegan de verdad', () {
      for (final linea in [
        // La del framework, por el VM service.
        '══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════',
        'Another exception was thrown: Bad state: el fallo pintando',
        // La asíncrona sin dueño, que sale por stdout y ya llegaba antes.
        '[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled '
            'Exception: Bad state: el fallo asíncrono',
      ]) {
        expect(ElErrorQuePintaLaApp.pintaMal(linea), isTrue, reason: linea);
      }
    });

    // La otra mitad: pasarse de listo aquí pinta de rojo un registro entero, y
    // un registro todo rojo no señala nada.
    test('y lo que no lo es se queda como está', () {
      for (final linea in [
        'flutter: el print de la app',
        '✓ Built build/macos/Build/Products/Debug/rojo.app',
        'Launching lib/main.dart on macOS in debug mode...',
        '[IMPORTANT:flutter/shell/platform/embedder/embedder.cc(53)] Impeller',
        'recarga automática: reiniciando — cambió el pubspec',
      ]) {
        expect(ElErrorQuePintaLaApp.pintaMal(linea), isFalse, reason: linea);
      }
    });
  });
}

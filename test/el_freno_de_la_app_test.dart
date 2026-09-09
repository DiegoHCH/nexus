import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/domain/usecases/el_freno_de_la_app.dart';

/// **El depurador de la app, sin app.**
///
/// Punto 7 del repaso —la otra mitad del punto 13 del plan del 4 de
/// septiembre—. Las entradas son las que manda el VM service de verdad, con su
/// forma entera: un evento de parada trae el isolate, el marco de arriba, la
/// ubicación y la excepción anidados uno dentro de otro, y leer mal cualquiera
/// de los niveles no falla — deja la parada muda.
Map<String, Object?> _evento(Map<String, Object?> evento) => {
  'jsonrpc': '2.0',
  'method': 'streamNotify',
  'params': {'streamId': 'Debug', 'event': evento},
};

String _comoLlega(Map<String, Object?> evento) => jsonEncode(_evento(evento));

/// Una parada por excepción, tal como llega.
final _paradaDeVerdad = _comoLlega({
  'type': 'Event',
  'kind': 'PauseException',
  'isolate': {'type': '@Isolate', 'id': 'isolates/1234', 'name': 'main'},
  'topFrame': {
    'type': 'Frame',
    'index': 0,
    'function': {'type': '@Function', 'name': 'StocksGate.build'},
    'location': {
      'type': 'SourceLocation',
      'script': {
        'type': '@Script',
        'id': 'libraries/1/scripts/package%3Aapp%2Fstocks%2Fgate.dart',
        'uri': 'package:app/stocks/gate.dart',
      },
      'tokenPos': 1897,
    },
  },
  'exception': {
    'type': '@Instance',
    'class': {'type': '@Class', 'name': 'StateError'},
    'valueAsString': 'Bad state: setState() called during build',
  },
});

void main() {
  group('lo que se le pide', () {
    Map<String, Object?> loQueSeManda(String peticion) =>
        jsonDecode(peticion) as Map<String, Object?>;

    test('los isolates, porque el freno se pone por isolate', () {
      final pedido = loQueSeManda(ElFrenoDeLaApp.pedirLosIsolates(7));

      expect(pedido['method'], 'getVM');
      expect(pedido['id'], 7);
      expect(pedido['jsonrpc'], '2.0');
    });

    test('apuntarse al canal del depurador', () {
      final pedido = loQueSeManda(ElFrenoDeLaApp.escucharLasParadas(2));

      expect(pedido['method'], 'streamListen');
      expect((pedido['params']! as Map)['streamId'], 'Debug');
    });

    // 🔴 **`setIsolatePauseMode`, no `setExceptionPauseMode`.** El segundo es el
    // nombre viejo —obsoleto desde la 3.53 del protocolo— y es el que decía la
    // ficha del repaso.
    test('el freno, con el modo que se pidió', () {
      final puesto = loQueSeManda(
        ElFrenoDeLaApp.frenar(
          3,
          isolate: 'isolates/1234',
          cuando: ModoDePausa.sinDueno,
        ),
      );

      expect(puesto['method'], 'setIsolatePauseMode');
      expect((puesto['params']! as Map)['isolateId'], 'isolates/1234');
      expect((puesto['params']! as Map)['exceptionPauseMode'], 'Unhandled');

      final quitado = loQueSeManda(
        ElFrenoDeLaApp.frenar(
          4,
          isolate: 'isolates/1234',
          cuando: ModoDePausa.ninguna,
        ),
      );
      expect((quitado['params']! as Map)['exceptionPauseMode'], 'None');
    });

    test('seguir, con paso y sin paso', () {
      final sinPaso = loQueSeManda(
        ElFrenoDeLaApp.seguir(5, isolate: 'isolates/1234'),
      );

      expect(sinPaso['method'], 'resume');
      expect(
        (sinPaso['params']! as Map).containsKey('step'),
        isFalse,
        reason: 'con `step` puesto a nada, la VM no reanuda: da error',
      );

      for (final (paso, comoSeDice) in const [
        (PasoDelDepurador.siguiente, 'Over'),
        (PasoDelDepurador.entrar, 'Into'),
        (PasoDelDepurador.salir, 'Out'),
      ]) {
        final conPaso = loQueSeManda(
          ElFrenoDeLaApp.seguir(6, isolate: 'isolates/1234', paso: paso),
        );
        expect((conPaso['params']! as Map)['step'], comoSeDice);
      }
    });

    test('el script, para traducir la posición', () {
      final pedido = loQueSeManda(
        ElFrenoDeLaApp.pedirElScript(
          8,
          isolate: 'isolates/1234',
          script: 'libraries/1/scripts/gate.dart',
        ),
      );

      expect(pedido['method'], 'getObject');
      expect(
        (pedido['params']! as Map)['objectId'],
        'libraries/1/scripts/gate.dart',
      );
    });
  });

  group('quién corre dentro', () {
    test('salen los isolates de la respuesta', () {
      const respuesta =
          '{"jsonrpc":"2.0","id":1,"result":{"type":"VM","isolates":['
          '{"type":"@Isolate","id":"isolates/1234","name":"main"},'
          '{"type":"@Isolate","id":"isolates/5678","name":"io.flutter.1"}]}}';

      expect(ElFrenoDeLaApp.losIsolates(respuesta), [
        'isolates/1234',
        'isolates/5678',
      ]);
    });

    test('y una respuesta que no lo es no revienta', () {
      expect(ElFrenoDeLaApp.losIsolates('no soy json'), isEmpty);
      expect(ElFrenoDeLaApp.losIsolates('{"result":{}}'), isEmpty);
      expect(ElFrenoDeLaApp.losIsolates(null), isEmpty);
    });
  });

  group('dónde se paró', () {
    test('la excepción, el marco y el archivo, de un evento de verdad', () {
      final parada = ElFrenoDeLaApp.laParada(_paradaDeVerdad)!;

      expect(parada.isolate, 'isolates/1234');
      expect(parada.excepcion, 'Bad state: setState() called during build');
      expect(parada.funcion, 'StocksGate.build');
      expect(parada.archivo, 'package:app/stocks/gate.dart');
      expect(parada.posicion, 1897);
      expect(parada.scriptId, isNotNull);
      expect(
        parada.linea,
        isNull,
        reason: 'la línea no viene en el evento: hay que pedir el script',
      );
    });

    // 🔴 **`streamNotify` y no `streamNotification`**, que es el nombre que sale
    // en la documentación del protocolo. Ya se pagó una vez con los errores del
    // framework: con el de la documentación se descarta **todo**.
    test('con el nombre de la documentación no llegaría nada', () {
      final conElNombreMalo = jsonEncode({
        ..._evento({
          'kind': 'PauseException',
          'isolate': {'id': 'isolates/1234'},
        }),
        'method': 'streamNotification',
      });

      expect(ElFrenoDeLaApp.laParada(conElNombreMalo), isNull);
    });

    test('donde acaba un paso también es una parada', () {
      final parada = ElFrenoDeLaApp.laParada(
        _comoLlega({
          'kind': 'PauseBreakpoint',
          'isolate': {'id': 'isolates/1234'},
          'topFrame': {
            'function': {'name': 'main'},
            'location': {
              'script': {'id': 's1', 'uri': 'package:app/main.dart'},
              'tokenPos': 10,
            },
          },
        }),
      )!;

      expect(parada.funcion, 'main');
      expect(parada.excepcion, isNull, reason: 'un paso no trae excepción');
    });

    // Nacer y morir no son pararse: enseñarlos como parada diría que la app se
    // detuvo cuando lo que hizo fue arrancar.
    test('arrancar y terminar no cuentan', () {
      for (final clase in const ['PauseStart', 'PauseExit', 'Resume']) {
        expect(
          ElFrenoDeLaApp.laParada(
            _comoLlega({
              'kind': clase,
              'isolate': {'id': 'isolates/1234'},
            }),
          ),
          isNull,
          reason: clase,
        );
      }
    });

    test('sin isolate no hay parada: no habría a quién decirle que siga', () {
      expect(
        ElFrenoDeLaApp.laParada(_comoLlega({'kind': 'PauseException'})),
        isNull,
      );
    });

    test('y lo que no es un evento se descarta sin quejarse', () {
      expect(ElFrenoDeLaApp.laParada('Connecting to VM service...'), isNull);
      expect(ElFrenoDeLaApp.laParada('{"id":1,"result":{}}'), isNull);
      expect(ElFrenoDeLaApp.laParada('[]'), isNull);
    });

    // Una excepción de instancia no siempre trae texto; entonces vale su clase,
    // que es más que nada.
    test('si no hay texto de la excepción, queda su clase', () {
      final parada = ElFrenoDeLaApp.laParada(
        _comoLlega({
          'kind': 'PauseException',
          'isolate': {'id': 'isolates/1'},
          'exception': {
            'class': {'name': 'RangeError'},
          },
        }),
      )!;

      expect(parada.excepcion, 'RangeError');
    });

    // 🔴 **Y la clase no se pega delante cuando hay texto.** La primera versión
    // la pegaba, y esta prueba lo cazó con el primer evento de verdad: los
    // errores del núcleo de Dart ya se nombran en su propio texto, así que
    // salía «StateError: Bad state: setState() called during build».
    test('pero con texto, no se le pega la clase delante', () {
      final parada = ElFrenoDeLaApp.laParada(
        _comoLlega({
          'kind': 'PauseException',
          'isolate': {'id': 'isolates/1'},
          'exception': {
            'class': {'name': 'StateError'},
            'valueAsString': 'Bad state: algo',
          },
        }),
      )!;

      expect(parada.excepcion, 'Bad state: algo');
    });
  });

  group('cuando sigue sola', () {
    test('se sabe qué isolate reanudó', () {
      expect(
        ElFrenoDeLaApp.siguio(
          _comoLlega({
            'kind': 'Resume',
            'isolate': {'id': 'isolates/1234'},
          }),
        ),
        'isolates/1234',
      );
    });

    test('y una parada no se lee como una reanudación', () {
      expect(ElFrenoDeLaApp.siguio(_paradaDeVerdad), isNull);
      expect(ElFrenoDeLaApp.siguio('cualquier cosa'), isNull);
    });
  });

  group('de la posición a la línea', () {
    // 🔴 **La tabla es una lista de listas**: cada fila empieza por el número de
    // línea y sigue con pares `posición, columna`. Leerla como un índice daría
    // un número plausible y equivocado, que es la peor clase de número.
    const script =
        '{"id":1,"result":{"type":"Script","uri":"package:app/gate.dart",'
        '"tokenPosTable":[[76,1880,3,1885,11],[78,1893,5,1897,12],'
        '[79,1920,4]]}}';

    test('la posición exacta da su línea', () {
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion(script, 1897), 78);
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion(script, 1920), 79);
    });

    // No toda posición es un token: la del evento puede caer entre dos.
    test('y una posición entre dos cae en la de antes', () {
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion(script, 1899), 78);
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion(script, 1890), 76);
    });

    test('antes de la primera, ninguna', () {
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion(script, 10), isNull);
    });

    test('sin tabla o sin posición, ninguna, y no revienta', () {
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion(script, null), isNull);
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion('{"result":{}}', 1897), isNull);
      expect(ElFrenoDeLaApp.laLineaDeLaPosicion('roto', 1897), isNull);
    });

    test('una fila mal formada se salta, y las buenas siguen contando', () {
      const conBasura =
          '{"result":{"tokenPosTable":[["ochenta",1,2],[78,1893,5],[]]}}';

      expect(ElFrenoDeLaApp.laLineaDeLaPosicion(conBasura, 1893), 78);
    });
  });

  group('cómo se cuenta en la fila', () {
    test('el archivo por su nombre, con la línea y la función', () {
      final parada = ElFrenoDeLaApp.laParada(_paradaDeVerdad)!.conLaLinea(78);

      expect(parada.donde, 'gate.dart:78 · StocksGate.build');
    });

    // En la fila caben unos treinta caracteres, y la ruta entera se corta justo
    // por donde importa.
    test('y no la ruta del paquete, que se corta por donde importa', () {
      final parada = ElFrenoDeLaApp.laParada(_paradaDeVerdad)!.conLaLinea(78);

      expect(parada.donde, isNot(contains('package:')));
    });

    test('sin línea, el archivo solo', () {
      final parada = ElFrenoDeLaApp.laParada(_paradaDeVerdad)!;

      expect(parada.donde, 'gate.dart · StocksGate.build');
    });

    test('y sin archivo, la función', () {
      const parada = LaParadaDeLaApp(isolate: 'i1', funcion: 'main');

      expect(parada.donde, 'main');
    });
  });
}

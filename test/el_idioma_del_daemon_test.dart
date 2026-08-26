import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/lineas_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/peticiones_pendientes.dart';
import 'package:nexus/features/run/domain/usecases/protocolo_del_daemon.dart';

/// El idioma de `flutter run --machine`.
///
/// Las líneas de aquí tienen la forma de las de verdad: cada mensaje envuelto en
/// un array de un elemento, los eventos con `params`, y las respuestas con `id`.
/// Los tres casos raros —el `true` pelado de `app.stop`, el progreso que se
/// solapa, y la línea partida por la mitad— son los que costaron dinero en la
/// implementación de la que se copia esto.
void main() {
  group('leer una línea', () {
    test('un evento con sus params', () {
      final leido = ProtocoloDelDaemon.leerLinea(
        '[{"event":"app.start","params":{"appId":"abc","deviceId":"emulator-5554"}}]',
      );

      expect(leido, isA<EventoDelDaemon>());
      final evento = leido as EventoDelDaemon;
      expect(evento.nombre, 'app.start');
      expect(evento.params['appId'], 'abc');
    });

    test('una respuesta con su id', () {
      final leido = ProtocoloDelDaemon.leerLinea('[{"id":3,"result":{"code":0}}]');

      expect(leido, isA<RespuestaDelDaemon>());
      expect((leido as RespuestaDelDaemon).id, 3);
    });

    test('un id de cero es un id', () {
      // Con un emparejamiento por «no nulo» esto se leería como registro y la
      // primera petición de la sesión se quedaría esperando para siempre.
      final leido = ProtocoloDelDaemon.leerLinea('[{"id":0,"result":true}]');
      expect(leido, isA<RespuestaDelDaemon>());
      expect((leido as RespuestaDelDaemon).id, 0);
    });

    test('todo lo que no venga envuelto es registro, y se conserva', () {
      // Aquí viven los errores de compilación, que son justo lo que quiere leer
      // alguien cuyo `flutter run` no arrancó. Tirarlos deja un fallo sin pista.
      final leido = ProtocoloDelDaemon.leerLinea(
        "lib/main.dart:12:3: Error: Expected ';' after this.",
      );

      expect(leido, isA<RegistroDelDaemon>());
      expect((leido as RegistroDelDaemon).texto, contains('Expected'));
    });

    test('un JSON suelto de la app tampoco se confunde con el protocolo', () {
      // Por eso el formato envuelve cada mensaje en `[{…}]`: una app que imprime
      // su propio JSON no puede hacerse pasar por el daemon.
      expect(
        ProtocoloDelDaemon.leerLinea('{"event":"app.started"}'),
        isA<RegistroDelDaemon>(),
      );
    });

    test('un array roto es registro, no una excepción', () {
      expect(
        ProtocoloDelDaemon.leerLinea('[{"event": roto}]'),
        isA<RegistroDelDaemon>(),
      );
    });
  });

  group('las peticiones', () {
    test('recargar y reiniciar son el mismo método con una bandera', () {
      final reload = ProtocoloDelDaemon.peticionDeRecarga(
        1,
        'abc',
        completa: false,
      );
      final restart = ProtocoloDelDaemon.peticionDeRecarga(
        2,
        'abc',
        completa: true,
      );

      expect(reload, contains('"method":"app.restart"'));
      expect(reload, contains('"fullRestart":false'));
      expect(restart, contains('"fullRestart":true'));
      // Una línea por mensaje, como espera el otro lado.
      expect(reload.endsWith('\n'), isTrue);
      expect(reload.trim().split('\n').length, 1);
    });

    test('parar va por el daemon y lleva el appId', () {
      // Matar el proceso dejaría la app abierta en el dispositivo y sin nadie
      // que avise; por aquí el otro lado contesta y manda su `app.stop`.
      final parar = ProtocoloDelDaemon.peticionDeParada(7, 'abc');
      expect(parar, contains('"method":"app.stop"'));
      expect(parar, contains('"appId":"abc"'));
    });
  });

  group('qué salió de una respuesta', () {
    test('código cero es que fue bien', () {
      expect(ProtocoloDelDaemon.resultadoDe({'code': 0}, null).ok, isTrue);
    });

    test('cualquier otro código trae su motivo', () {
      final r = ProtocoloDelDaemon.resultadoDe(
        {'code': 1, 'message': 'Hot reload no aplicable'},
        null,
      );
      expect(r.ok, isFalse);
      expect(r.error, 'Hot reload no aplicable');
    });

    test('un código sin mensaje se dice igual', () {
      expect(
        ProtocoloDelDaemon.resultadoDe({'code': 5}, null).error,
        contains('5'),
      );
    });

    test('un error puesto gana sobre todo', () {
      final r = ProtocoloDelDaemon.resultadoDe(null, 'no hay app corriendo');
      expect(r.ok, isFalse);
      expect(r.error, 'no hay app corriendo');
    });

    test('**el `true` pelado de app.stop es un éxito**', () {
      // No trae objeto ni código. Con la regla del `code` se leería como fallo, y
      // parar la app diría que no se pudo parar mientras se paraba.
      expect(ProtocoloDelDaemon.resultadoDe(true, null).ok, isTrue);
      expect(ProtocoloDelDaemon.resultadoDe(null, null).ok, isTrue);
    });
  });

  group('el progreso, que se solapa', () {
    test('lo que se enseña es el último que siga abierto', () {
      // Compilar y firmar a la vez: dos ids abiertos, y cada uno se cierra por su
      // cuenta. Guardar solo el último mensaje dejaría la barra diciendo
      // «firmando» cuando la firma acabó y la compilación seguía.
      var mapa = ProtocoloDelDaemon.aplicaProgreso(const {}, {
        'id': '1',
        'message': 'Compilando',
      });
      mapa = ProtocoloDelDaemon.aplicaProgreso(mapa, {
        'id': '2',
        'message': 'Firmando',
      });
      expect(ProtocoloDelDaemon.progresoVisible(mapa)?.mensaje, 'Firmando');

      // Se cierra el segundo: vuelve a verse el primero, que sigue abierto.
      mapa = ProtocoloDelDaemon.aplicaProgreso(mapa, {
        'id': '2',
        'finished': true,
      });
      expect(ProtocoloDelDaemon.progresoVisible(mapa)?.mensaje, 'Compilando');

      mapa = ProtocoloDelDaemon.aplicaProgreso(mapa, {
        'id': '1',
        'finished': true,
      });
      expect(ProtocoloDelDaemon.progresoVisible(mapa), isNull);
    });

    test('un progreso sin id no ensucia el mapa', () {
      expect(
        ProtocoloDelDaemon.aplicaProgreso(const {}, {'message': 'algo'}),
        isEmpty,
      );
    });
  });

  group('los trozos que llegan del proceso', () {
    test('una línea partida por la mitad se recompone', () {
      // **El fallo que este decodificador viene a evitar.** Un stream de proceso
      // llega en trozos del tamaño que decida el sistema, y el mensaje partido
      // sería registro basura: se perdería el evento, y el que se pierde es
      // `app.started`.
      final lineas = LineasDelDaemon();

      expect(lineas.add('[{"event":"app.st'), isEmpty);
      final salieron = lineas.add('arted","params":{"appId":"abc"}}]\n').toList();

      expect(salieron.length, 1);
      expect((salieron.single as EventoDelDaemon).nombre, 'app.started');
    });

    test('dos mensajes pegados salen los dos', () {
      final lineas = LineasDelDaemon();
      final salieron = lineas
          .add('[{"event":"app.start","params":{}}]\n[{"id":1,"result":true}]\n')
          .toList();

      expect(salieron.length, 2);
      expect(salieron.first, isA<EventoDelDaemon>());
      expect(salieron.last, isA<RespuestaDelDaemon>());
    });

    test('lo que queda sin salto se guarda, no se tira', () {
      final lineas = LineasDelDaemon();
      lineas.add('[{"event":"app.start","params":{}}]\n[{"id":9,"result":true}]');

      // Todavía a medias: no ha salido.
      expect(lineas.add('').isEmpty, isTrue);
      // Y al cerrarse el proceso se ofrece, porque la última línea de algo que
      // murió mal suele ser el motivo.
      final resto = lineas.cierra();
      expect((resto! as RespuestaDelDaemon).id, 9);
      expect(lineas.cierra(), isNull);
    });
  });

  group('las peticiones que esperan contestación', () {
    test('la respuesta llega a quien preguntó, y no a otro', () async {
      final escritas = <String>[];
      final peticiones = PeticionesPendientes(escribir: escritas.add);

      final primera = peticiones.pedir(
        (id) => ProtocoloDelDaemon.peticionDeRecarga(id, 'abc', completa: false),
      );
      final segunda = peticiones.pedir(
        (id) => ProtocoloDelDaemon.peticionDeParada(id, 'abc'),
      );

      expect(peticiones.esperando, 2);
      // Los ids los pone la clase, y son distintos: llevar la cuenta fuera es
      // cómo se acaban repitiendo.
      expect(escritas.first, contains('"id":1'));
      expect(escritas.last, contains('"id":2'));

      // Contesta **la segunda primero**, que es lo normal: parar es más rápido
      // que recargar. Si se emparejara por orden de llegada, cada una recibiría
      // la respuesta de la otra.
      peticiones.recibe(const RespuestaDelDaemon(id: 2, result: true));
      expect((await segunda).ok, isTrue);

      peticiones.recibe(
        const RespuestaDelDaemon(id: 1, result: {'code': 1, 'message': 'no aplicable'}),
      );
      final r = await primera;
      expect(r.ok, isFalse);
      expect(r.error, 'no aplicable');
      expect(peticiones.esperando, 0);
    });

    test('una respuesta de nadie se reconoce como tal', () {
      // Para que quien lee la salida la trate como registro en vez de tirarla en
      // silencio.
      final peticiones = PeticionesPendientes(escribir: (_) {});
      expect(
        peticiones.recibe(const RespuestaDelDaemon(id: 99, result: true)),
        isFalse,
      );
    });

    test('si no contesta nadie, se rinde al llegar el plazo', () {
      // Con el reloj de mentira: esperar dos minutos de verdad haría una suite
      // que nadie corre, que es el mismo motivo por el que `fake_async` ya está
      // en este proyecto.
      fakeAsync((async) {
        final peticiones = PeticionesPendientes(
          escribir: (_) {},
          tope: const Duration(seconds: 30),
        );

        ({bool ok, String? error})? resultado;
        peticiones.pedir((id) => 'lo que sea').then((r) => resultado = r);

        async.elapse(const Duration(seconds: 29));
        expect(resultado, isNull, reason: 'se rindió antes de tiempo');

        async.elapse(const Duration(seconds: 2));
        expect(resultado?.ok, isFalse);
        expect(peticiones.esperando, 0);
      });
    });

    test('una respuesta que llega tarde no revienta', () {
      // Completar dos veces un `Completer` lanza, y esto pasa de verdad: el
      // dispositivo contesta justo después de que nos rindiéramos.
      fakeAsync((async) {
        final peticiones = PeticionesPendientes(
          escribir: (_) {},
          tope: const Duration(seconds: 10),
        );
        peticiones.pedir((id) => 'x');
        async.elapse(const Duration(seconds: 11));

        expect(
          () => peticiones.recibe(const RespuestaDelDaemon(id: 1, result: true)),
          returnsNormally,
        );
      });
    });

    test('si el proceso se muere, nadie se queda esperando el plazo', () async {
      final peticiones = PeticionesPendientes(escribir: (_) {});
      final espera = peticiones.pedir((id) => 'x');

      peticiones.cierra();

      final r = await espera;
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
    });

    test('si escribir falla, se contesta con el motivo y no con una excepción', () async {
      // El proceso pudo morirse entre decidir pedir y escribir.
      final peticiones = PeticionesPendientes(
        escribir: (_) => throw StateError('stdin cerrado'),
      );

      final r = await peticiones.pedir((id) => 'x');
      expect(r.ok, isFalse);
      expect(r.error, contains('stdin cerrado'));
      expect(peticiones.esperando, 0);
    });
  });
}

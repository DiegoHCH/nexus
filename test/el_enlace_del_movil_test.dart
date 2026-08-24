import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

// El lado del teléfono, probado **sin red**.
//
// Lo que puede romperse aquí son los tiempos y el orden: qué pasa si el `ack` no
// llega, si llega diciendo «duplicada», si vuelve la conexión con un hueco en la
// numeración. Nada de eso se ejercita tocando una pantalla, y provocarlo de verdad
// significaría cortar el wifi a mano en cada prueba.
//
// Los plazos van con `fake_async` y no con esperas cortas: una prueba que duerme 50 ms
// pasa en esta máquina y falla en un runner cargado, y una prueba que falla sola es
// una prueba que se acaba borrando.

class _SocketFalso implements ChannelSocket {
  final _entrantes = StreamController<String>();

  /// Lo que el enlace mandó, ya decodificado.
  final enviados = <Frame>[];
  var cerrado = false;

  @override
  Stream<String> get entrantes => _entrantes.stream;

  @override
  void enviar(String texto) => enviados.add(Frame.decode(texto));

  @override
  Future<void> close() async {
    cerrado = true;
    if (!_entrantes.isClosed) await _entrantes.close();
  }

  /// El Mac manda algo.
  void recibe(Frame marco) => _entrantes.add(marco.encode());

  /// Lo mismo, pero crudo: para el mensaje roto.
  void recibeCrudo(String texto) => _entrantes.add(texto);

  /// Se cae la conexión.
  void caer() {
    if (!_entrantes.isClosed) _entrantes.close();
  }

  T? ultimo<T extends Frame>() {
    for (final f in enviados.reversed) {
      if (f is T) return f;
    }
    return null;
  }
}

void main() {
  late _SocketFalso socket;
  late List<_SocketFalso> abiertos;
  late ChannelLink enlace;

  /// Monta el enlace con un socket falso. [nuevoCadaVez] hace que reconectar abra
  /// otro socket, que es lo que hace la vida real.
  /// Si `abrir` tiene que fallar, para dejar al enlace dando vueltas en su escalera
  /// de reintentos. Hace falta para probar lo que pasa **mientras** reintenta, que es
  /// donde vive más de un fallo de este enlace.
  var sinLlegar = false;

  ChannelLink montar({
    List<Duration>? esperas,
    Future<void> Function(Duration)? dormir,
    String Function()? idNuevo,
  }) {
    abiertos = [];
    sinLlegar = false;
    socket = _SocketFalso();
    abiertos.add(socket);
    var primera = true;
    return ChannelLink(
      abrir: () async {
        if (sinLlegar) throw const ChannelUnreachable();
        if (primera) {
          primera = false;
          return socket;
        }
        socket = _SocketFalso();
        abiertos.add(socket);
        return socket;
      },
      appVersion: '0.0.8',
      esperas: esperas ?? const [Duration(milliseconds: 1)],
      dormir: dormir,
      idNuevo: idNuevo,
    );
  }

  /// Conecta y contesta la bienvenida, que es el punto de partida de todo.
  Future<void> conectado(ChannelLink e, {int seq = 0}) async {
    final futuro = e.conectar();
    await Future<void>.delayed(Duration.zero);
    socket.recibe(Welcome(protocol: ProtocolRange.mine, seq: seq));
    await futuro;
  }

  tearDown(() async {
    await enlace.cerrar();
  });

  group('el saludo', () {
    test('manda el Hello y espera la bienvenida', () async {
      enlace = montar();
      await conectado(enlace);

      final hola = socket.ultimo<Hello>()!;
      expect(hola.peer, Peer.mobile);
      expect(hola.appVersion, '0.0.8');
      expect(enlace.ahora, LinkState.conectado);
    });

    test('«actualízate» es terminal: no se reintenta', () async {
      enlace = montar();
      var aperturas = 0;
      final e = ChannelLink(
        abrir: () async {
          aperturas++;
          return socket;
        },
        appVersion: '0.0.1',
        esperas: const [Duration(milliseconds: 1)],
      );
      final futuro = e.conectar();
      await Future<void>.delayed(Duration.zero);
      socket.recibe(
        UpgradeRequired(protocol: ProtocolRange.mine, who: Peer.mobile),
      );
      await futuro;

      // Reintentar aquí sería pedirle a la red que arregle un problema de
      // versiones — y en bucle, convierte un mensaje claro en una app colgada.
      expect(e.ahora, LinkState.hayQueActualizar);
      expect(aperturas, 1);
      await e.cerrar();
    });

    test('la bienvenida con otro seq dispara el resync sola', () async {
      enlace = montar();
      // El Mac va por el 40 y este teléfono no ha visto ninguno.
      await conectado(enlace, seq: 40);

      // Sin pedir nada: el `seq` de la bienvenida existe justo para esto, saber si
      // vas al día **sin gastar una petición**.
      expect(socket.ultimo<Resume>()?.lastSeq, 0);
      expect(enlace.ahora, LinkState.resincronizando);
    });

    test('y si coincide, no pide nada', () async {
      enlace = montar();
      await conectado(enlace, seq: 0);

      expect(socket.ultimo<Resume>(), isNull);
      expect(enlace.ahora, LinkState.conectado);
    });
  });

  group('pedir y esperar', () {
    test('el resultado resuelve la petición', () async {
      enlace = montar(idNuevo: () => 'p1');
      await conectado(enlace);

      final futuro = enlace.pedir(RemoteMethod.conversations);
      await Future<void>.delayed(Duration.zero);
      socket.recibe(const Ack(id: 'p1'));
      socket.recibe(const Result(id: 'p1', data: {'conversations': []}));

      expect(await futuro, containsPair('conversations', isEmpty));
      expect(socket.ultimo<Call>()?.method, 'conversations');
    });

    test('un rechazo llega con su código, no como «algo falló»', () async {
      enlace = montar(idNuevo: () => 'p1');
      await conectado(enlace);

      final futuro = enlace.pedir(
        RemoteMethod.meter,
        params: {'conversation': 'fantasma'},
      );
      await Future<void>.delayed(Duration.zero);
      socket.recibe(const Ack(id: 'p1'));
      socket.recibe(
        const Failure(id: 'p1', code: 'unknownConversation', message: 'ya no'),
      );

      // El código es lo que el teléfono convierte en algo que enseñar. Sin él, la
      // pantalla solo podría decir «error».
      await expectLater(
        futuro,
        throwsA(
          isA<LinkError>()
              .having((e) => e.failure, 'failure', LinkFailure.rechazada)
              .having((e) => e.code, 'code', 'unknownConversation'),
        ),
      );
    });

    test(
      '«duplicada» se resuelve ya, sin esperar un resultado que no viene',
      () async {
        enlace = montar(idNuevo: () => 'p1');
        await conectado(enlace);

        final futuro = enlace.pedir(RemoteMethod.sendErrand);
        await Future<void>.delayed(Duration.zero);
        // El Mac ya la tenía: contesta el ack y **no ejecuta**, así que no habrá
        // resultado. Quedarse esperándolo es lo que se ve como «no responde».
        socket.recibe(const Ack(id: 'p1', duplicate: true));

        expect(await futuro, containsPair('duplicate', true));
      },
    );

    test('sin enlace no se finge que se mandó', () async {
      enlace = montar();
      await expectLater(
        enlace.pedir(RemoteMethod.conversations),
        throwsA(
          isA<LinkError>().having(
            (e) => e.failure,
            'failure',
            LinkFailure.desconectado,
          ),
        ),
      );
    });
  });

  group('los dos plazos, que es de lo que depende reintentar', () {
    test('sin ack: «pudo no llegar»', () {
      fakeAsync((reloj) {
        final s = _SocketFalso();
        final e = ChannelLink(
          abrir: () async => s,
          appVersion: '0.0.8',
          plazoDelAck: const Duration(seconds: 5),
          plazoDeLaRespuesta: const Duration(seconds: 30),
        );
        e.conectar();
        reloj.flushMicrotasks();
        s.recibe(const Welcome(protocol: ProtocolRange.mine, seq: 0));
        reloj.flushMicrotasks();

        Object? fallo;
        e.pedir(RemoteMethod.sendErrand).catchError((Object err) {
          fallo = err;
          return <String, Object?>{};
        });
        reloj.elapse(const Duration(seconds: 6));

        // Nadie confirmó, así que la petición **pudo no llegar** y reintentarla es
        // seguro. Esa es la única razón de tener dos plazos.
        expect((fallo! as LinkError).failure, LinkFailure.sinConfirmacion);
      });
    });

    test('con ack y sin respuesta: «llegó y no contestó»', () {
      fakeAsync((reloj) {
        final s = _SocketFalso();
        final e = ChannelLink(
          abrir: () async => s,
          appVersion: '0.0.8',
          plazoDelAck: const Duration(seconds: 5),
          plazoDeLaRespuesta: const Duration(seconds: 30),
        );
        e.conectar();
        reloj.flushMicrotasks();
        s.recibe(const Welcome(protocol: ProtocolRange.mine, seq: 0));
        reloj.flushMicrotasks();

        Object? fallo;
        final idMandado = <String>[];
        e.pedir(RemoteMethod.sendErrand).catchError((Object err) {
          fallo = err;
          return <String, Object?>{};
        });
        reloj.flushMicrotasks();
        idMandado.add(s.ultimo<Call>()!.id);
        s.recibe(Ack(id: idMandado.single));

        // Pasado el plazo corto no falla: el ack ya llegó.
        reloj.elapse(const Duration(seconds: 10));
        expect(fallo, isNull);

        reloj.elapse(const Duration(seconds: 25));
        // Reintentar esto no sirve: ya está en el Mac, y el deduplicador contestaría
        // «duplicada» sin volver a ejecutarlo.
        expect((fallo! as LinkError).failure, LinkFailure.sinRespuesta);
      });
    });
  });

  group('los eventos', () {
    test('en orden, se emiten y avanzan la cuenta', () async {
      enlace = montar();
      await conectado(enlace);
      final vistos = <Event>[];
      enlace.eventos.listen(vistos.add);

      socket.recibe(const Event(seq: 1, kind: 'text', data: {'append': 'ho'}));
      socket.recibe(const Event(seq: 2, kind: 'text', data: {'append': 'la'}));
      await Future<void>.delayed(Duration.zero);

      expect(vistos.map((e) => e.seq), [1, 2]);
      expect(enlace.ultimoSeq, 2);
    });

    test('uno repetido se descarta', () async {
      enlace = montar();
      await conectado(enlace);
      final vistos = <Event>[];
      enlace.eventos.listen(vistos.add);

      socket.recibe(const Event(seq: 1, kind: 'text'));
      socket.recibe(const Event(seq: 1, kind: 'text'));
      await Future<void>.delayed(Duration.zero);

      // Pasa al reconectar: el `Resume` se solapa con lo que ya llegó, y aplicarlo
      // dos veces duplicaría texto en la pantalla.
      expect(vistos, hasLength(1));
    });

    test('un hueco pide lo que falta y NO aplica el evento', () async {
      enlace = montar();
      await conectado(enlace);
      final vistos = <Event>[];
      enlace.eventos.listen(vistos.add);

      socket.recibe(const Event(seq: 1, kind: 'text'));
      // Falta el 2 y el 3.
      socket.recibe(const Event(seq: 4, kind: 'text'));
      await Future<void>.delayed(Duration.zero);

      // Aplicar el 4 dejaría la pantalla con un agujero **silencioso**, que es lo
      // peor porque nadie lo va a mirar. Se pide desde el 1 y este se descarta:
      // volverá en el resync, en orden.
      expect(vistos.map((e) => e.seq), [1]);
      expect(socket.ultimo<Resume>()?.lastSeq, 1);
      expect(enlace.ahora, LinkState.resincronizando);
    });

    test('el snapshot pone la cuenta al día y vuelve a conectado', () async {
      enlace = montar();
      await conectado(enlace);
      final fotos = <Snapshot>[];
      enlace.fotos.listen(fotos.add);

      socket.recibe(const Snapshot(seq: 99, data: {'conversations': []}));
      await Future<void>.delayed(Duration.zero);

      expect(fotos, hasLength(1));
      expect(enlace.ultimoSeq, 99);
      expect(enlace.ahora, LinkState.conectado);
    });
  });

  group('cuando se cae', () {
    test(
      'reconecta, y las peticiones en vuelo dicen si se pueden reintentar',
      () async {
        enlace = montar(idNuevo: () => 'p1');
        await conectado(enlace);

        // Una confirmada y otra no. El motivo del fallo tiene que ser distinto.
        final confirmada = enlace.pedir(RemoteMethod.sendErrand);
        // El oyente se engancha **antes** de tirar la conexión: si no, el error se
        // completa sin nadie mirando y la zona lo da por no capturado.
        final esperada = expectLater(
          confirmada,
          throwsA(
            isA<LinkError>().having(
              (e) => e.failure,
              'failure',
              LinkFailure.sinRespuesta,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        socket.recibe(const Ack(id: 'p1'));
        await Future<void>.delayed(Duration.zero);

        socket.caer();
        await esperada;
        // Y se abrió otro socket: reconectar es el comportamiento por defecto porque
        // un móvil entra y sale de cobertura todo el rato.
        expect(abiertos.length, greaterThan(1));
      },
    );

    test('sin ack, la que estaba en vuelo se puede reintentar', () async {
      enlace = montar(idNuevo: () => 'p1');
      await conectado(enlace);

      final sinConfirmar = enlace.pedir(RemoteMethod.sendErrand);
      final esperada = expectLater(
        sinConfirmar,
        throwsA(
          isA<LinkError>().having(
            (e) => e.failure,
            'failure',
            LinkFailure.sinConfirmacion,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      socket.caer();
      await esperada;
    });

    test('tras desconectar, una caída posterior no reconecta', () async {
      enlace = montar();
      await conectado(enlace);
      await enlace.desconectar();
      final cuantos = abiertos.length;

      socket.caer();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Esto lo cumple la escucha ya cancelada, no la bandera: `desconectar` corta
      // la suscripción, así que el `onDone` nunca llega. Se deja porque el
      // comportamiento importa, pero **no** es lo que vigila la bandera — eso es la
      // prueba de abajo.
      expect(abiertos.length, cuantos);
      expect(enlace.ahora, LinkState.sinConexion);
    });

    test('desconectar mientras reintenta corta el bucle', () async {
      // **Esta es la que vigila la bandera de verdad**, y hubo que escribirla al ver
      // que la de arriba pasaba igual con las dos guardas quitadas: allí la escucha
      // ya estaba cancelada, así que la caída nunca llegaba al código que decide si
      // reintentar. El escenario real es otro: el bucle está esperando entre
      // intentos —un móvil sin cobertura— y se cierra la pantalla.
      //
      // Sin la guarda, ese bucle sigue vivo despertando la radio para siempre.
      var aperturas = 0;
      final durmiendo = <Completer<void>>[];
      final e = ChannelLink(
        abrir: () async {
          aperturas++;
          throw const SocketException('no hay red');
        },
        appVersion: '0.0.8',
        esperas: const [Duration(milliseconds: 1)],
        dormir: (_) {
          final c = Completer<void>();
          durmiendo.add(c);
          return c.future;
        },
      );

      final conectando = e.conectar();
      // Se le deja llegar a la primera espera.
      await Future<void>.delayed(Duration.zero);
      expect(aperturas, 1);
      expect(durmiendo, hasLength(1), reason: 'está esperando para reintentar');

      await e.desconectar();
      durmiendo.single.complete();
      await conectando;
      await Future<void>.delayed(Duration.zero);

      expect(aperturas, 1, reason: 'no volvió a intentarlo');
      await e.cerrar();
    });
  });

  group('lo que no se entiende no tira el enlace', () {
    test('un mensaje roto se anota y se sigue', () async {
      enlace = montar();
      await conectado(enlace);

      socket.recibeCrudo('esto no es json');
      await Future<void>.delayed(Duration.zero);
      socket.recibe(const Event(seq: 1, kind: 'text'));
      await Future<void>.delayed(Duration.zero);

      // Dejar de leer sí cerraría la conexión; un mensaje roto, no.
      expect(enlace.ultimoSeq, 1);
      expect(enlace.ahora, LinkState.conectado);
    });

    test('un marco de una versión más nueva se ignora', () async {
      enlace = montar();
      await conectado(enlace);

      socket.recibeCrudo('{"t":"algoDelFuturo","x":1}');
      await Future<void>.delayed(Duration.zero);

      // Es lo que permite que el Mac se actualice sin romper este teléfono.
      expect(enlace.ahora, LinkState.conectado);
    });
  });

  group('reintentar con el mismo id, y solo cuando toca', () {
    test('lo que muta sí; lo que lee, no', () {
      // El deduplicador del Mac protege **efectos**, no respuestas: reenviar una
      // lectura con el mismo id devuelve «duplicada» y ninguna respuesta, así que
      // una consulta perdida se vuelve a pedir con id nuevo. Meterlas en el mismo
      // saco es la forma de que consultar deje de funcionar tras un corte.
      expect(
        {
          for (final m in RemoteMethod.values)
            m.name: ChannelLink.reintentable(m),
        },
        {
          // Cambian algo en el Mac: el mismo id los protege de correr dos veces.
          'sendErrand': true,
          'stopErrand': true,
          'unlockWrites': true,
          // Abrir y retomar **crean estado**: reenviarlas con id nuevo abriría dos
          // conversaciones sobre la misma carpeta, que el escritorio no permite.
          'openConversation': true,
          'resumeConversation': true,
          // Renombrar y cerrar son **idempotentes**: el mismo nombre dos veces es el
          // mismo nombre, y cerrar lo ya cerrado deja lo mismo. Con id nuevo, un cierre
          // perdido se quedaria sin hacer.
          'renameConversation': true,
          'closeConversation': true,
          // Abrir y cerrar el microfono: idempotentes, y con id nuevo **un cierre
          // perdido dejaria el microfono abierto**, que es el peor final de la lista.
          'startVoice': true,
          'stopVoice': true,
          // Solo leen: una consulta perdida se vuelve a pedir con id nuevo, porque el
          // deduplicador protege efectos y no respuestas.
          'conversations': false,
          'history': false,
          'meter': false,
          'permission': false,
          'archive': false,
          'folders': false,
          'artifacts': false,
          'artifact': false,
        },
      );
    });
  });

  group('un solo intento a la vez', () {
    test('dos llamadas a conectar no abren dos sockets', () async {
      // **El fallo, medido en el registro del Mac:** una conexion pidiendo cosas y otra
      // tirada a los 10 s por no saludar. Con dos bucles, los dos escriben en el mismo
      // socket, el mismo oyente y el mismo saludo, y el ultimo gana: el `Welcome` del
      // que si saludo le llega a un oyente reemplazado, nadie pasa el estado a
      // «conectado» y la pantalla se queda en «reconectando» **con la conexion
      // funcionando**. Es lo que pasa al volver del fondo.
      enlace = montar();

      unawaited(enlace.conectar());
      unawaited(enlace.conectar());
      await Future<void>.delayed(Duration.zero);

      expect(
        abiertos,
        hasLength(1),
        reason: 'el segundo bucle abre un socket que nadie saluda',
      );
    });

    test('desconectar mientras reintenta no deja el guardia puesto', () async {
      // **La salida del bucle por arriba**, que es la unica que suelta el guardia en
      // el `while` y no en un `return`. Si se quedara puesto, el siguiente `conectar`
      // volveria en silencio sin abrir nada — y eso es peor que el fallo original: el
      // telefono no tendria forma de volver.
      enlace = montar(esperas: const [Duration(milliseconds: 10)]);
      sinLlegar = true;
      unawaited(enlace.conectar());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await enlace.desconectar();
      sinLlegar = false;
      final antes = abiertos.length;

      unawaited(enlace.conectar());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(abiertos.length, greaterThan(antes));
    });

    test('desconectar a mano no deja el enlace sin poder reintentar', () async {
      // El guardia tiene que soltarse **tambien al salir del bucle**, que es por donde
      // se sale al desconectar a mano. Si se quedara puesto, el siguiente `conectar`
      // volveria en silencio sin abrir nada — y eso es peor que el fallo original: el
      // telefono no tendria forma de volver, ni cancelando.
      enlace = montar(esperas: const [Duration(milliseconds: 10)]);
      await conectado(enlace);
      final antes = abiertos.length;

      await enlace.desconectar();
      unawaited(enlace.conectar());
      await Future<void>.delayed(Duration.zero);

      expect(abiertos.length, greaterThan(antes));
    });

    test('despues de conectar se puede volver a intentar', () async {
      // El guardia tiene que soltarse en **todas** las salidas del bucle, o el enlace
      // se queda sin poder reintentar nunca — que es peor que el fallo original.
      enlace = montar(esperas: const [Duration(milliseconds: 10)]);
      await conectado(enlace);

      // Se cae y el enlace lo reintenta por su cuenta: si el guardia se hubiera
      // quedado puesto, esto no abriria nada.
      socket.caer();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(abiertos.length, greaterThan(1));
    });
  });

  group('el acento en vivo', () {
    test('un evento de acento llega al acento, no al espejo', () async {
      // El evento no lleva `conversation`, y el espejo descarta lo que no lo lleva —
      // asi que sin este desvio el cambio se perderia en silencio, que es la peor
      // forma de perderse.
      enlace = montar();
      await conectado(enlace);
      final acentos = <int>[];
      final delEspejo = <Event>[];
      final s1 = enlace.acento.listen(acentos.add);
      final s2 = enlace.eventos.listen(delEspejo.add);
      addTearDown(s1.cancel);
      addTearDown(s2.cancel);

      socket.recibe(
        const Event(seq: 1, kind: 'accent', data: {'argb': 0xFF56E1EA}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(acentos, [0xFF56E1EA]);
      expect(
        delEspejo,
        isEmpty,
        reason: 'al espejo no le sirve: no es de ninguna conversacion',
      );
    });
  });
}

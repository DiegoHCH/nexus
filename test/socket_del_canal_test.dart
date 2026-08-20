import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/data/channel_server.dart';
import 'package:nexus/features/remote/domain/dispatcher.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus/features/remote/domain/gatekeeper.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

// El socket, probado **contra un socket de verdad**.
//
// No con dobles: estas reglas viven en las cabeceras de un upgrade de WebSocket y
// en los códigos de respuesta, y un doble de `HttpRequest` probaría mi idea de cómo
// funciona `dart:io`, no cómo funciona.
//
// Se levanta en `127.0.0.1`, que es justo la dirección que la política prohíbe en
// producción: el servidor escucha donde se le dice, y quién se lo dice es el
// proveedor —que solo tiene una de Tailscale o no arranca nada—. Esa separación es
// lo que hace esto probable.
void main() {
  late ChannelServer servidor;
  late List<String> anotado;

  const token = 'el-token-de-verdad';

  tearDown(() => servidor.stop());

  /// Levanta un servidor cuyo `Host` esperado ya coincide con su puerto.
  Future<ChannelServer> servidorListo({
    DateTime Function()? reloj,
    Dispatcher? despacho,
    Snapshot Function()? snapshot,
    EventLog? registroEventos,
  }) async {
    final registro = <String>[];
    // Se pide un puerto libre primero, se cierra, y se reusa: es la única forma de
    // saber el puerto antes de construir el portero que lo exige.
    final sonda = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final libre = sonda.port;
    await sonda.close();

    final s = ChannelServer(
      gatekeeper: Gatekeeper(
        token: token,
        hostEsperado: '127.0.0.1:$libre',
        reloj: reloj,
      ),
      log: registroEventos ?? EventLog(),
      despacho: despacho,
      snapshot: snapshot,
      registro: registro.add,
    );
    await s.start(direccion: InternetAddress.loopbackIPv4, puerto: libre);
    anotado = registro;
    return s;
  }

  Future<HttpClientResponse> pedir(
    ChannelServer s, {
    String? autorizacion = 'Bearer $token',
    String? origin,
    String? host,
  }) async {
    final cliente = HttpClient();
    final peticion = await cliente.get('127.0.0.1', s.puerto!, '/');
    if (autorizacion != null) {
      peticion.headers.set(HttpHeaders.authorizationHeader, autorizacion);
    }
    if (origin != null) peticion.headers.set('origin', origin);
    if (host != null) peticion.headers.set(HttpHeaders.hostHeader, host);
    final respuesta = await peticion.close();
    await respuesta.drain<void>();
    cliente.close();
    return respuesta;
  }

  group('quién entra y quién no', () {
    test('sin token: 403', () async {
      servidor = await servidorListo();
      final r = await pedir(servidor, autorizacion: null);
      expect(r.statusCode, HttpStatus.forbidden);
      expect(anotado.any((l) => l.contains('sinToken')), isTrue);
    });

    test('con el token equivocado: 403', () async {
      servidor = await servidorListo();
      final r = await pedir(servidor, autorizacion: 'Bearer otro');
      expect(r.statusCode, HttpStatus.forbidden);
      expect(anotado.any((l) => l.contains('tokenIncorrecto')), isTrue);
    });

    test('con Origin: 403, porque eso es un navegador', () async {
      servidor = await servidorListo();
      final r = await pedir(servidor, origin: 'https://cualquier-web.com');
      expect(r.statusCode, HttpStatus.forbidden);
      expect(anotado.any((l) => l.contains('desdeUnNavegador')), isTrue);
    });

    test('con otro Host: 403', () async {
      servidor = await servidorListo();
      final r = await pedir(servidor, host: 'evil.example.com');
      expect(r.statusCode, HttpStatus.forbidden);
      expect(anotado.any((l) => l.contains('hostAjeno')), isTrue);
    });

    test('todos los rechazos dan el mismo código y ningún cuerpo', () async {
      // A propósito: distinguirlos le diría a quien lo intenta qué comprobación
      // pasó, y eso solo le sirve a quien no debería estar ahí. El motivo va al
      // registro local, que es donde lo lee el dueño del Mac.
      servidor = await servidorListo();
      final codigos = <int>{};
      for (final r in [
        await pedir(servidor, autorizacion: null),
        await pedir(servidor, autorizacion: 'Bearer otro'),
        await pedir(servidor, origin: 'https://web.com'),
        await pedir(servidor, host: 'otro.com'),
      ]) {
        codigos.add(r.statusCode);
        expect(
          r.contentLength <= 0,
          isTrue,
          reason: 'sin cuerpo que dé pistas',
        );
      }
      expect(codigos, {
        HttpStatus.forbidden,
      }, reason: 'un solo código para todos');
    });

    test('el token también vale sin el prefijo Bearer', () async {
      // Exigirlo convertiría un cliente mal escrito en un «token incorrecto», que
      // manda a mirar al sitio equivocado.
      servidor = await servidorListo();
      final r = await pedir(servidor, autorizacion: token);
      expect(
        r.statusCode,
        HttpStatus.upgradeRequired,
        reason: 'pasó el portero; falla por no ser un WebSocket',
      );
    });

    test('autenticado pero sin upgrade: 426 y no 403', () async {
      servidor = await servidorListo();
      final r = await pedir(servidor);
      expect(r.statusCode, HttpStatus.upgradeRequired);
    });

    test('demasiados intentos: se cierra la puerta', () async {
      servidor = await servidorListo();
      for (var i = 0; i < 10; i++) {
        await pedir(servidor, autorizacion: 'Bearer mal-$i');
      }
      await pedir(servidor, autorizacion: 'Bearer mal-11');
      expect(anotado.any((l) => l.contains('demasiadosIntentos')), isTrue);
      // Y ni con el bueno.
      final r = await pedir(servidor);
      expect(r.statusCode, HttpStatus.forbidden);
    });
  });

  group('el saludo', () {
    Future<WebSocket> conectar(ChannelServer s) => WebSocket.connect(
      'ws://127.0.0.1:${s.puerto}/',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
    );

    test('con la misma versión, bienvenida con el seq', () async {
      servidor = await servidorListo();
      // Un par de eventos para que la numeración no sea cero.
      servidor.log
        ..emitir('a')
        ..emitir('b');

      final ws = await conectar(servidor);
      final recibido = Completer<Frame>();
      ws.listen((dynamic d) {
        if (!recibido.isCompleted) recibido.complete(Frame.decode(d as String));
      });

      ws.add(
        const Hello(
          protocol: ProtocolRange.mine,
          peer: Peer.mobile,
          appVersion: '0.0.8',
        ).encode(),
      );

      final respuesta = await recibido.future.timeout(
        const Duration(seconds: 5),
      );
      expect(respuesta, isA<Welcome>());
      expect(
        (respuesta as Welcome).seq,
        2,
        reason: 'la bienvenida dice por dónde va, para no pedir el snapshot',
      );
      await ws.close();
    });

    test('un cliente viejo recibe «actualízate tú», no un fallo raro', () async {
      servidor = await servidorListo();
      final ws = await conectar(servidor);
      final recibido = Completer<Frame>();
      ws.listen((dynamic d) {
        if (!recibido.isCompleted) recibido.complete(Frame.decode(d as String));
      });

      // Un cliente que solo habla una versión anterior al mínimo del servidor.
      ws.add(
        Hello(
          protocol: const ProtocolRange(
            min: ProtocolVersion(0),
            current: ProtocolVersion(0),
          ),
          peer: Peer.mobile,
          appVersion: '0.0.1',
        ).encode(),
      );

      final respuesta = await recibido.future.timeout(
        const Duration(seconds: 5),
      );
      expect(respuesta, isA<UpgradeRequired>());
      expect(
        (respuesta as UpgradeRequired).who,
        Peer.mobile,
        reason: 'le toca al móvil, y decírselo al otro sería inútil',
      );
      await ws.close();
    });

    test('si el primer mensaje no es un saludo, se cierra', () async {
      servidor = await servidorListo();
      final ws = await conectar(servidor);
      final cerrado = Completer<void>();
      ws.listen((_) {}, onDone: cerrado.complete);

      // Colarse pidiendo algo sin haber saludado.
      ws.add(const Call(id: '1', method: 'sendErrand').encode());

      await cerrado.future.timeout(const Duration(seconds: 5));
      expect(anotado.any((l) => l.contains('no era un saludo')), isTrue);
    });

    test('un mensaje roto no tira el servidor', () async {
      servidor = await servidorListo();
      final ws = await conectar(servidor);
      ws.add('esto no es json');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(servidor.escuchando, isTrue, reason: 'sigue en pie');
      expect(anotado.any((l) => l.contains('mensaje roto')), isTrue);
      await ws.close();
    });

    test('quien conecta aparece en la lista, y al irse desaparece', () async {
      // La lista de la decisión 2.7, empezada: saber quién está dentro.
      servidor = await servidorListo();
      final ws = await conectar(servidor);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(servidor.clientes, hasLength(1));

      await ws.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(servidor.clientes, isEmpty);
    });
  });

  test('parar cierra de verdad', () async {
    servidor = await servidorListo();
    final p = servidor.puerto!;
    await servidor.stop();
    expect(servidor.escuchando, isFalse);
    // Y el puerto queda libre: si no cerrara, esto lanzaría.
    final otro = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
    await otro.close();
  });
  group('las peticiones, por el cable de verdad', () {
    /// El saludo y la espera de la bienvenida, que es el punto de partida de
    /// cualquier petición.
    Future<(WebSocket, Stream<Frame>)> saludado(ChannelServer s) async {
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${s.puerto}/',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      final marcos = ws
          .map((dynamic d) => Frame.decode(d as String))
          .asBroadcastStream();
      final bienvenida = marcos.first;
      ws.add(
        const Hello(
          protocol: ProtocolRange.mine,
          peer: Peer.mobile,
          appVersion: '0.0.8',
        ).encode(),
      );
      await bienvenida.timeout(const Duration(seconds: 5));
      return (ws, marcos);
    }

    test('llega el ack y luego el resultado, en ese orden', () async {
      final app = _AppFalsa();
      servidor = await servidorListo(
        despacho: Dispatcher(
          surface: app,
          unlock: WriteUnlock(),
          phrases: _SinFrase(),
        ),
      );
      final (ws, marcos) = await saludado(servidor);

      final dos = marcos.take(2).toList();
      ws.add(const Call(id: 'p1', method: 'conversations').encode());
      final recibidos = await dos.timeout(const Duration(seconds: 5));

      // El orden **por el cable**, no solo dentro del despacho: es lo que hace que
      // el móvil sepa que su encargo llegó sin esperar a que termine.
      expect(recibidos.first, isA<Ack>());
      expect(recibidos.last, isA<Result>());
      expect(
        ((recibidos.last as Result).data['conversations']! as List),
        hasLength(1),
      );
      await ws.close();
    });

    test('sin despacho se contesta que no, en vez de callar', () async {
      // El caso de las pruebas del portero: servidor sin la app detrás. Un teléfono
      // esperando para siempre se lee como «el Mac no responde», y manda a buscar el
      // problema al sitio equivocado.
      servidor = await servidorListo();
      final (ws, marcos) = await saludado(servidor);

      final respuesta = marcos.first;
      ws.add(const Call(id: 'p1', method: 'conversations').encode());
      final marco = await respuesta.timeout(const Duration(seconds: 5));

      expect(marco, isA<Failure>());
      expect((marco as Failure).code, 'unavailable');
      await ws.close();
    });

    test('el registro anota el método y NUNCA los parámetros', () async {
      const secreta = 'abrete-sesamo-7';
      servidor = await servidorListo(
        despacho: Dispatcher(
          surface: _AppFalsa(),
          unlock: WriteUnlock(),
          phrases: _SinFrase(),
        ),
      );
      final (ws, marcos) = await saludado(servidor);

      final respuesta = marcos.take(2).toList();
      ws.add(
        const Call(
          id: 'p1',
          method: 'unlockWrites',
          params: {'phrase': secreta},
        ).encode(),
      );
      await respuesta.timeout(const Duration(seconds: 5));

      expect(
        anotado.any((l) => l.contains('unlockWrites')),
        isTrue,
        reason: 'saber qué se pidió es la mitad de poder depurarlo',
      );
      // Y la otra mitad es que el secreto no acabe escrito en el registro del
      // sistema, que es donde va a parar `debugPrint` en la app de verdad.
      for (final linea in anotado) {
        expect(linea, isNot(contains(secreta)));
      }
      await ws.close();
    });
  });

  group('los eventos y el resync', () {
    /// Saluda y devuelve el flujo de marcos posteriores a la bienvenida.
    Future<(WebSocket, Stream<Frame>)> conectado(ChannelServer s) async {
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${s.puerto}/',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      final marcos = ws
          .map((dynamic d) => Frame.decode(d as String))
          .asBroadcastStream();
      final bienvenida = marcos.first;
      ws.add(
        const Hello(
          protocol: ProtocolRange.mine,
          peer: Peer.mobile,
          appVersion: '0.0.8',
        ).encode(),
      );
      await bienvenida.timeout(const Duration(seconds: 5));
      return (ws, marcos);
    }

    test('un evento llega a quien ya saludó', () async {
      final log = EventLog();
      servidor = await servidorListo(registroEventos: log);
      final (ws, marcos) = await conectado(servidor);

      final siguiente = marcos.first;
      servidor.difundir(
        log.emitir('text', {'conversation': 'a', 'append': 'ya'}),
      );
      final marco = await siguiente.timeout(const Duration(seconds: 5));

      expect(marco, isA<Event>());
      expect((marco as Event).data['append'], 'ya');
      await ws.close();
    });

    test('a quien NO ha saludado no le llega nada', () async {
      // Un evento antes de la bienvenida iría a un cliente que todavía no sabe qué
      // versión se habla: es lo que convierte el handshake en papel mojado.
      final log = EventLog();
      servidor = await servidorListo(registroEventos: log);
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${servidor.puerto}/',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      final recibidos = <Frame>[];
      ws.listen((dynamic d) => recibidos.add(Frame.decode(d as String)));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      servidor.difundir(log.emitir('text', {'append': 'no deberías ver esto'}));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(recibidos, isEmpty);
      await ws.close();
    });

    test('«mándame desde el N» reenvía solo lo que falta', () async {
      final log = EventLog();
      for (var i = 0; i < 5; i++) {
        log.emitir('text', {'append': 'trozo $i'});
      }
      servidor = await servidorListo(registroEventos: log);
      final (ws, marcos) = await conectado(servidor);

      final dos = marcos.take(2).toList();
      ws.add(const Resume(lastSeq: 3).encode());
      final recibidos = await dos.timeout(const Duration(seconds: 5));

      // Dos y no cinco: en 4G esa es la diferencia entre barato y caro.
      expect(recibidos.map((f) => (f as Event).seq), [4, 5]);
      await ws.close();
    });

    test('pedir desde un seq que ya se tiró da el snapshot', () async {
      final log = EventLog(capacidad: 3);
      for (var i = 0; i < 10; i++) {
        log.emitir('text', {'append': 'trozo $i'});
      }
      servidor = await servidorListo(
        registroEventos: log,
        snapshot: () => Snapshot(seq: log.lastSeq, data: const {'todo': true}),
      );
      final (ws, marcos) = await conectado(servidor);

      final respuesta = marcos.first;
      // El 2 ya se tiró del búfer de tres.
      ws.add(const Resume(lastSeq: 2).encode());
      final marco = await respuesta.timeout(const Duration(seconds: 5));

      // Reenviar una lista incompleta sería peor que esto: el cliente se creería al
      // día con un hueco dentro.
      expect(marco, isA<Snapshot>());
      expect((marco as Snapshot).seq, 10);
      await ws.close();
    });

    test('sin snapshot que dar, se dice — no se calla', () async {
      final log = EventLog(capacidad: 2);
      for (var i = 0; i < 5; i++) {
        log.emitir('text', {'append': 'x'});
      }
      servidor = await servidorListo(registroEventos: log);
      final (ws, marcos) = await conectado(servidor);

      final respuesta = marcos.first;
      ws.add(const Resume(lastSeq: 1).encode());
      final marco = await respuesta.timeout(const Duration(seconds: 5));

      expect(marco, isA<Failure>());
      expect((marco as Failure).code, 'unavailable');
      await ws.close();
    });
  });
}

/// Lo mínimo para que el despacho tenga a quién preguntar. Lo de verdad se prueba
/// en `el_despacho_test.dart`, sin socket.
class _AppFalsa implements RemoteSurface {
  @override
  Future<List<RemoteConversation>> conversations() async => const [
    RemoteConversation(id: 'a', folder: '/tmp/uno', focused: true),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SinFrase implements WritePhraseStore {
  @override
  Future<WritePhrase?> read() async => null;
  @override
  Future<void> write(WritePhrase phrase) async {}
  @override
  Future<void> clear() async {}
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/data/channel_server.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
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
  Future<ChannelServer> servidorListo({DateTime Function()? reloj}) async {
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
      log: EventLog(),
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
        expect(r.contentLength <= 0, isTrue, reason: 'sin cuerpo que dé pistas');
      }
      expect(codigos, {HttpStatus.forbidden}, reason: 'un solo código para todos');
    });

    test('el token también vale sin el prefijo Bearer', () async {
      // Exigirlo convertiría un cliente mal escrito en un «token incorrecto», que
      // manda a mirar al sitio equivocado.
      servidor = await servidorListo();
      final r = await pedir(servidor, autorizacion: token);
      expect(r.statusCode, HttpStatus.upgradeRequired,
          reason: 'pasó el portero; falla por no ser un WebSocket');
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
      servidor.log..emitir('a')..emitir('b');

      final ws = await conectar(servidor);
      final recibido = Completer<Frame>();
      ws.listen((dynamic d) {
        if (!recibido.isCompleted) recibido.complete(Frame.decode(d as String));
      });

      ws.add(const Hello(
        protocol: ProtocolRange.mine,
        peer: Peer.mobile,
        appVersion: '0.0.8',
      ).encode());

      final respuesta = await recibido.future.timeout(const Duration(seconds: 5));
      expect(respuesta, isA<Welcome>());
      expect((respuesta as Welcome).seq, 2,
          reason: 'la bienvenida dice por dónde va, para no pedir el snapshot');
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
      ws.add(Hello(
        protocol: const ProtocolRange(
          min: ProtocolVersion(0),
          current: ProtocolVersion(0),
        ),
        peer: Peer.mobile,
        appVersion: '0.0.1',
      ).encode());

      final respuesta = await recibido.future.timeout(const Duration(seconds: 5));
      expect(respuesta, isA<UpgradeRequired>());
      expect((respuesta as UpgradeRequired).who, Peer.mobile,
          reason: 'le toca al móvil, y decírselo al otro sería inútil');
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
}

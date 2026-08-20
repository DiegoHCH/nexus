import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:test/test.dart';

// Los mensajes: que vayan y vuelvan iguales, y que **lo desconocido no rompa**.
//
// Esa segunda parte es la que sostiene todo lo demás. Si decodificar un mensaje
// que no se conoce lanzara, añadir un evento nuevo al servidor rompería a todos los
// teléfonos sin actualizar — y entonces cada añadido sería un cambio de versión, y
// nadie añadiría nada.
void main() {
  /// Codifica y decodifica de verdad, pasando por el texto: comparar objetos sin
  /// serializar no prueba nada del formato.
  T ida<T extends Frame>(Frame f) => Frame.decode(f.encode()) as T;

  group('van y vuelven', () {
    test('el saludo', () {
      const original = Hello(
        protocol: ProtocolRange.mine,
        peer: Peer.mobile,
        appVersion: '0.0.7',
      );
      final vuelta = ida<Hello>(original);
      expect(vuelta.protocol, ProtocolRange.mine);
      expect(vuelta.peer, Peer.mobile);
      expect(vuelta.appVersion, '0.0.7');
    });

    test('la bienvenida, con su seq', () {
      final vuelta = ida<Welcome>(
        const Welcome(protocol: ProtocolRange.mine, seq: 412),
      );
      expect(vuelta.seq, 412);
    });

    test('«actualízate», diciendo a quién le toca', () {
      final vuelta = ida<UpgradeRequired>(
        const UpgradeRequired(protocol: ProtocolRange.mine, who: Peer.desktop),
      );
      expect(vuelta.who, Peer.desktop);
    });

    test('una petición con su clientMsgId', () {
      final vuelta = ida<Call>(
        const Call(id: 'abc-123', method: 'sendErrand', params: {'texto': 'hola'}),
      );
      expect(vuelta.id, 'abc-123');
      expect(vuelta.known, RemoteMethod.sendErrand);
      expect(vuelta.params['texto'], 'hola');
    });

    test('la confirmación, y su marca de duplicado', () {
      expect(ida<Ack>(const Ack(id: 'x')).duplicate, isFalse);
      expect(ida<Ack>(const Ack(id: 'x', duplicate: true)).duplicate, isTrue);
    });

    test('un evento numerado', () {
      final vuelta = ida<Event>(
        const Event(seq: 7, kind: 'delta', data: {'t': 'texto'}),
      );
      expect(vuelta.seq, 7);
      expect(vuelta.kind, 'delta');
    });

    test('el resync y el snapshot', () {
      expect(ida<Resume>(const Resume(lastSeq: 99)).lastSeq, 99);
      expect(ida<Snapshot>(const Snapshot(seq: 100, data: {'a': 1})).seq, 100);
    });

    test('un fallo, con y sin petición detrás', () {
      expect(ida<Failure>(const Failure(code: 'nope', message: 'no')).id, isNull);
      expect(
        ida<Failure>(const Failure(code: 'nope', message: 'no', id: 'q')).id,
        'q',
      );
    });
  });

  group('lo que no se conoce no rompe', () {
    test('un tipo del futuro vuelve como desconocido', () {
      final f = Frame.decode('{"t":"telepatia","d":{"x":1}}');
      expect(f, isA<UnknownFrame>());
      expect((f as UnknownFrame).type, 'telepatia');
      // Y conserva el crudo, para poder registrar qué se está perdiendo.
      expect(f.raw['d'], {'x': 1});
    });

    test('un evento de una clase nueva se decodifica igual', () {
      // El caso concreto: el servidor empieza a mandar un evento que este cliente
      // no conoce. Tiene que llegar como evento y con su `seq`, porque **el seq
      // hay que respetarlo aunque el contenido no se entienda**: si se ignorara el
      // número, el cliente pediría resync desde un punto que ya pasó, para siempre.
      final f = Frame.decode('{"t":"event","seq":31,"k":"algo-nuevo"}');
      expect(f, isA<Event>());
      expect((f as Event).seq, 31);
      expect(f.kind, 'algo-nuevo');
    });

    test('un método que no existe llega como texto y no revienta', () {
      // El servidor tiene que poder **contestar un error** a un método que no
      // conoce. Si `Call` guardara un enum, decodificarlo lanzaría y el cliente se
      // quedaría esperando sin respuesta.
      final c = ida<Call>(const Call(id: '1', method: 'formatearElDisco'));
      expect(c.method, 'formatearElDisco');
      expect(c.known, isNull);
    });
  });

  group('lo roto sí se rechaza', () {
    test('lo que no es un objeto', () {
      expect(() => Frame.decode('42'), throwsFormatException);
      expect(() => Frame.decode('[]'), throwsFormatException);
    });

    test('lo que no trae tipo', () {
      // Un mensaje del futuro trae tipo y no se entiende; uno sin tipo está roto.
      // Son cosas distintas y no pueden tratarse igual.
      expect(() => Frame.decode('{"seq":1}'), throwsFormatException);
      expect(() => Frame.decode('{"t":3}'), throwsFormatException);
    });

    test('y lo que no es JSON', () {
      expect(() => Frame.decode('no soy json'), throwsFormatException);
    });
  });

  test('el token no viaja en el saludo', () {
    // La decisión 2.1: el token va en una cabecera del upgrade, nunca en un
    // mensaje, porque los mensajes acaban en trazas. Esto lo vigila: si alguien
    // añade el campo por comodidad, la prueba lo dice.
    const saludo = Hello(
      protocol: ProtocolRange.mine,
      peer: Peer.mobile,
      appVersion: '0.0.7',
    );
    final texto = saludo.encode().toLowerCase();
    for (final palabra in ['token', 'secret', 'auth', 'bearer']) {
      expect(
        texto.contains(palabra),
        isFalse,
        reason: 'el saludo lleva «$palabra»: el token no puede ir en un mensaje',
      );
    }
  });
}

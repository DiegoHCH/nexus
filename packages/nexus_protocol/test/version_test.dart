import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:test/test.dart';

// La negociación de versión, en los dos sentidos.
//
// Existe porque escritorio y móvil **se actualizan por su cuenta**: el escritorio
// solo desde la 0.0.2, el teléfono por la tienda. Sus versiones van a divergir
// siempre, y lo que no puede pasar es que esa divergencia se vea como «no
// responde».
void main() {
  const vieja = ProtocolRange(
    min: ProtocolVersion(1),
    current: ProtocolVersion(1),
  );
  const nueva = ProtocolRange(
    min: ProtocolVersion(2),
    current: ProtocolVersion(3),
  );

  test('con la misma versión se entienden', () {
    expect(
      negotiate(client: ProtocolRange.mine, server: ProtocolRange.mine),
      Negotiation.ok,
    );
  });

  test('un cliente por debajo del mínimo del servidor se actualiza', () {
    expect(
      negotiate(client: vieja, server: nueva),
      Negotiation.clientMustUpdate,
    );
  });

  test('y el caso simétrico, que es el que se olvida', () {
    // Pasa de verdad: la tienda empuja el móvil sin preguntar mientras el Mac
    // lleva semanas sin abrirse. Si solo se comprobara un sentido, el móvil diría
    // «no responde» sobre un Mac que contesta perfectamente en otro idioma.
    expect(
      negotiate(client: nueva, server: vieja),
      Negotiation.serverMustUpdate,
    );
  });

  test('se habla la más nueva que los dos entienden', () {
    const cliente = ProtocolRange(
      min: ProtocolVersion(1),
      current: ProtocolVersion(5),
    );
    const servidor = ProtocolRange(
      min: ProtocolVersion(1),
      current: ProtocolVersion(3),
    );
    expect(negotiate(client: cliente, server: servidor), Negotiation.ok);
    expect(agreed(client: cliente, server: servidor), const ProtocolVersion(3));
    // Y da igual quién sea el más nuevo.
    expect(agreed(client: servidor, server: cliente), const ProtocolVersion(3));
  });

  test('el rango va y vuelve por JSON', () {
    expect(ProtocolRange.fromJson(nueva.toJson()), nueva);
  });

  test('el mínimo no puede ser mayor que el actual', () {
    // No es una comprobación en tiempo de ejecución, es una de este paquete: un
    // rango invertido haría que nadie pudiera hablar con él, y el fallo se vería
    // como «actualiza» en los dos lados a la vez.
    expect(protocolMinimum <= protocolCurrent, isTrue);
  });
}

import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:test/test.dart';

// La pieza que evita que un encargo escriba dos veces en tus archivos.
//
// El escenario, que no es hipotético: el WebSocket cae después de que el escritorio
// recibió el encargo pero **antes** de confirmarlo. El móvil, que no sabe si llegó,
// lo reenvía. Sin deduplicación, `claude -p` con `acceptEdits` corre dos veces sobre
// los mismos archivos.
void main() {
  test('la primera vez se acepta y la segunda se reconoce', () {
    final d = Deduplicator(ttl: const Duration(minutes: 10));
    expect(d.aceptar('encargo-1'), isTrue, reason: 'la primera pasa');
    expect(d.aceptar('encargo-1'), isFalse, reason: 'el reenvío no vuelve a correr');
    // Y sigue reconociéndose: un `false` no lo olvida.
    expect(d.aceptar('encargo-1'), isFalse);
  });

  test('cada petición es la suya', () {
    final d = Deduplicator(ttl: const Duration(minutes: 10));
    expect(d.aceptar('a'), isTrue);
    expect(d.aceptar('b'), isTrue);
    expect(d.recordadas, 2);
  });

  test('pasado el plazo se olvida', () {
    // Con reloj inyectado, porque la caducidad **es** temporal: probarla con el
    // reloj de verdad significaría esperar diez minutos.
    var ahora = DateTime(2026, 8, 20, 10);
    final d = Deduplicator(ttl: const Duration(minutes: 10), reloj: () => ahora);

    expect(d.aceptar('viejo'), isTrue);
    ahora = ahora.add(const Duration(minutes: 11));
    expect(
      d.aceptar('viejo'),
      isTrue,
      reason: 'un id de hace once minutos ya no va a reenviarse, y recordarlo '
          'para siempre haría crecer la memoria sin tope',
    );
  });

  test('justo antes del plazo todavía se recuerda', () {
    // El borde por el lado que importa: olvidar demasiado pronto es ejecutar dos
    // veces, que es el fallo que esto viene a impedir.
    var ahora = DateTime(2026, 8, 20, 10);
    final d = Deduplicator(ttl: const Duration(minutes: 10), reloj: () => ahora);
    d.aceptar('x');
    ahora = ahora.add(const Duration(minutes: 9, seconds: 59));
    expect(d.aceptar('x'), isFalse);
  });

  test('lo que caduca deja de ocupar memoria', () {
    var ahora = DateTime(2026, 8, 20, 10);
    final d = Deduplicator(ttl: const Duration(minutes: 1), reloj: () => ahora);
    for (var i = 0; i < 50; i++) {
      d.aceptar('id-$i');
    }
    expect(d.recordadas, 50);
    ahora = ahora.add(const Duration(minutes: 2));
    expect(d.recordadas, 0, reason: 'un servidor que nunca olvida crece sin tope');
  });

  test('consultar no registra', () {
    final d = Deduplicator(ttl: const Duration(minutes: 10));
    expect(d.conocida('nunca-vista'), isFalse);
    expect(d.recordadas, 0, reason: 'preguntar no puede crear la entrada');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/el_audio_ajeno.dart';

/// Lo que suena alrededor y no iba dirigido a Nexus.
///
/// 🔴 **Pasó, dos corridas seguidas y con la transcripción delante.** El
/// micrófono recogió conversación de la habitación —«sí, porque el otro
/// muchacho fue el que hizo el servicio en el día»— el modelo la contestó, y el
/// servicio la tomó por una interrupción que cortó la frase a medias. Aquí se
/// prueba la regla que decide, con las frases de verdad.
void main() {
  group('mientras está hablando', () {
    bool ignora(String frase, {String? agente}) =>
        ElAudioAjeno.seIgnora(frase, estabaHablando: true, agente: agente);

    // Las dos que se transcribieron de verdad, tal cual salieron.
    test('la conversación de la habitación se tira', () {
      expect(
        ignora(
          'sí, porque el otro muchacho fue el que hizo el servicio en el día',
        ),
        isTrue,
      );
      expect(
        ignora('Ya usted ha visto la muchacha que empezó a trabajar conmigo'),
        isTrue,
      );
      expect(ignora('Dieguito. Señora. Le pido un favor…'), isTrue);
    });

    test('pero su nombre corta', () {
      expect(ignora('nexus, para'), isFalse);
      expect(ignora('oye Nexus, mira otra cosa'), isFalse);
      // Y el nombre que se le haya puesto en Ajustes, no solo el del producto.
      expect(ignora('Aurora, espera un momento', agente: 'Aurora'), isFalse);
      expect(
        ignora('aurora ¿esto qué es?', agente: 'Aurora'),
        isFalse,
        reason: 'sin signos y en minúsculas: la transcripción puntúa a su aire',
      );
    });

    test('y las palabras con las que se corta a alguien, también', () {
      for (final frase in [
        'para',
        'párate',
        'espera espera',
        'cállate',
        'repítelo',
        'stop',
        'wait',
        'never mind',
      ]) {
        expect(ignora(frase), isFalse, reason: '«$frase» tiene que cortar');
      }
    });

    // 🔴 La lista de cortar es **más corta** que la de cortesía a propósito: con
    // «hola» o «gracias» dentro, cualquier cortesía de fondo volvería a cortar
    // la respuesta, que es justo el fallo que esto cierra.
    test('la cortesía de fondo no corta', () {
      expect(ignora('hola'), isTrue);
      expect(ignora('gracias'), isTrue);
      expect(ignora('buenas tardes señora'), isTrue);
    });

    test('el silencio no se ignora ni se atiende: no es nada', () {
      expect(ignora('   '), isFalse);
      expect(ElAudioAjeno.interrumpe('  '), isFalse);
    });
  });

  // **En silencio no se filtra nada.** La sesión la abriste tú y lo primero que
  // dices va dirigido a ella por construcción; exigir el nombre en cada frase
  // convertiría una conversación en una lista de órdenes.
  test('callada, se atiende todo', () {
    for (final frase in [
      'sí, porque el otro muchacho fue el que hizo el servicio en el día',
      'mira el historial de git',
      'hola',
    ]) {
      expect(
        ElAudioAjeno.seIgnora(frase, estabaHablando: false),
        isFalse,
        reason: 'con Nexus callada, «$frase» se atiende como siempre',
      );
    }
  });
}

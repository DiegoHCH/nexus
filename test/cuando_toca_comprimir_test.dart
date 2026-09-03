import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/la_compresion_de_la_conversacion.dart';

/// Cuándo se comprime la conversación, y qué se cuenta después.
///
/// 🔴 **Las tres decisiones son caras de las dos maneras.** Comprimir de más
/// gasta un turno entero de Claude —un minuto largo— por nada. Comprimir de
/// menos deja que la ventana se llene y el contexto se recorte solo, sin que
/// nadie lo decida. Y contarlo mal es lo que producía «el contexto baja del
/// 132 % al 132 %», que además de no decir nada hacía dudar de si la compresión
/// había hecho algo.
void main() {
  group('cuándo toca', () {
    bool toca(int? contexto, {bool comprimiendo = false}) =>
        LaCompresionDeLaConversacion.toca(
          contexto: contexto,
          yaComprimiendo: comprimiendo,
        );

    test('por debajo del umbral no se toca nada', () {
      expect(toca(0), isFalse);
      expect(toca(84), isFalse);
    });

    test('desde el umbral, sí', () {
      expect(toca(LaCompresionDeLaConversacion.alPorCiento), isTrue);
      expect(toca(90), isTrue);
    });

    // La ventana puede pasarse del 100 %: el porcentaje se calcula contra la
    // que declara el modelo, y no es un tope duro.
    test('pasada la ventana, con más razón', () {
      expect(toca(132), isTrue);
    });

    // 🔴 La mitad de la decisión: `/compact` es un turno entero, y dispararlo
    // dos veces gasta dos.
    test('comprimiendo ya, no se dispara otra', () {
      expect(toca(95, comprimiendo: true), isFalse);
      expect(toca(132, comprimiendo: true), isFalse);
    });

    test('sin medida no se decide nada', () {
      expect(toca(null), isFalse);
      expect(toca(null, comprimiendo: true), isFalse);
    });
  });

  group('qué se cuenta después', () {
    LoQueDejoLaCompresion dejo(int antes, int? despues) =>
        LaCompresionDeLaConversacion.loQueDejo(antes: antes, despues: despues);

    test('con una medida nueva se cuenta la bajada entera', () {
      final r = dejo(90, 30) as BajoDe;

      expect(r.antes, 90);
      expect(r.despues, 30);
    });

    test('sin medida no se inventa una', () {
      expect(dejo(90, null), isA<SinMedidaTodavia>());
    });

    // 🔴 El caso que producía «baja del 132 % al 132 %». `copyWith` conserva el
    // valor anterior cuando le llega `null`, así que un número idéntico no
    // distingue «no se midió» de «no bajó» — y anunciar una bajada de X a X es
    // peor que no anunciarla.
    test('la misma medida es no haber medido, no una bajada de cero', () {
      expect(dejo(132, 132), isA<SinMedidaTodavia>());
      expect(dejo(90, 90), isA<SinMedidaTodavia>());
    });

    // Subir después de comprimir no debería pasar, pero si pasa se cuenta lo
    // que hay en vez de callarlo: un número raro delante es lo que hace que
    // alguien mire.
    test('una medida mayor se cuenta igual', () {
      final r = dejo(90, 95) as BajoDe;

      expect(r.despues, 95);
    });
  });
}

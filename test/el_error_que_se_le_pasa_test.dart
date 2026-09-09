import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/domain/usecases/el_error_que_se_le_pasa.dart';

/// **El error de la app, pasado a Claude de un toque.**
///
/// 🔴 Cierra un círculo que estaba medio construido: Nexus ya oye los errores
/// del framework y ya sabe llevar encargos a la carpeta de un proyecto, pero el
/// puente entre correr y encargar iba **en un solo sentido** —al terminar un
/// encargo se recarga la app, y al revés nada—. Así que un error se veía y
/// arreglarlo pasaba por copiar el bloque a mano, que es donde se pierde lo que
/// importa: medido dos días seguidos, con un `git push -u origin <rama>`
/// retranscrito como `git push` a secas y dos errores 128 distintos por la
/// misma causa.
///
/// Las líneas de aquí son las que salen de verdad: el bloque del framework por
/// el VM service y la excepción asíncrona del motor por stdout.
const _traza = [
  'flutter: arrancando',
  '✓ Built build/app.apk',
  '══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════',
  'The following StateError was thrown building StocksGate(dirty):',
  'Bad state: setState() called during build',
  'The relevant error-causing widget was:',
  '  StocksGate StocksGate:file:///repo/lib/stocks/gate.dart:78:12',
  'flutter: y sigue corriendo',
];

void main() {
  group('el último error, con lo que lo acompaña', () {
    test('se lleva la traza, que es lo que dice dónde mirar', () {
      final bloque = ElErrorQueSeLePasa.deLasLineas(_traza)!;

      expect(bloque, startsWith('══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY'));
      expect(bloque, contains('Bad state: setState() called during build'));
      expect(
        bloque,
        contains('gate.dart:78:12'),
        reason: 'sin el archivo y la línea, el bloque no dice dónde mirar',
      );
      // Lo de antes del error no viaja: no es del error.
      expect(bloque, isNot(contains('✓ Built')));
    });

    // De abajo arriba: lo que se quiere pasar es lo último que se rompió, no lo
    // primero que se rompió hace media hora.
    test('el último y no el primero', () {
      final bloque = ElErrorQueSeLePasa.deLasLineas([
        '[ERROR:flutter/x.cc(1)] Unhandled Exception: el viejo',
        'flutter: por medio',
        '[ERROR:flutter/x.cc(1)] Unhandled Exception: el nuevo',
        '#0      Algo.build (package:app/algo.dart:10:5)',
      ])!;

      expect(bloque, contains('el nuevo'));
      expect(bloque, isNot(contains('el viejo')));
      expect(bloque, contains('algo.dart:10:5'));
    });

    // Dos errores mezclados es pedirle a Claude que adivine cuál se arregla.
    test('para donde empieza otro error', () {
      final bloque = ElErrorQueSeLePasa.deLasLineas([
        '[ERROR:flutter/x.cc(1)] Unhandled Exception: el de arriba',
        'Another exception was thrown: el de abajo',
        'una línea más',
      ])!;

      expect(
        bloque,
        'Another exception was thrown: el de abajo\nuna línea más',
      );
    });

    // Esto entra en el prompt de un encargo, y el prompt se paga: una traza de
    // Flutter son cuarenta líneas y las diez primeras ya dicen dónde.
    test('y se corta en el tope, sin llevarse el framework entero', () {
      final bloque = ElErrorQueSeLePasa.deLasLineas([
        '[ERROR:flutter/x.cc(1)] Unhandled Exception: uno',
        for (var i = 0; i < 80; i++)
          '#$i      Framework.algo (package:f/f.dart)',
      ])!;

      expect(bloque.split('\n'), hasLength(ElErrorQueSeLePasa.tope));
    });

    test('sin errores en el registro, no hay nada que pasar', () {
      expect(
        ElErrorQueSeLePasa.deLasLineas(const [
          'flutter: todo bien',
          '✓ Built build/app.apk',
        ]),
        isNull,
      );
      expect(ElErrorQueSeLePasa.deLasLineas(const []), isNull);
    });
  });

  group('el encargo que se manda', () {
    test('la petición delante y el bloque literal detrás', () {
      final encargo = ElErrorQueSeLePasa.elEncargo(
        peticion: 'La app dejó este error corriendo con «ci» en emulator-5554.',
        bloque: 'Bad state: algo',
      );

      expect(encargo, startsWith('La app dejó este error'));
      expect(
        encargo,
        endsWith('Bad state: algo'),
        reason: 'el bloque va literal: resumirlo tira el archivo y la línea',
      );
      expect(
        encargo,
        contains('\n\n'),
        reason: 'separados, o la instrucción se lee como parte de la traza',
      );
    });
  });
}

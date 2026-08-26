import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';

/// Ver una prueba corriendo paso a paso.
///
/// El YAML y la salida de aquí tienen la forma de los de verdad: el flow con su
/// cabecera y sus comentarios —los de este repo llevan muchos— y la salida tal
/// como la escribe `maestro test --no-ansi`.
void main() {
  const flow = '''
# Humo: desde la bienvenida se llega al formulario de login.
#
# Va por `id` y no por texto visible a propósito.
appId: com.ejemplo.app
env:
  USUARIO: ""
---
- launchApp

# Un comentario en medio.
- extendedWaitUntil:
    visible:
      id: "btn_uno"
    timeout: 40000

- assertVisible:
    id: "btn_dos"
- tapOn:
    id: "btn_dos"
- takeScreenshot: final
''';

  group('leer los pasos de un flow', () {
    test('salen los cinco, y ni la cabecera ni los comentarios', () {
      final pasos = PasosDeUnaPrueba.leer(flow);

      expect(pasos.length, 5);
      expect(pasos.first, 'launchApp');
      expect(pasos.last, 'takeScreenshot: final');
      // `appId` y `env` van antes del `---` y no son ejecutables.
      expect(pasos.join(' '), isNot(contains('appId')));
    });

    test('un guion indentado es un argumento, no otro paso', () {
      // El `- ` de una lista dentro de un paso —los `tags`, por ejemplo— no es un
      // paso más. Contarlo desalinearía todo lo que viene detrás.
      const conLista = '''
appId: x
---
- launchApp
- assertVisible:
    text: "hola"
    optional: false
''';
      expect(PasosDeUnaPrueba.leer(conLista).length, 2);
    });

    test('sin separador no hay pasos', () {
      expect(PasosDeUnaPrueba.leer('appId: x\n'), isEmpty);
      expect(PasosDeUnaPrueba.leer(''), isEmpty);
    });
  });

  group('cuánto ha avanzado', () {
    // La salida real de `maestro test --no-ansi`.
    const salida = [
      'Running on Medium_Phone_API_36.1',
      ' > Flow welcome_to_login',
      'Launch app "com.ejemplo.app"... COMPLETED',
      'Assert that id: btn_uno is visible... COMPLETED',
    ];

    test('las cabeceras no cuentan como pasos', () {
      // «Running on…» y « > Flow…» no terminan en COMPLETED, así que no cuentan.
      final a = PasosDeUnaPrueba.avance(salida);
      expect(a.terminados, 2);
      expect(a.fallo, isFalse);
    });

    test('un paso fallado cuenta y se marca', () {
      final a = PasosDeUnaPrueba.avance([
        ...salida,
        'Tap on id: btn_dos... FAILED',
      ]);
      expect(a.terminados, 3);
      expect(a.fallo, isTrue);
    });
  });

  group('el estado de cada paso', () {
    test('lo hecho, lo que corre y lo que espera', () {
      // **Una línea solo aparece cuando el paso termina**, así que el que corre es
      // el siguiente al último impreso. De ahí sale el símbolo de «en curso» sin
      // preguntarle nada a nadie.
      final estados = PasosDeUnaPrueba.estados(
        cuantosPasos: 5,
        terminados: 2,
        viva: true,
        fallo: false,
      );

      expect(estados, [
        EstadoDePaso.hecho,
        EstadoDePaso.hecho,
        EstadoDePaso.enCurso,
        EstadoDePaso.pendiente,
        EstadoDePaso.pendiente,
      ]);
    });

    test('terminada y sin fallo, todo hecho y nada en curso', () {
      final estados = PasosDeUnaPrueba.estados(
        cuantosPasos: 3,
        terminados: 3,
        viva: false,
        fallo: false,
      );
      expect(estados, everyElement(EstadoDePaso.hecho));
    });

    test('el que falló se marca, y no se marca como hecho', () {
      final estados = PasosDeUnaPrueba.estados(
        cuantosPasos: 4,
        terminados: 3,
        viva: false,
        fallo: true,
      );

      expect(estados, [
        EstadoDePaso.hecho,
        EstadoDePaso.hecho,
        EstadoDePaso.fallado,
        // Lo que venía detrás no se ejecutó.
        EstadoDePaso.pendiente,
      ]);
    });

    test('**más pasos impresos que líneas: se rinde en vez de mentir**', () {
      // Pasa con `runFlow` y con los bucles, donde lo ejecutado no son las líneas
      // del archivo. Devolver algo ahí pintaría un estado inventado.
      expect(
        PasosDeUnaPrueba.estados(
          cuantosPasos: 3,
          terminados: 7,
          viva: true,
          fallo: false,
        ),
        isNull,
      );
    });

    test('sin empezar, todo pendiente y el primero en curso', () {
      final estados = PasosDeUnaPrueba.estados(
        cuantosPasos: 2,
        terminados: 0,
        viva: true,
        fallo: false,
      );
      expect(estados!.first, EstadoDePaso.enCurso);
      expect(estados.last, EstadoDePaso.pendiente);
    });
  });
}

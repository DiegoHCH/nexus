import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';
import 'package:nexus/features/assistant/domain/usecases/claude_errand.dart';
import 'package:nexus/features/e2e/domain/usecases/la_prueba_que_se_pide.dart';

/// De «corre el login» al archivo `login.yaml`.
///
/// Es el trozo que decide de la herramienta nueva, y el único con criterio: lo
/// demás —lanzar— ya existía. Adivinar mal aquí no da un error, da **una prueba
/// distinta corriendo delante de todos**, que es el peor final posible para la
/// demo que esta herramienta viene a asegurar.

void main() {
  const suite = ['login', 'login-fallido', 'checkout', 'alta_de_usuario'];

  group('lo que se quita de lo que se oye', () {
    test('la forma de pedirlo no es el nombre', () {
      for (final dicho in [
        'corre el login',
        'lanza la prueba de login',
        'ejecuta el flow login',
        'el test de login',
        'LOGIN',
        '  login  ',
      ]) {
        expect(
          LaPruebaQueSePide.cual(dicho, suite),
          isA<LaPruebaEs>().having((r) => r.flow, 'flow', 'login'),
          reason: '«$dicho» tenía que llevar a login',
        );
      }
    });

    // El reconocimiento de voz pone tildes y los nombres de archivo no las
    // llevan; y un `alta_de_usuario` se dice «alta de usuario».
    test('ni las tildes ni los guiones', () {
      expect(
        LaPruebaQueSePide.cual('corre el alta de usuario', suite),
        isA<LaPruebaEs>().having((r) => r.flow, 'flow', 'alta_de_usuario'),
      );
      expect(LaPruebaQueSePide.nucleo('Añadir Ítem'), 'anadir item');
    });
  });

  group('cuando encaja en varias', () {
    // La regla que evita el desastre: `login` está dentro de `login-fallido`,
    // así que «corre el login» encaja en dos. Lo exacto gana a lo parecido.
    test('lo exacto gana a lo que solo contiene', () {
      expect(
        LaPruebaQueSePide.cual('login', suite),
        isA<LaPruebaEs>().having((r) => r.flow, 'flow', 'login'),
      );
    });

    // Un trozo que solo vale para una sí lanza: nadie dice el nombre entero de
    // `login-fallido`, dice «el fallido», y pedir confirmación de algo que no
    // tiene alternativa es hacer perder un turno.
    test('un trozo que solo vale para una, lanza', () {
      expect(
        LaPruebaQueSePide.cual('el fallido', suite),
        isA<LaPruebaEs>().having((r) => r.flow, 'flow', 'login-fallido'),
      );
    });

    test('dos que empiezan igual se ofrecen las dos', () {
      final cual = LaPruebaQueSePide.cual('log', suite);

      expect(cual, isA<VariasSeParecen>());
      expect((cual as VariasSeParecen).flows, ['login', 'login-fallido']);
    });
  });

  group('cuando no encaja en ninguna', () {
    test('se dicen las que hay, no solo que no está', () {
      final cual = LaPruebaQueSePide.cual('el de los pagos', suite);

      expect(cual, isA<NingunaSeParece>());
      // Quien lo pidió acaba de decir un nombre parecido al bueno: oír la lista
      // es lo que le deja acertar a la segunda.
      expect((cual as NingunaSeParece).hay, suite);
    });

    test('un proyecto sin pruebas también contesta', () {
      expect(LaPruebaQueSePide.cual('login', const []), isA<NingunaSeParece>());
    });

    test('y una frase que no dice ningún nombre, igual', () {
      // «corre la prueba» es todo relleno: no queda núcleo con el que buscar.
      expect(
        LaPruebaQueSePide.cual('corre la prueba', suite),
        isA<NingunaSeParece>(),
      );
    });
  });

  group('la herramienta llega hasta el modelo', () {
    // Los tres nombres tienen que ser el mismo texto en los tres sitios: el que
    // se declara, el que se reconoce y el de la constante. Con dos de tres, la
    // herramienta existe para el modelo y no la atiende nadie.
    test('el nombre que se declara es el que se reconoce', () {
      expect(GeminiVoiceGateway.testToolName, ClaudeErrand.testTool);
    });

    test('está declarada, y dice que no hace falta escritura', () {
      final fuente = File(
        'lib/features/assistant/data/repositories/gemini_voice_gateway.dart',
      ).readAsStringSync();
      final declaracion = fuente.substring(fuente.indexOf('testToolName,'));

      expect(declaracion, contains('solo lectura'));
      expect(
        declaracion,
        contains('en vez de'),
        reason:
            'sin decirle que la use en vez de pedírselo a Claude, el modelo '
            'seguirá usando la de siempre y esto no habrá servido de nada',
      );
    });

    // La de forma: `forTool` no la conoce a propósito —no produce un encargo
    // para Claude— y quien la atiende es la conversación. Si alguien la añade
    // ahí, acabaría yendo a Claude y volverían los tres eslabones.
    test('no produce un encargo para Claude', () {
      expect(
        ClaudeErrand.forTool(ClaudeErrand.testTool, const {'prueba': 'login'}),
        isNull,
      );
    });
  });
}

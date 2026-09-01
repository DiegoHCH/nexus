import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/domain/entities/los_nombres.dart';

/// Cómo se llama quien contesta y cómo te llama a ti.
///
/// Lo que se prueba es la frontera entre «no lo he dicho» y «lo he dicho en
/// blanco», que es donde esto se rompe: una cadena vacía tratada como nombre
/// produce un prompt que pide llamar a alguien por un nombre que no existe, y un
/// aviso que empieza con una coma suelta.
void main() {
  group('la etiqueta sobre sus respuestas', () {
    test('sin nombre elegido, la de la app', () {
      expect(const LosNombres().etiqueta('NEXUS'), 'NEXUS');
    });

    test('con nombre, el elegido y en mayúsculas como el resto', () {
      expect(
        const LosNombres(agente: 'Patricia').etiqueta('NEXUS'),
        'PATRICIA',
      );
    });

    test('y un nombre en blanco no borra la etiqueta', () {
      expect(const LosNombres(agente: '').etiqueta('NEXUS'), 'NEXUS');
    });
  });

  group('lo que se le añade al prompt', () {
    test('sin nada dicho, no se añade nada', () {
      expect(const LosNombres().paraElPrompt(), isNull);
    });

    test('tu nombre, para que te llame', () {
      final prompt = const LosNombres(tuyo: 'Diego').paraElPrompt();

      expect(prompt, contains('Diego'));
      // 🔴 Se le pide que no lo fuerce: un nombre en cada frase se lee como un
      // vendedor, no como alguien que te conoce.
      expect(prompt, contains('sin forzarlo'));
    });

    test('y el suyo, para que sepa que le hablas a él', () {
      final prompt = const LosNombres(agente: 'Patricia').paraElPrompt();

      expect(prompt, contains('Patricia'));
      expect(prompt, contains('es a ti'));
    });

    test('los dos juntos, en dos líneas', () {
      final prompt = const LosNombres(
        agente: 'Patricia',
        tuyo: 'Diego',
      ).paraElPrompt();

      expect(prompt!.split('\n'), hasLength(2));
    });

    // Vacíos no cuentan: pedirle que llame a alguien por un nombre en blanco es
    // pedirle una tontería, y las tonterías en un prompt se obedecen.
    test('los vacíos no llegan al prompt', () {
      expect(const LosNombres(agente: '', tuyo: '').paraElPrompt(), isNull);
    });
  });

  group('el vocativo del aviso hablado', () {
    test('con nombre, el nombre y su coma', () {
      expect(const LosNombres(tuyo: 'Diego').vocativo, 'Diego, ');
    });

    // 🔴 Vacío y no `null`: quien compone el aviso lo concatena sin preguntar, y
    // una cadena vacía no deja una coma suelta al principio de la frase.
    test('sin nombre, nada — y no una coma huérfana', () {
      expect(const LosNombres().vocativo, '');
      expect(const LosNombres(tuyo: '').vocativo, '');
    });
  });

  test('hayAlgo distingue configurado de virgen', () {
    expect(const LosNombres().hayAlgo, isFalse);
    expect(const LosNombres(tuyo: 'Diego').hayAlgo, isTrue);
  });

  group('copyWith', () {
    // Se necesita poder **borrar** un nombre, así que `null` tiene que
    // distinguirse de «no lo toques». De ahí el centinela.
    test('un null explícito borra, y omitir conserva', () {
      const puestos = LosNombres(agente: 'Patricia', tuyo: 'Diego');

      expect(puestos.copyWith(agente: null).agente, isNull);
      expect(puestos.copyWith(agente: null).tuyo, 'Diego');
      expect(puestos.copyWith().agente, 'Patricia');
    });
  });
}

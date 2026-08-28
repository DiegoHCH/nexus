import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_vive_el_repo_de_pruebas.dart';

void main() {
  group('dónde vive el clon', () {
    test('cuelga de la carpeta de soporte, con el slug aplanado', () {
      expect(
        DondeViveElRepoDePruebas.de(
          soporte: '/Users/x/Library/Application Support/nexus',
          slug: 'global66/automated-test',
        ),
        '/Users/x/Library/Application Support/nexus/repos/global66--automated-test',
      );
    });

    test('la url de clonado va por https, que es lo que gh ya autentica', () {
      expect(
        DondeViveElRepoDePruebas.urlDe('global66/automated-test'),
        'https://github.com/global66/automated-test.git',
      );
    });

    test('los flows viven bajo flows/ dentro del clon', () {
      expect(DondeViveElRepoDePruebas.flowsEn('/tmp/clon'), '/tmp/clon/flows');
    });
  });

  group('la rama de un cambio', () {
    final cuando = DateTime(2026, 8, 27, 16, 5);

    test('sale del nombre del flow, con fecha y hora', () {
      expect(
        DondeViveElRepoDePruebas.ramaPara(
          flow: 'flows/15-login-to-home-flow.yaml',
          cuando: cuando,
        ),
        'test/15-login-to-home-flow-202608271605',
      );
    });

    test('dos cambios el mismo día no chocan si cambia el minuto', () {
      final a = DondeViveElRepoDePruebas.ramaPara(flow: 'x.yaml', cuando: cuando);
      final b = DondeViveElRepoDePruebas.ramaPara(
        flow: 'x.yaml',
        cuando: cuando.add(const Duration(minutes: 1)),
      );
      expect(a, isNot(b));
    });

    test('un nombre con caracteres que git no acepta se limpia', () {
      expect(
        DondeViveElRepoDePruebas.ramaPara(
          flow: 'flows/con espacios y ñ~^:.yaml',
          cuando: cuando,
        ),
        'test/con-espacios-y-202608271605',
      );
    });

    test('un nombre que queda vacío no produce una rama sin nombre', () {
      expect(
        DondeViveElRepoDePruebas.ramaPara(flow: '~~~.yaml', cuando: cuando),
        'test/prueba-202608271605',
      );
    });
  });
}

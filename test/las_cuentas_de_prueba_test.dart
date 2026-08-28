import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/entities/cuenta_de_pruebas.dart';
import 'package:nexus/features/e2e/domain/usecases/las_cuentas_de_prueba.dart';

/// Las dos cuentas que declara `run.sh` del repo, con su mismo mapeo.
final _pe = CuentaDePruebas(
  clave: 'pe',
  tags: const {'pe', 'any'},
  descripcion: 'PEN verificada, sin Bre-B',
  variables: const {'EMAIL': 'a@b.c', 'PASSWORD': 'x', 'PIN_1': '1'},
);
final _co = CuentaDePruebas(
  clave: 'co',
  tags: const {'co'},
  descripcion: 'CO/PE con Bre-B y Smart Card',
);

String _flow(String tags) => 'appId: x\ntags:\n$tags---\n- launchApp';

void main() {
  group('elegir la cuenta de un flow', () {
    test('el flow pide una cuenta que existe', () {
      final cuenta = LasCuentasDePrueba.paraElFlow(
        contenido: _flow('  - acct-co\n'),
        cuentas: [_pe, _co],
      );
      expect(cuenta?.clave, 'co');
    });

    test('sin tags cae en la primera, que es la de por defecto', () {
      final cuenta = LasCuentasDePrueba.paraElFlow(
        contenido: 'appId: x\n---\n- launchApp',
        cuentas: [_pe, _co],
      );
      expect(cuenta?.clave, 'pe');
    });

    test('acct-any viaja con la de por defecto y no pide pasada propia', () {
      final cuenta = LasCuentasDePrueba.paraElFlow(
        contenido: _flow('  - acct-any\n'),
        cuentas: [_pe, _co],
      );
      expect(cuenta?.clave, 'pe');
    });

    test('una cuenta que no está NO cae en la de por defecto', () {
      // Correr el flow mexicano con la cuenta peruana no da un error: da un rojo
      // que parece una regresión. Es peor que no correr.
      final cuenta = LasCuentasDePrueba.paraElFlow(
        contenido: _flow('  - acct-mx\n'),
        cuentas: [_pe, _co],
      );
      expect(cuenta, isNull);
    });

    test('sin cuentas configuradas no hay nada que elegir', () {
      final cuenta = LasCuentasDePrueba.paraElFlow(
        contenido: _flow('  - acct-pe\n'),
        cuentas: const [],
      );
      expect(cuenta, isNull);
    });

    test('dice qué clave pide el flow y nadie cubre', () {
      final faltan = LasCuentasDePrueba.sinCubrir(
        contenido: _flow('  - acct-mx\n  - acct-co\n'),
        cuentas: [_pe, _co],
      );
      expect(faltan, {'mx'});
    });
  });

  group('repartir una pasada por cuenta', () {
    test('cada flow cae en la suya y los sueltos en la de por defecto', () {
      final reparto = LasCuentasDePrueba.repartir(
        flows: {
          'flows/15.yaml': _flow('  - acct-pe\n'),
          'flows/38.yaml': _flow('  - acct-co\n'),
          'flows/02.yaml': _flow('  - acct-any\n'),
          'flows/99.yaml': 'appId: x\n---\n- launchApp',
        },
        cuentas: [_pe, _co],
      );
      expect(reparto['pe'], ['flows/02.yaml', 'flows/15.yaml', 'flows/99.yaml']);
      expect(reparto['co'], ['flows/38.yaml']);
    });

    test('un flow sin cuenta que lo cubra no se cuela en la pasada de otra', () {
      final reparto = LasCuentasDePrueba.repartir(
        flows: {'flows/70.yaml': _flow('  - acct-mx\n')},
        cuentas: [_pe, _co],
      );
      expect(reparto['pe'], isEmpty);
      expect(reparto['co'], isEmpty);
    });
  });

  group('guardar y releer las cuentas', () {
    test('una vuelta completa conserva todo', () {
      final leidas = LasCuentasDePrueba.deJson(
        LasCuentasDePrueba.aJson([_pe, _co]),
      );
      expect(leidas.map((c) => c.clave), ['pe', 'co']);
      expect(leidas.first.tags, {'any', 'pe'});
      expect(leidas.first.variables['EMAIL'], 'a@b.c');
      expect(leidas.last.descripcion, 'CO/PE con Bre-B y Smart Card');
    });

    test('dos cuentas con la misma clave: gana la primera', () {
      final leidas = LasCuentasDePrueba.deJson([
        {'clave': 'pe', 'tags': ['pe'], 'variables': {'EMAIL': 'buena'}},
        {'clave': 'pe', 'tags': ['co'], 'variables': {'EMAIL': 'pisada'}},
      ]);
      expect(leidas, hasLength(1));
      expect(leidas.single.variables['EMAIL'], 'buena');
    });

    test('lo que no se entiende se ignora en vez de adivinarse', () {
      final leidas = LasCuentasDePrueba.deJson([
        'no soy una cuenta',
        {'sin': 'clave'},
        {'clave': '  '},
        {'clave': 'ok', 'tags': ['ok']},
      ]);
      expect(leidas.map((c) => c.clave), ['ok']);
    });

    test('dice qué claves le faltan, por nombre y nunca por valor', () {
      expect(_co.leFaltan(['EMAIL', 'PASSWORD']), ['EMAIL', 'PASSWORD']);
      expect(_pe.leFaltan(['EMAIL', 'PIN_2']), ['PIN_2']);
    });
  });
}

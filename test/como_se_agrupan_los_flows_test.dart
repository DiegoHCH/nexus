import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/como_se_agrupan_los_flows.dart';

/// El reparto real de `global66/automated-test`, en pequeño.
const _rutas = [
  'flows/01-login-error-flow.yaml',
  'flows/26-vaults-flow.yaml',
  'flows/34-vault-creation-flow.yaml',
  'flows/auth/00-login.yaml',
  'flows/commons/setup-authed.yaml',
  'flows/migration/android-prod/p2p-flow.yaml',
  'flows/migration/ios-prod/payin-flow.yaml',
];

const _piezas = {'flows/auth/00-login.yaml', 'flows/commons/setup-authed.yaml'};

void main() {
  group('repartir la lista', () {
    test('las que se lanzan van primero y las piezas al final', () {
      final grupos = ComoSeAgrupanLosFlows.repartir(
        rutas: _rutas,
        piezas: _piezas,
      );
      expect(grupos.first.clase, ClaseDeGrupo.pruebas);
      expect(grupos.first.total, 3);
      expect(grupos.last.clase, ClaseDeGrupo.piezas);
      expect(grupos.last.total, 2);
    });

    test('las carpetas salen por orden alfabético', () {
      final grupos = ComoSeAgrupanLosFlows.repartir(
        rutas: _rutas,
        piezas: _piezas,
      );
      final carpetas = [
        for (final g in grupos)
          if (g.clase == ClaseDeGrupo.carpeta) g.carpeta,
      ];
      expect(carpetas, ['migration/android-prod', 'migration/ios-prod']);
    });

    test('una pieza no se cuenta también como prueba de su carpeta', () {
      final grupos = ComoSeAgrupanLosFlows.repartir(
        rutas: _rutas,
        piezas: _piezas,
      );
      final carpetas = [
        for (final g in grupos)
          if (g.clase == ClaseDeGrupo.carpeta) g.carpeta,
      ];
      expect(carpetas, isNot(contains('auth')));
      expect(carpetas, isNot(contains('commons')));
    });

    test('un grupo vacío no se enseña', () {
      final grupos = ComoSeAgrupanLosFlows.repartir(
        rutas: const ['flows/01.yaml'],
        piezas: const {},
      );
      expect(grupos, hasLength(1));
      expect(grupos.single.clase, ClaseDeGrupo.pruebas);
    });
  });

  group('el filtro', () {
    test('deja pasar lo que casa y conserva el total', () {
      final grupos = ComoSeAgrupanLosFlows.repartir(
        rutas: _rutas,
        piezas: _piezas,
        filtro: 'vault',
      );
      final pruebas = grupos.firstWhere((g) => g.clase == ClaseDeGrupo.pruebas);
      expect(pruebas.rutas, hasLength(2));
      // El total no se filtra: es lo que permite decir «2 de 3» y saber que el
      // filtro se comió algo, en vez de un «2» que parece todo lo que hay.
      expect(pruebas.total, 3);
    });

    test('no distingue mayúsculas', () {
      final grupos = ComoSeAgrupanLosFlows.repartir(
        rutas: _rutas,
        piezas: _piezas,
        filtro: 'VAULT',
      );
      expect(grupos.first.rutas, hasLength(2));
    });

    test('un grupo sin coincidencias sigue estando, con cero', () {
      final grupos = ComoSeAgrupanLosFlows.repartir(
        rutas: _rutas,
        piezas: _piezas,
        filtro: 'vault',
      );
      final piezas = grupos.firstWhere((g) => g.clase == ClaseDeGrupo.piezas);
      expect(piezas.rutas, isEmpty);
      expect(piezas.total, 2);
    });
  });

  group('qué es una pieza', () {
    test('lo que otro incluye, con la ruta relativa resuelta', () {
      final piezas = ComoSeAgrupanLosFlows.piezasDe(
        referenciasPorFlow: {
          'flows/15-login.yaml': ['commons/setup-authed.yaml'],
          'flows/commons/setup-authed.yaml': ['../auth/00-login.yaml'],
        },
      );
      expect(piezas, {
        'flows/commons/setup-authed.yaml',
        'flows/auth/00-login.yaml',
      });
    });

    test('incluirse a sí mismo no te convierte en pieza', () {
      final piezas = ComoSeAgrupanLosFlows.piezasDe(
        referenciasPorFlow: {'flows/a.yaml': ['a.yaml']},
      );
      expect(piezas, isEmpty);
    });

    test('sin referencias no hay piezas', () {
      expect(
        ComoSeAgrupanLosFlows.piezasDe(referenciasPorFlow: const {}),
        isEmpty,
      );
    });
  });
}

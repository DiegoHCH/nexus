import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';

/// Monta el árbol que deja Maestro: `<salida>/.maestro/tests/<fecha>/<name>/`.
Directory _monta(List<(String fecha, List<String> flows)> pasadas) {
  final raiz = Directory.systemTemp.createTempSync('artefactos');
  for (final (fecha, flows) in pasadas) {
    for (final flow in flows) {
      Directory('${raiz.path}/.maestro/tests/$fecha/$flow/takeScreenshot')
          .createSync(recursive: true);
    }
  }
  return raiz;
}

void main() {
  const ds = E2eDataSource();

  test('🔴 la carpeta lleva el name: del YAML, no el del archivo', () {
    // 01-login-error-flow.yaml declara `name: Login Error Flow`. Buscando por el
    // nombre del archivo no se encontraba nada y las capturas no salían.
    final raiz = _monta([('2026-08-27_203911', ['Login Error Flow'])]);
    addTearDown(() => raiz.deleteSync(recursive: true));

    expect(
      ds.carpetaDeArtefactos(salida: raiz.path, flow: '01-login-error-flow'),
      endsWith('/2026-08-27_203911/Login Error Flow'),
    );
  });

  test('si el nombre coincide, se prefiere el exacto', () {
    final raiz = _monta([
      ('2026-08-27_120000', ['login', 'otro']),
    ]);
    addTearDown(() => raiz.deleteSync(recursive: true));

    expect(
      ds.carpetaDeArtefactos(salida: raiz.path, flow: 'login'),
      endsWith('/login'),
    );
  });

  test('con varias y ninguna que case, no se adivina', () {
    final raiz = _monta([
      ('2026-08-27_120000', ['Uno', 'Dos']),
    ]);
    addTearDown(() => raiz.deleteSync(recursive: true));

    expect(
      ds.carpetaDeArtefactos(salida: raiz.path, flow: 'no-esta'),
      isNull,
    );
  });

  test('gana la pasada más reciente por nombre de carpeta', () {
    final raiz = _monta([
      ('2026-08-27_100000', ['Login Error Flow']),
      ('2026-08-27_203911', ['Login Error Flow']),
    ]);
    addTearDown(() => raiz.deleteSync(recursive: true));

    expect(
      ds.carpetaDeArtefactos(salida: raiz.path, flow: '01-login-error-flow'),
      contains('203911'),
    );
  });

  test('sin salida de Maestro no hay carpeta', () {
    final raiz = Directory.systemTemp.createTempSync('vacio');
    addTearDown(() => raiz.deleteSync(recursive: true));

    expect(ds.carpetaDeArtefactos(salida: raiz.path, flow: 'x'), isNull);
  });
}

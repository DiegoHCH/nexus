import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ADD-03. El valor de subir el listón no está en subirlo: está en que **siga
/// subido**. Un modo estricto que alguien apaga el día que estorba deja el
/// repositorio donde estaba, y sin que nadie se entere.
///
/// Por eso esto es una prueba y no una nota en un README.

void main() {
  final opciones = File('analysis_options.yaml').readAsStringSync();
  final ci = File('.github/workflows/ci.yml').readAsStringSync();

  group('el listón del analizador', () {
    // Medidos por separado sobre las 48.000 líneas antes de activarlos:
    // `strict-casts` encontró seis cosas y `strict-raw-types` cinco — todas
    // reales, un `dynamic` colándose donde se esperaba un `bool` o un elemento
    // con tipo. `strict-inference` no encontró ninguna, y va puesto igual.
    test('los tres modos estrictos siguen puestos', () {
      for (final modo in [
        'strict-casts: true',
        'strict-raw-types: true',
        'strict-inference: true',
      ]) {
        expect(opciones, contains(modo), reason: modo);
      }
    });

    // Sin esto, la mitad de lo que dicen esos modos no para nada:
    // `strict-raw-types` avisa con severidad *info*, y un aviso que no rompe el
    // CI es un aviso que se acumula hasta que nadie los lee.
    test('y el CI los exige, no solo los enciende', () {
      expect(ci, contains('flutter analyze --fatal-infos'));
    });

    // El formato es el mismo problema con otra cara: 55 archivos habían quedado
    // sin formatear, y el precio no era la estética — era que cada rama que
    // tocara uno arrastrara cien líneas de reindentado ajeno al cambio.
    test('y el formato también se exige', () {
      expect(ci, contains('dart format --output=none --set-exit-if-changed'));
    });

    test('la cobertura se mide y se dice', () {
      expect(ci, contains('flutter test --coverage'));
      expect(
        ci,
        contains(r'$GITHUB_STEP_SUMMARY'),
        reason: 'medirla y no enseñarla es medirla para nadie',
      );
    });

    // El suelo va sobre `domain` y no sobre el total, y esa distinción es el
    // valor entero de tenerlo: un umbral global se contenta con pruebas de
    // widgets y baja solo con que alguien añada una pantalla grande. El agregado
    // está en 60 % y `domain` en 90 %.
    test('y hay un suelo, pero donde importa', () {
      expect(ci, contains(r'dominio = ($2 ~ /\/domain\//)'));
      expect(
        ci,
        contains('< 85'),
        reason: 'sin el corte, medir por capa es informar y nada más',
      );
      expect(
        ci,
        isNot(contains(r'if (100*c/t <')),
        reason:
            'un suelo sobre el total castigaría añadir una pantalla y premiaría '
            'probar widgets, que no es lo que se quiere de este número',
      );
    });
  });
}

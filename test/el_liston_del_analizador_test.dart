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
  final gate = File('scripts/gate.sh').readAsStringSync();
  final cobertura = File('scripts/cobertura.sh').readAsStringSync();

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
      // Vive en `scripts/cobertura.sh` desde que el gate local existe: el
      // cálculo lo corren los dos y así por definición dicen el mismo número.
      expect(cobertura, contains(r'dominio = ($2 ~ /\/domain\//)'));
      expect(
        cobertura,
        contains('< suelo'),
        reason: 'sin el corte, medir por capa es informar y nada más',
      );
      expect(
        cobertura,
        contains('SUELO:-85'),
        reason: 'el número, escrito y no supuesto',
      );
      expect(
        cobertura,
        isNot(contains(r'if (100*c/t <')),
        reason:
            'un suelo sobre el total castigaría añadir una pantalla y premiaría '
            'probar widgets, que no es lo que se quiere de este número',
      );
      // Y el CI lo corre, que es lo que lo convierte en un suelo y no en un
      // archivo con buenas intenciones.
      expect(ci, contains('scripts/cobertura.sh'));
    });
  });

  /// 🔴 **El gate local tiene que ser el del CI, paso por paso.** Existe porque
  /// no lo era: se corrían dos de memoria y los otros cuatro llegaban como
  /// sorpresa cinco minutos después de empujar — un PR rojo por formato, las 37
  /// pruebas del paquete del protocolo que no corría nadie, y un suelo de
  /// cobertura que solo se podía comprobar en el CI.
  ///
  /// Esto es una prueba y no una nota en el README por lo mismo que el listón:
  /// el día que el CI gane un paso, el gate se queda corto **en silencio**, y
  /// entonces vuelve a no ser el gate.
  group('el gate de casa', () {
    test('corre los mismos seis pasos que el CI', () {
      for (final paso in [
        'flutter pub get',
        'dart pub get',
        'flutter analyze --fatal-infos',
        'dart format --output=none --set-exit-if-changed lib test packages',
        'dart test',
        'flutter test --coverage',
        './scripts/cobertura.sh',
      ]) {
        expect(gate, contains(paso), reason: paso);
      }
    });

    // El orden **no es decorativo**: `flutter analyze` desde la raíz analiza
    // también `packages/`, así que sin resolver las dependencias del paquete
    // daba 98 errores de imports que no existen. Está escrito en el workflow
    // con su incidente, y aquí se fija.
    test('y en el orden que importa: el paquete antes del análisis', () {
      // Se comparan las **llamadas** y no el texto suelto: los comentarios de
      // arriba nombran los dos pasos para explicar por qué van así, y buscar
      // por nombre encontraría la explicación antes que la orden.
      expect(
        gate.indexOf('paso "dependencias del protocolo"'),
        allOf(greaterThan(-1), lessThan(gate.indexOf('paso "analyze'))),
      );
    });

    // Los corre todos y luego informa: antes de empujar hace falta saber
    // cuántos frentes hay abiertos, no el primero por orden.
    test('no para en el primer fallo, pero acaba en rojo', () {
      expect(gate, contains('RESULTADO DEL GATE'));
      expect(gate, contains('exit 1'));
    });
  });
}

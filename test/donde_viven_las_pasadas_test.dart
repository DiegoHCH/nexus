import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_pasadas.dart';

/// Dónde viven las pasadas y cómo se llaman sus archivos.
void main() {
  test('una carpeta por app, con su nombre legible', () {
    // **Legible y no la ruta entera.** Antes era `Users·diego·Workspace·tienda`,
    // que es exacto y no se puede leer; estos archivos los va a mirar alguien en
    // el Finder. La ruta completa va dentro de cada registro, así que dos
    // proyectos llamados igual comparten carpeta sin perder la atribución.
    expect(DondeVivenLasPasadas.carpetaDe('/Users/alguien/Workspace/tienda'), 'tienda');
    expect(DondeVivenLasPasadas.carpetaDe('/Users/alguien/tienda/'), 'tienda');
  });

  test('una ruta rara no deja archivos en la raíz', () {
    // Sin nombre, los registros caerían sueltos entre las carpetas de las apps.
    expect(DondeVivenLasPasadas.carpetaDe('/'), 'proyecto');
    expect(DondeVivenLasPasadas.carpetaDe(''), 'proyecto');
  });

  test('la carpeta de un proyecto cuelga de la raíz', () {
    expect(
      DondeVivenLasPasadas.de(raiz: '/casa/documentos/test', proyecto: '/x/tienda'),
      '/casa/documentos/test/tienda',
    );
  });

  test('**Maestro añade su propia estructura a la ruta que se le da**', () {
    // Comprobado contra el binario: con `--debug-output /tmp/x` no escribe en
    // `/tmp/x`, escribe en `/tmp/x/.maestro/tests/<fecha>/<flow>/`. Empieza por
    // punto, así que su ruido queda oculto en una carpeta que sí se mira.
    expect(DondeVivenLasPasadas.loQueAnadeMaestro, startsWith('.'));
  });

  group('el nombre del registro', () {
    test('lleva el flow y la hora, para poder leerlo', () {
      expect(
        DondeVivenLasPasadas.nombreDelRegistro(
          flow: 'welcome_to_login',
          cuando: DateTime(2026, 8, 26, 9, 35, 7),
        ),
        'welcome_to_login 2026-08-26 09h3507',
      );
    });

    test('**con `h` y no con dos puntos**', () {
      // macOS enseña un `:` en un nombre de archivo como `/`, así que «09:35»
      // aparecería como «09/35» y se leería como otra carpeta.
      final nombre = DondeVivenLasPasadas.nombreDelRegistro(
        flow: 'x',
        cuando: DateTime(2026, 1, 2, 3, 4, 5),
      );
      expect(nombre, isNot(contains(':')));
      expect(nombre, contains('03h04'));
      // Y con ceros delante, o el orden alfabético no coincide con el temporal.
      expect(nombre, contains('2026-01-02'));
    });
  });
}

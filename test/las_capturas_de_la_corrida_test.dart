import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/usecases/la_corrida_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';

/// Las capturas que deja una corrida.
///
/// **La carpeta la elige Maestro**: añade `.maestro/tests/<fecha_hora>/` dentro de
/// la ruta que le damos, así que no se sabe al lanzar y se busca al terminar.
///
/// Durante un tiempo creí que esa carpeta no se escribía cuando la corrida salía de
/// la app, y lo dejé escrito en un comentario como hecho medido. Era falso: la
/// buscaba en `~/.maestro/tests`, el sitio por defecto, que es justo el que deja de
/// usarse cuando se pasa `--debug-output`.
void main() {
  const ds = E2eDataSource();

  /// Un PNG mínimo de verdad: 1×1 transparente.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGMAAQAABQAB'
    'oR9lAAAAAElFTkSuQmCC',
  );

  late Directory salida;
  setUp(() => salida = Directory.systemTemp.createTempSync('capturas'));
  tearDown(() => salida.deleteSync(recursive: true));

  /// Monta lo que escribe Maestro dentro de nuestra ruta.
  String corridaDeMaestro(String fecha, String flow, {List<String> tomas = const []}) {
    final carpeta = Directory('${salida.path}/.maestro/tests/$fecha/$flow')
      ..createSync(recursive: true);
    File('${carpeta.path}/commands.json').writeAsStringSync('[]');
    if (tomas.isNotEmpty) {
      Directory('${carpeta.path}/takeScreenshot').createSync();
      for (final t in tomas) {
        File('${carpeta.path}/takeScreenshot/$t.png').writeAsBytesSync(png);
      }
    }
    return carpeta.path;
  }

  group('encontrar la carpeta', () {
    test('la de este flow, dentro de nuestra ruta', () {
      final esperada = corridaDeMaestro('2026-08-26_160821', 'login');

      expect(
        ds.carpetaDeArtefactos(salida: salida.path, flow: 'login'),
        esperada,
      );
    });

    test('con varias, la más reciente por el nombre que puso Maestro', () {
      corridaDeMaestro('2026-08-26_104140', 'login');
      final ultima = corridaDeMaestro('2026-08-26_160821', 'login');
      corridaDeMaestro('2026-08-26_124317', 'login');

      expect(
        ds.carpetaDeArtefactos(salida: salida.path, flow: 'login'),
        ultima,
      );
    });

    test('no se coge la de otro flow', () {
      corridaDeMaestro('2026-08-26_160821', 'otro_flow');

      expect(ds.carpetaDeArtefactos(salida: salida.path, flow: 'login'), isNull);
    });

    test('sin nada escrito todavía, null y no un error', () {
      expect(ds.carpetaDeArtefactos(salida: salida.path, flow: 'login'), isNull);
    });
  });

  group('leerlas', () {
    test('la clave es el nombre que dice el paso, sin extensión', () {
      // «Take screenshot login_form» ↔ `login_form.png`: casan sin heurística.
      final carpeta = corridaDeMaestro(
        '2026-08-26_160821',
        'login',
        tomas: ['login_form'],
      );

      final capturas = ds.capturasDe(carpeta);

      expect(capturas.keys, ['login_form']);
      expect(capturas['login_form'], startsWith('data:image/png;base64,'));
    });

    test('van embebidas, no por ruta', () {
      // El visor solo tiene permiso de lectura sobre la carpeta de la página: una
      // imagen referenciada fuera de ahí sería un hueco en blanco.
      final carpeta = corridaDeMaestro(
        '2026-08-26_160821',
        'login',
        tomas: ['login_form'],
      );

      // Ninguna ruta del disco dentro: la imagen viaja en la propia página.
      expect(
        ds.capturasDe(carpeta)['login_form'],
        isNot(contains(salida.path)),
      );
      expect(ds.capturasDe(carpeta)['login_form'], isNot(contains('.png')));
    });

    test('una corrida sin capturas no da nada', () {
      final carpeta = corridaDeMaestro('2026-08-26_160821', 'login');
      expect(ds.capturasDe(carpeta), isEmpty);
    });

    test('sin carpeta tampoco', () {
      expect(ds.capturasDe(null), isEmpty);
    });
  });

  group('pintarlas', () {
    const unaCaptura = {'login_form': 'data:image/png;base64,AAAA'};

    test('cada una va debajo del paso que la tomó', () {
      final html = LaCorridaComoHtml.escribe(
        flow: 'login',
        pasos: const [
          PasoParaPintar(texto: 'Launch app "com.x"', estado: EstadoDePaso.hecho),
          PasoParaPintar(
            texto: 'Take screenshot login_form',
            estado: EstadoDePaso.hecho,
          ),
        ],
        lineas: const [],
        terminados: 2,
        viva: false,
        fallo: false,
        capturas: unaCaptura,
      );

      // Dentro de la fila del paso que la tomó, no en un montón al final.
      final fila = html.substring(html.indexOf('Take screenshot login_form'));
      expect(fila, contains('<img class="toma" src="data:image/png;base64,AAAA"'));
    });

    test('un paso que no toma capturas no lleva ninguna', () {
      final html = LaCorridaComoHtml.escribe(
        flow: 'login',
        pasos: const [
          PasoParaPintar(texto: 'Launch app "com.x"', estado: EstadoDePaso.hecho),
        ],
        lineas: const [],
        terminados: 1,
        viva: false,
        fallo: false,
        capturas: unaCaptura,
      );

      expect(html, isNot(contains('<img')));
    });

    test('el paso del YAML no lleva captura: todavía no ha corrido', () {
      final html = LaCorridaComoHtml.escribe(
        flow: 'login',
        pasos: const [
          PasoParaPintar(
            texto: 'takeScreenshot: login_form',
            estado: EstadoDePaso.pendiente,
          ),
        ],
        lineas: const [],
        terminados: 0,
        viva: true,
        fallo: false,
        capturas: unaCaptura,
      );

      expect(html, isNot(contains('<img')));
    });

    test('sigue sin pedir nada a la red', () {
      final html = LaCorridaComoHtml.escribe(
        flow: 'login',
        pasos: const [
          PasoParaPintar(
            texto: 'Take screenshot login_form',
            estado: EstadoDePaso.hecho,
          ),
        ],
        lineas: const [],
        terminados: 1,
        viva: false,
        fallo: false,
        capturas: unaCaptura,
      );

      expect(html, isNot(contains('http')));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ESC-04, la parte que el informe dejó abierta.
///
/// Decía «empezar por esos dos» —`bytesDe` y los permisos MCP, cerrados en el
/// PR #144— «y el resto cuando se toquen por otro motivo». Esto no deshace esa
/// decisión: la sigue para las 65 comprobaciones de existencia, que son una
/// llamada al inodo y no recorren nada, y la rompe solo donde había un motivo
/// que el informe no tenía delante.
///
/// El motivo: **recorrer una carpeta no es comprobar un archivo**. Un `listSync`
/// bloquea el isolate que dibuja tanto tiempo como archivos haya dentro, y los
/// dos que quedaban fuera de un isolate estaban en caminos que se piden solos —
/// uno de ellos desde el teléfono.

void main() {
  String fuente(String ruta) => File(ruta).readAsStringSync();

  /// Lo que se mira es el código, sin comentarios: los que quedan nombran
  /// `listSync` para explicar por qué ya no está, y esa mención hay que
  /// conservarla.
  String codigo(String ruta) => File(
    ruta,
  ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

  group('los recorridos que se piden solos', () {
    // Esta lista la pide también el teléfono por el canal, así que recorrer la
    // carpeta y pedir la fecha de cada archivo de forma síncrona bloquea justo
    // cuando alguien abre los documentos.
    test('la carpeta de documentos se recorre cediendo', () {
      const ruta =
          'lib/features/artifacts/data/datasources/artifacts_data_source.dart';

      expect(codigo(ruta), isNot(contains('listSync')));
      expect(codigo(ruta), isNot(contains('statSync')));
      expect(fuente(ruta), contains('await for (final entry in dir.list('));
    });

    // El de skills baja cuatro niveles por un árbol de repositorio —salta `.git`
    // y `node_modules` justo porque son enormes— y además copia carpetas
    // enteras al instalar.
    test('el árbol de skills también', () {
      const ruta =
          'lib/features/superpowers/data/datasources/skills_data_source.dart';

      expect(codigo(ruta), isNot(contains('listSync')));
    });
  });

  // Donde sí es correcto, y por qué. Sin esto, la próxima vez que alguien
  // busque `listSync` para «arreglarlo» tocaría el único sitio que lo tiene
  // bien puesto.
  test('dentro de un isolate se queda síncrono, que es lo que toca', () {
    const ruta =
        'lib/features/stats/data/datasources/transcript_data_source.dart';
    final texto = fuente(ruta);

    expect(texto, contains('Isolate.run'));
    expect(
      texto,
      contains('listSync'),
      reason:
          'ahí dentro nada que ceder ayuda: el isolate existe para que ese '
          'trabajo no toque el hilo que dibuja, y 250 archivos leídos de uno en '
          'uno cediendo serían más lentos por nada',
    );
  });

  // La decisión del informe, escrita como prueba para que no se erosione por
  // los dos lados: ni volviendo a meter recorridos, ni convirtiendo las 65
  // comprobaciones de existencia en una migración que no aporta.
  test('comprobar si un archivo existe se queda como está', () {
    final cuantos = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .fold<int>(
          0,
          (total, f) =>
              total + 'existsSync('.allMatches(f.readAsStringSync()).length,
        );

    expect(
      cuantos,
      greaterThan(40),
      reason:
          'son una llamada al inodo, no un recorrido: convertirlas todas sería '
          'churn sin efecto medible, y el informe decía justamente eso',
    );
  });
}

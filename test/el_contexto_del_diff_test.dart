import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/el_diff_como_html.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// Cuánto se ve alrededor de un cambio.
///
/// `git diff` da **tres líneas** de contexto por defecto, y eso está pensado
/// para un parche que se aplica, no para una revisión que se lee: un cambio
/// dentro de un método largo llega sin la firma del método y quien lo mira no
/// sabe dónde está. Era literalmente la mitad del motivo por el que la guía
/// mandaba al terminal a revisar diffs.

void main() {
  test('el contexto por defecto no son las tres de git', () {
    expect(GitDataSource.contexto, greaterThanOrEqualTo(20));
    expect(
      GitDataSource.contextoEntero,
      greaterThan(GitDataSource.contexto * 100),
      reason:
          'no hay bandera de «entero» en git: se pide un número más grande que '
          'cualquier archivo razonable',
    );
  });

  test('la bandera llega al comando, y no se queda en la constante', () {
    final fuente = File(
      'lib/features/workspace/data/datasources/git_data_source.dart',
    ).readAsStringSync();

    expect(fuente, contains("'-U\$lineasDeContexto'"));
    expect(
      fuente,
      isNot(contains("_run(folderPath, ['diff', base])")),
      reason: 'sin la bandera, el contexto vuelve a ser el de fábrica',
    );
  });

  group('el panel ofrece los tres alcances', () {
    test('cada grupo es una entrada de la navegación', () {
      final html = ElDiffComoHtml.deGrupos([
        (
          titulo: 'Este encargo',
          diff: 'diff --git a/a.dart b/a.dart\n@@ -1,1 +1,1 @@\n-x\n+y\n',
          nuevos: const <String>[],
        ),
        (
          titulo: 'Con el archivo entero',
          diff: 'diff --git a/a.dart b/a.dart\n@@ -1,9 +1,9 @@\n-x\n+y\n',
          nuevos: const <String>[],
        ),
        (
          titulo: 'Todo lo no comiteado',
          diff: 'diff --git a/b.dart b/b.dart\n@@ -1,1 +1,1 @@\n-p\n+q\n',
          nuevos: const <String>[],
        ),
      ]);

      expect(html, contains('Este encargo'));
      expect(html, contains('Con el archivo entero'));
      expect(html, contains('Todo lo no comiteado'));
      // Numerados de corrido: es una sola navegación, no tres páginas.
      expect(html, contains('<section id="f2">'));
    });

    test('sin grupos no revienta, y lo dice', () {
      final html = ElDiffComoHtml.deGrupos(const []);
      expect(html, contains('no dejó ningún cambio'));
    });
  });
}

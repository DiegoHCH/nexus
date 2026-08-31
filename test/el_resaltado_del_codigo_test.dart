import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/el_resaltado_del_codigo.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';

/// Lo que decide de qué color sale cada línea de un bloque.
///
/// Se prueba la parte que puede equivocarse sola: qué se toma por un diff y qué
/// significa cada prefijo. El mapa de tokens no se prueba color por color —eso
/// es criterio visual y un test lo congelaría sin protegerlo— pero sí que las
/// gramáticas no revientan y que un lenguaje desconocido no pierde texto.
void main() {
  const colores = NexusColors.light;
  const base = TextStyle(fontSize: 12);

  /// Todo el texto de un árbol de spans, para comprobar que no se pierde nada.
  String todoElTexto(InlineSpan span) {
    final buffer = StringBuffer();
    span.visitChildren((hijo) {
      if (hijo is TextSpan) buffer.write(hijo.text ?? '');
      return true;
    });
    return buffer.toString();
  }

  group('qué se toma por un diff', () {
    test('una cabecera de diff de verdad', () {
      expect(
        ElResaltadoDelCodigo.pareceUnDiff('diff --git a/x.dart b/x.dart'),
        isTrue,
      );
      expect(ElResaltadoDelCodigo.pareceUnDiff('@@ -1,3 +1,4 @@'), isTrue);
      expect(ElResaltadoDelCodigo.pareceUnDiff('--- a/x.dart'), isTrue);
    });

    // 🔴 Lo que **no** se toma por un diff, y es la mitad que importa: una lista
    // con guiones, un YAML o un trozo de shell están llenos de líneas que
    // empiezan por `-` o `+`. Pintarlas de rojo por el prefijo sería la
    // adivinanza que estropea más de lo que arregla.
    test('una lista con guiones no lo es', () {
      expect(
        ElResaltadoDelCodigo.pareceUnDiff('- uno\\n- dos\\n- tres'),
        isFalse,
      );
    });

    test('ni un yaml', () {
      expect(
        ElResaltadoDelCodigo.pareceUnDiff('deps:\\n  - flutter\\n  - riverpod'),
        isFalse,
      );
    });

    test('ni un git status, que no tiene prefijos', () {
      expect(
        ElResaltadoDelCodigo.pareceUnDiff(
          'On branch main\\nChanges not staged for commit:',
        ),
        isFalse,
      );
    });
  });

  group('el lenguaje del cercado', () {
    test('sale de la clase que pone markdown', () {
      expect(ElResaltadoDelCodigo.lenguajeDe('language-dart'), 'dart');
      expect(ElResaltadoDelCodigo.lenguajeDe('foo language-yaml bar'), 'yaml');
    });

    test('y es nulo cuando el cercado venía pelado', () {
      expect(ElResaltadoDelCodigo.lenguajeDe(null), isNull);
      expect(ElResaltadoDelCodigo.lenguajeDe(''), isNull);
      expect(ElResaltadoDelCodigo.lenguajeDe('language-'), isNull);
      expect(ElResaltadoDelCodigo.lenguajeDe('otra-cosa'), isNull);
    });
  });

  group('no se pierde texto por el camino', () {
    // Lo que se pinta tiene que decir lo mismo que llegó, pase lo que pase con
    // la gramática: un resaltado que se come una línea es peor que ninguno.
    for (final caso in <({String nombre, String codigo, String? lenguaje})>[
      (
        nombre: 'dart de verdad',
        codigo: "void main() {\\n  print('hola'); // 42\\n}",
        lenguaje: 'dart',
      ),
      (
        nombre: 'un lenguaje que no existe',
        codigo: 'algo raro aquí',
        lenguaje: 'lenguaje-inventado-xyz',
      ),
      (nombre: 'sin lenguaje', codigo: 'texto pelado', lenguaje: null),
      (
        nombre: 'un diff',
        codigo: '@@ -1 +1 @@\\n-antes\\n+después',
        lenguaje: 'diff',
      ),
      (
        nombre: 'un diff sin que nadie lo diga',
        codigo: 'diff --git a/x b/x\\n-viejo\\n+nuevo',
        lenguaje: null,
      ),
    ]) {
      test(caso.nombre, () {
        final pintado = ElResaltadoDelCodigo.enSpans(
          caso.codigo,
          lenguaje: caso.lenguaje,
          colores: colores,
          base: base,
        );

        expect(todoElTexto(pintado), caso.codigo);
      });
    }
  });

  group('los colores de un diff', () {
    TextStyle? estiloDeLaLinea(String codigo, int cual) {
      final pintado = ElResaltadoDelCodigo.enSpans(
        codigo,
        lenguaje: 'diff',
        colores: colores,
        base: base,
      );
      return (pintado.children![cual] as TextSpan).style;
    }

    test('lo añadido y lo quitado, con los colores que ya significan eso', () {
      const diff = '@@ -1 +1 @@\n-antes\n+después';

      expect(estiloDeLaLinea(diff, 0)?.color, colores.accent);
      expect(estiloDeLaLinea(diff, 1)?.color, colores.err);
      expect(estiloDeLaLinea(diff, 2)?.color, colores.ok);
    });

    // 🔴 `+++` y `---` son cabecera, no contenido. Sin mirarlos antes que `+` y
    // `-`, cada archivo de un diff estrenaría una línea verde y otra roja que no
    // son cambios de nadie.
    test('las cabeceras de archivo no son un cambio', () {
      const diff = '--- a/x.dart\n+++ b/x.dart\n+de verdad';

      expect(estiloDeLaLinea(diff, 0)?.color, colores.mute);
      expect(estiloDeLaLinea(diff, 1)?.color, colores.mute);
      expect(estiloDeLaLinea(diff, 2)?.color, colores.ok);
    });
  });
}

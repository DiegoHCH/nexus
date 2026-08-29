import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/el_diff_como_html.dart';

/// El diff pintado para el visor de documentos.
///
/// Se reutiliza esa ventana porque ya está encerrada —sin red y **sin
/// JavaScript**—, y esa última parte manda sobre el diseño: el panel de
/// archivos y el cambio de contenido al elegir uno tienen que salir de HTML y
/// CSS, o no salen.

void main() {
  const dosArchivos = '''
diff --git a/lib/a.dart b/lib/a.dart
@@ -1,1 +1,1 @@
-vieja
+nueva
diff --git a/lib/muy/hondo/b.dart b/lib/muy/hondo/b.dart
@@ -1,0 +1,1 @@
+otra
''';

  group('el panel de archivos', () {
    test('lista los tocados, con su cuenta', () {
      final html = ElDiffComoHtml.de(
        diff: dosArchivos,
        nuevos: const [],
        titulo: 'Este encargo',
      );

      expect(html, contains('lib/a.dart'));
      expect(html, contains('+1'));
      expect(html, contains('−1'));
      // La ruta larga se recorta por la izquierda: lo que identifica un archivo
      // es su nombre, no las carpetas que tiene encima.
      expect(html, contains('…/hondo/b.dart'));
    });

    test('cada archivo es un destino, y elegirlo cambia el contenido', () {
      final html = ElDiffComoHtml.de(
        diff: dosArchivos,
        nuevos: const [],
        titulo: 'Este encargo',
      );

      expect(html, contains('href="#f0"'));
      expect(html, contains('<section id="f0">'));
      expect(html, contains('href="#f1"'));
      // Sin JavaScript: uno a la vez, el elegido, por `:target`.
      expect(html, contains('section{display:none}'));
      expect(html, contains('section:target{display:block}'));
    });

    // Sin esto la ventana se abre en blanco hasta que alguien pulsa algo, y una
    // ventana en blanco se lee como que no hubo cambios.
    test('sin elegir nada se enseña el primero', () {
      final html = ElDiffComoHtml.de(
        diff: dosArchivos,
        nuevos: const [],
        titulo: 'x',
      );
      expect(
        html,
        contains('body:not(:has(section:target)) section:first-of-type'),
      );
    });
  });

  group('los dos alcances', () {
    test('el segundo se ofrece como otro grupo, no en otra ventana', () {
      final html = ElDiffComoHtml.de(
        diff: dosArchivos,
        nuevos: const [],
        titulo: 'Este encargo',
        tambien: '''
diff --git a/lib/z.dart b/lib/z.dart
@@ -1,1 +1,1 @@
-antes
+ahora
''',
        tituloDeTambien: 'Todo lo no comiteado',
      );

      expect(html, contains('Este encargo'));
      expect(html, contains('Todo lo no comiteado'));
      expect(html, contains('lib/z.dart'));
      // Numerados de corrido entre los dos grupos: son la misma navegación.
      expect(html, contains('<section id="f2">'));
    });
  });

  group('que se lea como un diff y no como un desastre', () {
    // El fallo que tuvo la primera versión: la fila del `@@` llevaba `colspan`,
    // y con `table-layout: fixed` **el ancho de las columnas lo fija la primera
    // fila**. Era esa. Todo lo demás quedaba descuadrado detrás.
    test('los anchos los declara el colgroup, no la primera fila', () {
      final html = ElDiffComoHtml.de(
        diff: dosArchivos,
        nuevos: const [],
        titulo: 'x',
      );

      expect(html, contains('<colgroup>'));
      expect(html, contains('col.cn{width:52px}'));
    });

    // El segundo intento fue una tabla por tramo, para evitar el `colspan`. Era
    // peor: cada tabla calcula sus columnas por su cuenta, así que el divisor
    // central saltaba entre tramos del mismo archivo.
    test('un archivo es una sola tabla, para que el eje no salte', () {
      final html = ElDiffComoHtml.de(
        diff: '''
diff --git a/lib/a.dart b/lib/a.dart
@@ -1,1 +1,1 @@
-una
+otra
@@ -20,1 +20,1 @@
-tercera
+cuarta
''',
        nuevos: const [],
        titulo: 'x',
      );

      expect('<table>'.allMatches(html), hasLength(1));
      expect('class="tramo"'.allMatches(html), hasLength(2));
    });

    // Lo segundo que lo rompía: las líneas largas se partían en tres, así que
    // una fila medía tres alturas en un lado y una en el otro. Dos columnas a
    // distinta altura no son mejores que una.
    // Y partir las líneas largas resultó **no** ser el problema: dentro de una
    // tabla las dos celdas de una fila comparten altura, así que los dos lados
    // siguen enfrentados aunque uno ocupe tres renglones.
    test('las líneas largas se parten, sin descuadrar los lados', () {
      final html = ElDiffComoHtml.de(
        diff: dosArchivos,
        nuevos: const [],
        titulo: 'x',
      );
      expect(html, contains('white-space:pre-wrap'));
      expect(html, contains('table-layout:fixed'));
    });
  });

  group('los colores del código', () {
    String pintado(String linea) => ElDiffComoHtml.de(
      diff: 'diff --git a/x.dart b/x.dart\n@@ -1,1 +1,1 @@\n-x\n+$linea\n',
      nuevos: const [],
      titulo: 'x',
    );

    // Sin JavaScript en el visor, el coloreado tiene que venir hecho de aquí.
    test('las palabras reservadas, las cadenas y los comentarios', () {
      expect(pintado('final x = 1;'), contains('<i class="res">final</i>'));
      expect(pintado("var s = 'hola';"), contains(r'<i class="cad">'));
      expect(
        pintado('// una nota'),
        contains('<i class="com">// una nota</i>'),
      );
      expect(
        pintado('final x = Widget();'),
        contains('<i class="tip">Widget</i>'),
      );
    });

    test('y el escapado gana al coloreado', () {
      // Primero se escapa y luego se marca: al revés, una `<` del código
      // cerraría las etiquetas que acabamos de abrir.
      final html = pintado("const a = '<b>';");
      expect(html, contains('&lt;b&gt;'));
      expect(html, isNot(contains('<b>')));
    });

    test('una comilla sin cerrar no se come el resto del archivo', () {
      // En un diff pasa constantemente: media línea llega sin su contexto.
      final html = pintado("texto sin cerrar '");
      expect(html, contains('class="cad"'));
    });
  });

  group('lo que no se puede colar', () {
    // Lo que entra aquí es código que escribió otro, a veces un modelo. El
    // visor no ejecuta scripts, así que lo peor sería una página rota — pero
    // rota justo donde vienes a leer qué cambió.
    test('el código se escapa, no se interpreta', () {
      final html = ElDiffComoHtml.de(
        diff: '''
diff --git a/lib/x.dart b/lib/x.dart
@@ -1,1 +1,1 @@
-const viejo = 1;
+const nuevo = Text('<script>alert("x")</script>');
''',
        nuevos: const [],
        titulo: 'x',
      );

      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('un archivo nuevo se nombra aunque no tenga diff', () {
      final html = ElDiffComoHtml.de(
        diff: '',
        nuevos: const ['lib/nuevo.dart'],
        titulo: 'x',
      );

      expect(html, contains('lib/nuevo.dart'));
      expect(html, contains('nuevo'));
      // Y se dice por qué no hay nada que enseñar, en vez de dejar el panel en
      // blanco como si no hubiera pasado nada.
      expect(html, contains('Todavía no lo sigue git'));
    });

    test('sin nada que enseñar se dice, y no se abre una ventana muda', () {
      final html = ElDiffComoHtml.de(diff: '', nuevos: const [], titulo: 'x');
      expect(html, contains('no dejó ningún cambio'));
    });
  });
}

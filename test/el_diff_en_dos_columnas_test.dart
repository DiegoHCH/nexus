import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/el_diff_en_dos_columnas.dart';

/// De un diff unificado a dos columnas, como las enseña un editor.
///
/// Lo que se prueba aquí es **el apareo**, que es lo único con criterio: una
/// línea editada tiene que quedar a la misma altura por los dos lados. Si no,
/// dos columnas no son mejores que una — son dos sitios donde buscar.

void main() {
  const unaLineaCambiada = '''
diff --git a/lib/a.dart b/lib/a.dart
index 111..222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -10,3 +10,3 @@
 sin tocar
-lo de antes
+lo de ahora
 tampoco
''';

  test('una línea editada queda enfrentada, no en dos sitios', () {
    final archivos = ElDiffEnDosColumnas.de(unaLineaCambiada);

    expect(archivos, hasLength(1));
    expect(archivos.single.ruta, 'lib/a.dart');

    final cambio = archivos.single.filas.firstWhere(
      (f) => f.que == QuePaso.cambiada,
    );
    expect(cambio.izquierda, 'lo de antes');
    expect(cambio.derecha, 'lo de ahora');
  });

  test('los números de línea salen del tramo y avanzan solos', () {
    final filas = ElDiffEnDosColumnas.de(unaLineaCambiada).single.filas;
    final contexto = filas.where((f) => f.que == QuePaso.igual).toList();

    expect(contexto.first.numeroIzquierda, 10);
    expect(contexto.first.numeroDerecha, 10);
    // Después de una línea cambiada los dos lados siguen a la par.
    expect(contexto.last.numeroIzquierda, 12);
    expect(contexto.last.numeroDerecha, 12);
  });

  test('lo que solo entra deja hueco enfrente, y al revés', () {
    final archivos = ElDiffEnDosColumnas.de('''
diff --git a/lib/b.dart b/lib/b.dart
@@ -1,2 +1,3 @@
 uno
+dos y medio
 dos
''');
    final entra = archivos.single.filas.firstWhere(
      (f) => f.que == QuePaso.entra,
    );
    expect(entra.izquierda, isNull);
    expect(entra.derecha, 'dos y medio');
  });

  // El caso que decide si el apareo sirve: tres fuera, una dentro. Las tres
  // primeras no se pueden emparejar todas, así que una va enfrentada y las
  // otras dos quedan solas — que es lo que hace cualquier editor.
  test('rachas desiguales: se aparea lo que se puede y el resto va solo', () {
    final filas = ElDiffEnDosColumnas.de('''
diff --git a/lib/c.dart b/lib/c.dart
@@ -1,3 +1,1 @@
-una
-dos
-tres
+solo una
''').single.filas;

    expect(filas.where((f) => f.que == QuePaso.cambiada), hasLength(1));
    expect(filas.where((f) => f.que == QuePaso.sale), hasLength(2));

    // La primera fila de un archivo es siempre el `@@ … @@`, que sitúa y no es
    // código: lo que se mira es la primera de verdad.
    final primera = filas.firstWhere((f) => f.que != QuePaso.tramo);
    expect(primera.izquierda, 'una');
    expect(primera.derecha, 'solo una');
  });

  test('varios archivos se separan, con su cuenta de más y de menos', () {
    final archivos = ElDiffEnDosColumnas.de('''
diff --git a/lib/a.dart b/lib/a.dart
@@ -1,1 +1,1 @@
-vieja
+nueva
diff --git a/lib/b.dart b/lib/b.dart
@@ -1,0 +1,2 @@
+una
+otra
''');

    expect(archivos.map((a) => a.ruta), ['lib/a.dart', 'lib/b.dart']);
    expect(archivos.last.mas, 2);
    expect(archivos.last.menos, 0);
  });

  test('un diff vacío no da archivos, y no revienta', () {
    expect(ElDiffEnDosColumnas.de(''), isEmpty);
    expect(ElDiffEnDosColumnas.de('cualquier cosa\nsin cabecera'), isEmpty);
  });

  // Las cabeceras del archivo no son contenido. Colarlas desplazaría la
  // numeración de todo lo que va debajo, que es el error que hace desconfiar
  // de un visor de diffs para siempre.
  test('las cabeceras de git no cuentan como líneas', () {
    final filas = ElDiffEnDosColumnas.de('''
diff --git a/lib/d.dart b/lib/d.dart
new file mode 100644
index 000..111
--- /dev/null
+++ b/lib/d.dart
@@ -0,0 +1,1 @@
+la primera
''').single.filas;

    expect(filas.where((f) => f.que != QuePaso.tramo), hasLength(1));
    expect(filas.last.derecha, 'la primera');
  });
}

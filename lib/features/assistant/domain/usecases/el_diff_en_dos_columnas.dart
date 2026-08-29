/// De un diff unificado a dos columnas enfrentadas, como las enseña un editor.
///
/// El diff que da git es una lista de líneas con un signo delante. Se lee bien
/// cuando el cambio es pequeño y fatal en cuanto hay veinte líneas tocadas:
/// para saber **en qué se convirtió** una línea hay que buscarla más abajo y
/// aparearla a ojo. Dos columnas hacen ese apareo una vez y bien.
///
/// La regla del apareo es la que usa cualquier editor y no es obvia: dentro de
/// un tramo, una racha de líneas que salen se empareja **una a una** con la
/// racha de líneas que entran justo detrás. Si una racha es más larga, lo que
/// sobra queda enfrente de un hueco. Eso es lo que hace que una línea editada
/// se lea a la misma altura por los dos lados en vez de en dos sitios.
library;

/// Qué le pasó a una fila.
enum QuePaso {
  /// Igual por los dos lados.
  igual,

  /// Cambió: hay algo a la izquierda y algo distinto a la derecha.
  cambiada,

  /// Solo entra: la izquierda va vacía.
  entra,

  /// Solo sale: la derecha va vacía.
  sale,

  /// El encabezado de un tramo (`@@ … @@`). No es código: sitúa.
  tramo,
}

/// Una fila de la tabla: qué había, qué hay, y con qué números de línea.
typedef FilaDelDiff = ({
  QuePaso que,
  String? izquierda,
  String? derecha,
  int? numeroIzquierda,
  int? numeroDerecha,
});

/// Un archivo del diff, ya en filas.
typedef ArchivoDelDiff = ({
  String ruta,
  List<FilaDelDiff> filas,
  int mas,
  int menos,
});

abstract final class ElDiffEnDosColumnas {
  /// Parte un diff unificado en archivos y cada archivo en filas.
  static List<ArchivoDelDiff> de(String diff) {
    final archivos = <ArchivoDelDiff>[];
    String? ruta;
    var filas = <FilaDelDiff>[];
    var salen = <(String, int)>[];
    var entran = <(String, int)>[];
    var izquierda = 0;
    var derecha = 0;

    void volcarRachas() {
      for (var i = 0; i < salen.length || i < entran.length; i++) {
        final sale = i < salen.length ? salen[i] : null;
        final entra = i < entran.length ? entran[i] : null;
        filas.add((
          // Emparejadas es «cambiada»; sola por un lado es entrar o salir.
          que: sale != null && entra != null
              ? QuePaso.cambiada
              : (sale != null ? QuePaso.sale : QuePaso.entra),
          izquierda: sale?.$1,
          derecha: entra?.$1,
          numeroIzquierda: sale?.$2,
          numeroDerecha: entra?.$2,
        ));
      }
      salen = [];
      entran = [];
    }

    void cerrarArchivo() {
      volcarRachas();
      final cual = ruta;
      if (cual == null) return;
      archivos.add((
        ruta: cual,
        filas: filas,
        mas: filas
            .where((f) => f.derecha != null && f.que != QuePaso.igual)
            .length,
        // Sin las filas de tramo: el `@@ … @@` lleva texto en la izquierda, y
        // colarlo aquí sumaba una línea borrada por cada tramo del archivo.
        menos: filas
            .where(
              (f) =>
                  f.izquierda != null &&
                  f.que != QuePaso.igual &&
                  f.que != QuePaso.tramo,
            )
            .length,
      ));
      filas = [];
    }

    // El `split` de un texto que acaba en salto deja una cadena vacía al final,
    // y aquí una cadena vacía **es** una línea de contexto vacía. Sin quitarla
    // se cuela una fila de más y todo lo de debajo queda desnumerado.
    final lineas = diff.split('\n');
    while (lineas.isNotEmpty && lineas.last.isEmpty) {
      lineas.removeLast();
    }

    for (final linea in lineas) {
      if (linea.startsWith('diff --git ')) {
        cerrarArchivo();
        // `b/loquesea` es el nombre de después, que es el que interesa: si el
        // archivo se renombró, el nombre viejo ya no lleva a ningún sitio.
        final partes = linea.split(' b/');
        ruta = partes.length > 1 ? partes.last : linea;
        continue;
      }
      if (ruta == null) continue;
      // Las cabeceras del archivo no son contenido: modo, índice, ---/+++.
      if (linea.startsWith('index ') ||
          linea.startsWith('--- ') ||
          linea.startsWith('+++ ') ||
          linea.startsWith('new file') ||
          linea.startsWith('deleted file') ||
          linea.startsWith('similarity ') ||
          linea.startsWith('rename ') ||
          linea.startsWith('old mode') ||
          linea.startsWith('new mode')) {
        continue;
      }

      if (linea.startsWith('@@')) {
        volcarRachas();
        final numeros = _numerosDelTramo(linea);
        izquierda = numeros.$1;
        derecha = numeros.$2;
        filas.add((
          que: QuePaso.tramo,
          izquierda: linea,
          derecha: null,
          numeroIzquierda: null,
          numeroDerecha: null,
        ));
        continue;
      }

      if (linea.startsWith('-')) {
        salen.add((linea.substring(1), izquierda++));
      } else if (linea.startsWith('+')) {
        entran.add((linea.substring(1), derecha++));
      } else if (linea.startsWith(' ') || linea.isEmpty) {
        volcarRachas();
        final texto = linea.isEmpty ? '' : linea.substring(1);
        filas.add((
          que: QuePaso.igual,
          izquierda: texto,
          derecha: texto,
          numeroIzquierda: izquierda++,
          numeroDerecha: derecha++,
        ));
      }
      // Lo demás —`\ No newline at end of file`, binarios— se ignora: no es
      // una línea de código y colarla desplazaría la numeración.
    }
    cerrarArchivo();
    return archivos;
  }

  /// Los dos números de un `@@ -12,7 +12,9 @@`.
  static (int, int) _numerosDelTramo(String linea) {
    final marca = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
    final encontrado = marca.firstMatch(linea);
    if (encontrado == null) return (1, 1);
    return (int.parse(encontrado.group(1)!), int.parse(encontrado.group(2)!));
  }
}

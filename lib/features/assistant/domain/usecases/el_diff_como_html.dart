import 'package:nexus/features/assistant/domain/usecases/el_diff_en_dos_columnas.dart';

/// El diff, pintado para el visor de documentos.
///
/// **Se reutiliza esa ventana en vez de hacer una nueva**, y no por ahorrar: es
/// la que ya está encerrada —sin red, sin JavaScript y con su CSP inyectada— y
/// abrir código ajeno es exactamente el caso para el que se encerró. Una ventana
/// nueva empezaría otra vez esa conversación desde cero.
///
/// El precio de esa ventana es que **no hay JavaScript**, así que aquí no puede
/// haber pestañas ni plegados hechos a mano. Los dos alcances —lo de este
/// encargo y todo lo que no se ha comiteado— van en un `<details>`, que es
/// nativo del navegador y funciona sin una línea de script.
abstract final class ElDiffComoHtml {
  /// Un grupo del panel: un título y el diff que cuelga de él.
  ///
  /// Grupos y no una pareja de alcances porque acabaron siendo tres —lo de este
  /// encargo, lo mismo con el archivo entero alrededor, y todo lo que sigue sin
  /// comitear— y cada uno contesta una pregunta distinta: «¿qué acabo de
  /// pedir?», «¿y qué había alrededor?», «¿qué llevo hecho de esta tarea?».
  /// Cuál importa solo lo sabe quien mira, así que se ofrecen todos y no se
  /// elige por él.
  static String deGrupos(
    List<({String titulo, String diff, List<String> nuevos})> entradas,
  ) {
    final titulo = entradas.isEmpty ? 'Cambios' : entradas.first.titulo;
    final grupos = [
      for (final entrada in entradas)
        (
          titulo: entrada.titulo,
          archivos: ElDiffEnDosColumnas.de(entrada.diff),
          nuevos: entrada.nuevos,
        ),
    ];

    final lado = StringBuffer();
    final centro = StringBuffer();
    final seleccion = StringBuffer();
    var n = 0;

    for (final grupo in grupos) {
      lado.writeln('<p class="grupo">${_texto(grupo.titulo)}</p>');
      if (grupo.archivos.isEmpty && grupo.nuevos.isEmpty) {
        lado.writeln('<p class="nada">Sin cambios</p>');
      }
      for (final archivo in grupo.archivos) {
        final id = 'f$n';
        n++;
        lado.writeln(
          '<a href="#$id"><span class="ruta">${_texto(_corta(archivo.ruta))}</span>'
          '<span class="mas">+${archivo.mas}</span>'
          '<span class="menos">−${archivo.menos}</span></a>',
        );
        // El resaltado del archivo elegido, sin una línea de script: se pinta
        // el enlace cuyo destino es el que está seleccionado.
        seleccion.writeln(
          'body:has(#$id:target) a[href="#$id"]{'
          'background:var(--sel);color:var(--texto)}',
        );
        centro
          ..writeln('<section id="$id">')
          ..writeln('<h2>${_texto(archivo.ruta)}</h2>')
          ..writeln('<div class="codigo">')
          ..writeln(_cuerpo(archivo.filas))
          ..writeln('</div></section>');
      }
      for (final nuevo in grupo.nuevos) {
        final id = 'f$n';
        n++;
        lado.writeln(
          '<a href="#$id"><span class="ruta">${_texto(_corta(nuevo))}</span>'
          '<span class="nuevo">nuevo</span></a>',
        );
        seleccion.writeln(
          'body:has(#$id:target) a[href="#$id"]{'
          'background:var(--sel);color:var(--texto)}',
        );
        // Un archivo nuevo no tiene diff: git todavía no lo sigue. Se dice, en
        // vez de dejar el panel en blanco como si no hubiera pasado nada.
        centro.writeln(
          '<section id="$id"><h2>${_texto(nuevo)}</h2>'
          '<p class="nada">Archivo nuevo. Todavía no lo sigue git, así que no '
          'hay nada contra lo que compararlo.</p></section>',
        );
      }
    }

    if (n == 0) {
      centro.writeln('<p class="nada">Esta tarea no dejó ningún cambio.</p>');
    }

    return '<!doctype html><html lang="es"><head><meta charset="utf-8">'
        '<title>${_texto(titulo)}</title>'
        '<style>$_estilo$seleccion</style></head>'
        '<body><nav>$lado</nav><main>$centro</main></body></html>';
  }

  /// Las filas de un archivo, **en una sola tabla**.
  ///
  /// Dos intentos y dos fallos distintos, que conviene dejar escritos porque los
  /// dos parecían la solución del otro:
  ///
  /// 1. Una tabla con la línea del `@@` dentro y un `colspan`. Con
  ///    `table-layout: fixed` y sin `<colgroup>`, el ancho de las columnas lo
  ///    fija la **primera fila** — que era esa. Todo lo demás quedaba torcido.
  /// 2. Una tabla por tramo, para no usar `colspan`. Peor: cada tabla calcula
  ///    sus columnas por su cuenta, así que **el divisor central saltaba de un
  ///    tramo a otro** dentro del mismo archivo.
  ///
  /// Una tabla con `<colgroup>` arregla las dos: los anchos los declara el
  /// grupo de columnas y no la primera fila, así que el `colspan` del tramo deja
  /// de importar y todo el archivo comparte el mismo eje.
  static String _cuerpo(List<FilaDelDiff> filas) {
    final salida = StringBuffer(
      '<table><colgroup><col class="cn"><col class="cc">'
      '<col class="cn"><col class="cc"></colgroup><tbody>',
    );
    for (final fila in filas) {
      if (fila.que == QuePaso.tramo) {
        salida.writeln(
          '<tr class="tramo"><td colspan="4">'
          '${_texto(fila.izquierda ?? '')}</td></tr>',
        );
        continue;
      }
      salida.writeln(_fila(fila));
    }
    return (salida..write('</tbody></table>')).toString();
  }

  static String _fila(FilaDelDiff fila) {
    final clase = switch (fila.que) {
      QuePaso.igual => '',
      QuePaso.entra => 'entra',
      QuePaso.sale => 'sale',
      QuePaso.cambiada => 'cambiada',
      QuePaso.tramo => '',
    };
    return '<tr class="$clase">'
        '<td class="n">${fila.numeroIzquierda ?? ''}</td>'
        '<td class="izq">${_pintado(fila.izquierda)}</td>'
        '<td class="n">${fila.numeroDerecha ?? ''}</td>'
        '<td class="der">${_pintado(fila.derecha)}</td>'
        '</tr>';
  }

  /// Una línea de código, escapada y con sus colores.
  ///
  /// **Sin nada que ejecutar**: el visor no tiene JavaScript, así que el
  /// coloreado no puede venir de una librería que corra en la página. Se hace
  /// aquí, marcando la línea con etiquetas, que además es lo único que se puede
  /// probar sin abrir un navegador.
  ///
  /// Línea a línea y sin memoria entre ellas: un bloque de comentario abierto en
  /// una y cerrado en otra no se pinta entero. Es el precio de no llevar un
  /// analizador de verdad, y en un diff —donde media línea llega sin su
  /// contexto— un analizador con estado se equivocaría más de lo que acertaría.
  static String _pintado(String? linea) {
    if (linea == null || linea.isEmpty) return '';

    final salida = StringBuffer();
    var i = 0;
    while (i < linea.length) {
      final resto = linea.substring(i);

      // Un comentario se come el resto de la línea, así que va primero.
      if (resto.startsWith('//') || resto.startsWith('#')) {
        salida.write('<i class="com">${_texto(resto)}</i>');
        break;
      }

      final comilla = resto[0];
      if (comilla == "'" || comilla == '"' || comilla == '`') {
        final cierra = _finDeCadena(resto, comilla);
        salida.write(
          '<i class="cad">${_texto(resto.substring(0, cierra))}</i>',
        );
        i += cierra;
        continue;
      }

      final palabra = _palabra.matchAsPrefix(resto);
      if (palabra != null) {
        final texto = palabra.group(0)!;
        final clase = _reservadas.contains(texto)
            ? 'res'
            // Un identificador que empieza por mayúscula es un tipo en casi
            // todos los lenguajes que se van a mirar aquí. No es exacto; es
            // barato y acierta casi siempre.
            : (texto[0].toUpperCase() == texto[0] &&
                      texto[0].toLowerCase() != texto[0]
                  ? 'tip'
                  : (_numero.hasMatch(texto) ? 'num' : ''));
        salida.write(
          clase.isEmpty
              ? _texto(texto)
              : '<i class="$clase">${_texto(texto)}</i>',
        );
        i += texto.length;
        continue;
      }

      salida.write(_texto(resto[0]));
      i++;
    }
    return salida.toString();
  }

  /// Dónde acaba una cadena, contando los escapes. Sin cierre, hasta el final:
  /// una comilla suelta en un diff es lo normal, no un error.
  static int _finDeCadena(String resto, String comilla) {
    for (var i = 1; i < resto.length; i++) {
      if (resto[i] == r'\\') {
        i++;
        continue;
      }
      if (resto[i] == comilla) return i + 1;
    }
    return resto.length;
  }

  static final _palabra = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*|[0-9]+\.?[0-9]*');
  static final _numero = RegExp(r'^[0-9]');

  /// Un puñado que cubre Dart, Swift, JS y YAML sin pretender ser un analizador.
  static const _reservadas = {
    'abstract',
    'as',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'func',
    'get',
    'guard',
    'if',
    'implements',
    'import',
    'in',
    'is',
    'late',
    'let',
    'library',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'part',
    'private',
    'required',
    'return',
    'sealed',
    'set',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
  };

  /// El atajo de un solo grupo, que es lo que quiere casi todo el que llama.
  static String de({
    required String diff,
    required List<String> nuevos,
    required String titulo,
    String? tambien,
    String? tituloDeTambien,
  }) => deGrupos([
    (titulo: titulo, diff: diff, nuevos: nuevos),
    if (tambien != null && tituloDeTambien != null)
      (titulo: tituloDeTambien, diff: tambien, nuevos: const <String>[]),
  ]);

  /// La ruta recortada por la izquierda, que es por donde sobra: lo que
  /// identifica un archivo en una lista es su nombre, no las cinco carpetas que
  /// tiene encima.
  static String _corta(String ruta) {
    final partes = ruta.split('/');
    if (partes.length <= 2) return ruta;
    return '…/${partes.sublist(partes.length - 2).join('/')}';
  }

  /// **Escapado, siempre.** Lo que entra aquí es código que escribió otro —a
  /// veces un modelo— y una sola `<` sin escapar convierte una línea del diff
  /// en etiquetas de verdad. El visor no ejecuta scripts, así que el daño sería
  /// una página rota y no algo peor, pero una página rota justo donde vienes a
  /// leer lo que cambió es suficiente motivo.
  static String _texto(String crudo) => crudo
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static const _estilo = '''
:root{--fondo:#0d1117;--panel:#0d1117;--lado:#12161c;--linea:#232a34;
      --texto:#c9d1d9;--tenue:#57606a;--acento:#57d3e0;--sel:#1d2530;
      --verde:#3fb950;--rojo:#f85149;--verdeF:#12261a;--rojoF:#2d1416;
      --res:#ff7b72;--cad:#a5d6ff;--com:#6a7480;--tip:#79c0ff;--num:#d2a8ff}
@media (prefers-color-scheme:light){
  :root{--fondo:#fff;--panel:#fff;--lado:#f6f7f9;--linea:#e4e2dd;
        --texto:#1f2328;--tenue:#8b949e;--acento:#1f6f7a;--sel:#eef1f5;
        --verdeF:#e6ffec;--rojoF:#ffebe9;--res:#cf222e;--cad:#0a3069;
        --com:#6e7781;--tip:#0550ae;--num:#8250df}}
*{box-sizing:border-box}
body{margin:0;background:var(--fondo);color:var(--texto);display:flex;
     font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}

/* El panel de archivos */
nav{width:250px;flex:none;height:100vh;overflow-y:auto;padding:16px 10px;
    border-right:1px solid var(--linea);background:var(--lado);position:sticky;top:0}
.grupo{color:var(--tenue);font-size:10px;text-transform:uppercase;
       letter-spacing:.1em;margin:12px 4px 6px}
nav a{display:flex;gap:8px;align-items:baseline;padding:3px 8px;border-radius:4px;
      text-decoration:none;color:var(--tenue)}
nav a:hover{background:var(--sel)}
nav .ruta{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
          direction:rtl;text-align:left}
.mas{color:var(--verde)} .menos{color:var(--rojo)}
.nuevo{color:var(--acento);font-size:10px;letter-spacing:.06em}

/* El panel del código */
main{flex:1;min-width:0;height:100vh;overflow-y:auto;padding:0 0 40px}
h2{position:sticky;top:0;z-index:1;margin:0;padding:12px 18px;
   background:var(--fondo);border-bottom:1px solid var(--linea);
   font-size:12px;font-weight:500;color:var(--acento);word-break:break-all}
.nada{color:var(--tenue);padding:18px}

/* **Las líneas largas se parten, y no pasa nada.** Partirlas parecía la causa
   del descuadre de la primera versión y no lo era: dentro de una tabla, las dos
   celdas de una fila comparten altura por definición, así que los dos lados
   siguen a la misma altura aunque uno ocupe tres renglones. Lo que descuadraba
   eran los anchos. Y partir evita el desplazamiento horizontal, que en dos
   columnas obliga a arrastrar para leer media línea. */
table{border-collapse:collapse;table-layout:fixed;width:100%}
col.cn{width:52px} col.cc{width:calc(50% - 52px)}
td{padding:0 10px;white-space:pre-wrap;word-break:break-word;vertical-align:top}
td.n{text-align:right;color:var(--tenue);user-select:none;padding:0 8px;
     border-right:1px solid var(--linea)}
td.izq{border-right:1px solid var(--linea)}
tr.sale td.izq,tr.cambiada td.izq{background:var(--rojoF)}
tr.entra td.der,tr.cambiada td.der{background:var(--verdeF)}
tr.entra td.izq,tr.sale td.der{background:color-mix(in srgb,var(--tenue) 6%,transparent)}
tr.tramo td{color:var(--tenue);padding:12px 18px 4px;font-size:11px;
            border-top:1px solid var(--linea);white-space:pre-wrap}

/* Sintaxis */
i{font-style:normal}
.res{color:var(--res)} .cad{color:var(--cad)} .com{color:var(--com)}
.tip{color:var(--tip)} .num{color:var(--num)}

/* Un archivo a la vez: el elegido; y el primero si no se ha elegido ninguno,
   para que la ventana no se abra en blanco. */
section{display:none}
section:target{display:block}
body:not(:has(section:target)) section:first-of-type{display:block}
''';
}

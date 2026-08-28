import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';

/// La prueba corriendo, escrita como una página.
///
/// **Existe para poder verla en una ventana aparte sin escribir nada nativo.** El
/// visor de documentos de Nexus es una `NSWindow` con un `WKWebView` que **vigila
/// el archivo y se recarga cuando cambia**; escribir aquí y reescribir en cada
/// paso sale exactamente eso: una ventana independiente que se actualiza sola, no
/// bloquea la app y se puede dejar al lado mientras se trabaja.
///
/// Autocontenida a propósito: sin fuentes ni hojas de fuera. La ventana carga un
/// archivo local y cualquier petición a la red sería un hueco en blanco.
///
/// **Sin una línea de JavaScript.** El giro del indicador es una animación de CSS
/// y el avance llega recargando el archivo, así que no hay estado que sincronizar
/// entre la página y la app — que es el error obvio aquí y el que habría hecho
/// falta depurar en dos sitios.
abstract final class LaPasadaComoHtml {
  /// El esquema con el que la página le habla a la app.
  ///
  /// El visor intercepta cualquier URL que no sea de archivo; con este esquema, en
  /// vez de abrirla en el navegador, se la reenvía a Nexus. Es lo que hace que el
  /// botón de detener funcione desde una página estática.
  static const esquema = 'nexus';

  static String escribe({
    required String flow,
    required List<PasoParaPintar> pasos,
    required List<String> lineas,
    required int terminados,
    required bool viva,
    required bool fallo,
    int? total,
    Map<String, String> capturas = const {},
    String? diagnostico,
  }) {
    // **El total va aparte y no se deduce de la lista.** Con una lista vacía
    // —lo que pasaba al abrir el informe de una pasada guardada— el encabezado
    // decía «8/0», que es una cuenta imposible y se lee como un fallo nuestro.
    final cuantos = total ?? pasos.length;

    // **El total es una estimación y se dice.** Sale de contar los pasos del
    // `.yaml`, y el archivo no sabe cuántos se van a ejecutar de verdad: un
    // `runFlow` o un bucle ejecutan más. Mientras cuadre se enseña «3 de 8»; en
    // cuanto lo ejecutado lo pasa, el denominador es falso y se quita en vez de
    // enseñar «11 de 8», que es una cuenta imposible y se lee como un fallo
    // nuestro. Es el mismo criterio que dejó de decir «8/0».
    final cuenta = terminados > cuantos
        ? '$terminados'
        : '$terminados de $cuantos';

    // **Ya no hay caso de rendirse.** Antes, cuando los pasos impresos no cuadraban
    // con los del archivo, esto se quedaba vacío y solo se enseñaba la salida cruda.
    // Los pasos vienen ahora de la propia salida —ver `PasosDeUnaPrueba.paraPintar`—
    // así que no hay nada que emparejar y no hay nada que degradar.
    final filas = [
      for (final (i, paso) in pasos.indexed) _fila(paso, i + 1, capturas),
    ].join('\n');

    return '''
<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>$flow</title>
<style>
  :root{
    --bg:#0b0d10; --panel:#111419; --ink:#e8eaee; --faint:#6e7683; --line:#22262e;
    --ok:#6fd39b; --err:#f08a8a; --acento:#7aa0ff;
    --mono:"Geist Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
    --sans:"Instrument Sans",-apple-system,BlinkMacSystemFont,sans-serif;
  }
  @media (prefers-color-scheme:light){
    :root{ --bg:#f3f2f0; --panel:#fff; --ink:#16181d; --faint:#8b91a0;
           --line:#e4e2dd; --ok:#1c7a4a; --err:#b02a2a; --acento:#2f5bd7; }
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);font-family:var(--mono);font-size:12.5px;
       line-height:1.6;color:var(--ink);padding:10px}
  .tarjeta{background:var(--panel);border:1px solid var(--line);
           border-radius:10px;overflow:hidden}
  header{display:flex;align-items:center;gap:10px;padding:12px 14px;
         border-bottom:1px solid var(--line)}
  h1{font-size:13px;margin:0;font-weight:600;font-family:var(--mono);
     white-space:nowrap;overflow:hidden;text-overflow:ellipsis}

  /* La etiqueta de estado: pastilla con su símbolo dentro. */
  .chapa{display:inline-flex;align-items:center;gap:6px;flex:none;
         font-family:var(--sans);font-size:11px;font-weight:600;
         padding:3px 9px;border-radius:999px;white-space:nowrap}
  .chapa.viva{color:var(--acento);background:color-mix(in srgb,var(--acento) 14%,transparent)}
  .chapa.bien{color:var(--ok);background:color-mix(in srgb,var(--ok) 14%,transparent)}
  .chapa.mal{color:var(--err);background:color-mix(in srgb,var(--err) 14%,transparent)}

  /* El giro, en CSS: la página no lleva JavaScript.

     `display:inline-block` es obligatorio y no decorativo: a un `span` inline no
     se le aplican `width` ni `height`, así que el círculo se quedaba en una
     astilla vertical —se veía como una barra— en la marca de cada paso. En la
     etiqueta de arriba sí salía redondo, porque ahí es hijo de un `inline-flex`
     y se convierte en item. El mismo HTML pintado de dos formas distintas según
     el padre: por eso el arreglo va en la clase y no en cada sitio. */
  .gira{display:inline-block;width:10px;height:10px;border-radius:50%;flex:none;
        border:1.5px solid color-mix(in srgb,currentColor 30%,transparent);
        border-top-color:currentColor;animation:vuelta .7s linear infinite}
  @keyframes vuelta{to{transform:rotate(360deg)}}

  .parar{margin-left:auto;flex:none;width:22px;height:22px;display:flex;
         align-items:center;justify-content:center;border-radius:5px;
         border:1px solid var(--line);color:var(--faint);text-decoration:none}
  .parar:hover{color:var(--err);border-color:var(--err)}
  .parar span{width:7px;height:7px;background:currentColor;border-radius:1px}

  ol{list-style:none;padding:6px 0;margin:0}
  li{display:flex;gap:8px;padding:2px 14px;align-items:baseline}
  /* **La fila en curso se marca con el acento de fondo, no con un gris.** Un gris
     sobre un fondo oscuro queda dentro del mismo rango de tono que el resto y no
     se distingue: había que buscar el símbolo para saber por dónde iba. Con el
     acento detrás, el paso actual se ve de un vistazo y sin leer nada.

     Y por eso mismo **la letra no se apaga nunca**: el paso pendiente se dice con
     su símbolo —el punto— y con el fondo, no oscureciendo el texto. Texto gris
     sobre este fondo se lee mal y compite con la única señal que importa. */
  li.curso{background:color-mix(in srgb,var(--acento) 22%,transparent)}
  .marca{flex:none;width:12px;text-align:center;line-height:1.6}
  .num{flex:none;color:var(--faint);min-width:22px;text-align:right}
  .guion{flex:none;color:var(--line)}
  .texto{white-space:pre-wrap;word-break:break-word;color:var(--ink)}
  li.hecho .marca{color:var(--ok)}
  li.omitido .marca{color:var(--faint)}
  li.omitido .texto{opacity:.65}
  li.fallo .marca{color:var(--err)}
  li.espera .marca{color:var(--line)}
  .punto{display:inline-block;width:5px;height:5px;border-radius:50%;
         background:currentColor;vertical-align:middle}
  .detalle{color:var(--ink)}
  /* La captura, centrada y acotada. Su propia línea, fuera de la columna del
     texto, que es lo que permite centrarla respecto a la tarjeta. Y `max-width`
     porque una pantalla de móvil son 1080 px: cabe sin desbordar ni deformarse. */
  li.toma{display:block;padding:2px 14px 8px}
  li.toma img{display:block;margin:0 auto;max-width:100%;height:auto;
              border:1px solid var(--line);border-radius:6px}

  /* El motivo, cuando se reconoce. Va arriba y no al final: es lo primero que se
     busca, y ahora mismo compite con veinte líneas de traza que no dicen nada. */
  .motivo{margin:10px 14px 0;padding:8px 10px;font-size:12px;line-height:1.5;
          color:var(--ink);border-radius:6px;
          background:color-mix(in srgb,var(--err) 16%,transparent);
          border:1px solid color-mix(in srgb,var(--err) 35%,transparent)}

  h2{font-size:10px;letter-spacing:.1em;text-transform:uppercase;
     color:var(--faint);margin:14px 14px 4px;font-family:var(--sans)}
  pre{margin:0;padding:0 14px 12px;white-space:pre-wrap;word-break:break-word;
      color:var(--faint)}
</style></head><body>
<div class="tarjeta">
  <header>
    <h1>${_escapa(flow)}</h1>
    ${_chapa(viva: viva, fallo: fallo)}
    ${viva ? '<a class="parar" href="$esquema://parar" title="Detener"><span></span></a>' : ''}
  </header>
  ${diagnostico == null ? '' : '<p class="motivo">${_escapa(diagnostico)}</p>'}
  ${filas.isEmpty ? '' : '<ol>\n$filas\n</ol>'}
  ${lineas.isEmpty ? '' : '<h2>salida · $cuenta</h2><pre>${_escapa(lineas.join('\n'))}</pre>'}
</div>
</body></html>
''';
  }

  /// La etiqueta de estado. **Tres estados y tres palabras**, con su símbolo: el
  /// indicador girando mientras corre, un visto al acabar, una equis si falló.
  static String _chapa({required bool viva, required bool fallo}) {
    if (viva) {
      return '<span class="chapa viva"><span class="gira"></span>Corriendo</span>';
    }
    if (fallo) {
      return '<span class="chapa mal">✕ Error</span>';
    }
    return '<span class="chapa bien">✓ Finalizada</span>';
  }

  /// [orden] es **el número que se enseña: 1, 2, 3…** y no la línea del archivo.
  ///
  /// Se probó con la línea del `.yaml` y no servía: salían 12, 22, 27 y eso no se
  /// lee como una lista de pasos, se lee como un error. La línea sigue estando y
  /// va en el `title` de la fila, que es donde no molesta y sigue sirviendo para
  /// ir a buscarla.
  static String _fila(
    PasoParaPintar paso,
    int orden,
    Map<String, String> capturas,
  ) {
    final clase = switch (paso.estado) {
      EstadoDePaso.hecho => 'hecho',
      EstadoDePaso.enCurso => 'curso',
      EstadoDePaso.fallado => 'fallo',
      EstadoDePaso.omitido => 'omitido',
      EstadoDePaso.pendiente => 'espera',
    };
    // **El símbolo cuenta el estado sin leer nada**: gris de espera, el indicador
    // girando en el color de acento mientras se ejecuta, y un visto al acabar.
    final marca = switch (paso.estado) {
      EstadoDePaso.hecho => '✓',
      EstadoDePaso.enCurso =>
        '<span class="gira" style="color:var(--acento)"></span>',
      EstadoDePaso.fallado => '✕',
      // Un guion y no una cruz: se saltó a propósito, no se rompió.
      EstadoDePaso.omitido => '–',
      EstadoDePaso.pendiente => '<span class="punto"></span>',
    };

    final detalle = paso.detalle.isEmpty
        ? ''
        : '\n<span class="detalle">${_escapa(paso.detalle.join('\n'))}</span>';

    // **La captura se pinta debajo del paso que la tomó.** El nombre lo dice el
    // propio paso —«Take screenshot login_form»— y el archivo es `login_form.png`,
    // así que casan sin heurística. Un montón de imágenes al final obligaría a
    // adivinar cuál es de cuál.
    final imagen = _captura(paso, capturas);

    // El `title` solo cuando se sabe de qué línea salió: los ejecutados vienen de
    // la prosa de Maestro y no lo dicen.
    final donde = paso.linea == null ? '' : ' title="línea ${paso.linea}"';

    return '<li class="$clase"$donde>'
        '<span class="marca">$marca</span>'
        '<span class="num">$orden</span>'
        '<span class="guion">–</span>'
        '<span class="texto">${_escapa(paso.texto)}$detalle</span>'
        '</li>'
        // **La captura va en su propia línea y no dentro del texto.** Dentro,
        // arranca en la columna del texto —detrás de la marca, el número y el
        // guion— así que no hay forma de centrarla respecto a la ventana: ya
        // ocupa todo el ancho que le queda. Fuera de la fila sí.
        '$imagen';
  }

  /// La captura de este paso, si la hay y si el paso es de tomar una.
  ///
  /// Solo se busca en los pasos ejecutados que Maestro nombra «Take screenshot X»:
  /// en el texto del `.yaml` sería `takeScreenshot: X`, y ese paso todavía no ha
  /// corrido, así que no hay nada que enseñar.
  static String _captura(PasoParaPintar paso, Map<String, String> capturas) {
    if (capturas.isEmpty) return '';

    final m = RegExp(r'^Take screenshot (.+)$').firstMatch(paso.texto.trim());
    if (m == null) return '';

    final fuente = capturas[m.group(1)!.trim()];
    if (fuente == null) return '';

    return '\n<li class="toma"><img src="$fuente" alt=""></li>';
  }

  /// Lo que imprime Maestro y lo que escribe alguien en un `.yaml` acaban aquí
  /// dentro, así que hay que escaparlos: un `assertVisible: "<b>"` no puede
  /// convertirse en negrita, y una comilla partiría el atributo de al lado.
  static String _escapa(String texto) => texto
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

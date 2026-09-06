/// De qué color se lee una línea. Tres y no seis: lo que se busca en un
/// volcado es lo rojo, y distinguir `verbose` de `debug` con un tono no lo
/// distingue nadie — para eso está el filtro de nivel, que sí es una lista.
enum TonoDeLinea { normal, aviso, error }

/// Una línea del registro, ya lista para pintar.
///
/// Tipo propio y no el del registro del sistema —`LineaDeRegistro`, que vive en
/// la feature de emuladores— a propósito: por esta página pasan **dos** cosas
/// distintas, lo que imprime la corrida (texto pelado) y lo que dice el
/// teléfono (con nivel y etiqueta). Traducir las dos aquí deja el dominio de
/// `run` sin depender de la feature de al lado.
class LineaDeLaVentana {
  const LineaDeLaVentana(
    this.texto, {
    this.tono = TonoDeLinea.normal,
    this.etiqueta,
  });

  final String texto;
  final TonoDeLinea tono;

  /// El `Tag` de `logcat`, cuando lo hay. La corrida no trae ninguno.
  final String? etiqueta;
}

/// Los textos de la página, que vienen de fuera.
///
/// **Se reciben en vez de escribirse aquí**: el idioma se elige en Ajustes y
/// puede no ser el del sistema. Es la misma regla que ya sigue la ventana de la
/// actividad, y por el mismo motivo.
class TextosDelRegistro {
  const TextosDelRegistro({
    required this.titulo,
    required this.dispositivo,
    required this.vacio,
    this.nivel,
    this.escucha,
  });

  final String titulo;

  /// De qué dispositivo salió esto. Va siempre, aunque solo haya una corrida:
  /// la ventana se queda abierta y al lado, lejos del panel que lo decía.
  final String dispositivo;

  /// Qué poner cuando todavía no ha llegado nada. Un hueco negro se lee como
  /// roto, y lo que pasa es que aún no ha escrito nadie.
  final String vacio;

  /// El rótulo del botón de nivel, ya resuelto —«desde avisos», «solo
  /// errores»—. Nulo en el registro de la corrida, que no filtra.
  final String? nivel;

  /// El del botón de escuchar o dejar de escuchar.
  final String? escucha;
}

/// El registro de una corrida, escrito como una página.
///
/// 🔴 **Existe para sacarlo de la columna del panel.** Los dos registros eran
/// interruptores con estado del widget que insertaban un cuadro **dentro del
/// menú**: no abrían nada, crecían hacia abajo. El panel de correr acababa
/// siendo un cuadrado con un volcado dentro, y al cerrarlo se perdía hasta
/// saber que estaba abierto.
///
/// El visor de Nexus es una `NSWindow` con un `WKWebView` que vigila el archivo
/// y se recarga cuando cambia, así que escribir esto y reescribirlo da lo que
/// hace falta mientras algo compila: una ventana movible, que se deja al lado,
/// que se actualiza sola y que **no bloquea la app**.
///
/// **Sin una línea de JavaScript**, como sus dos hermanas. Ni siquiera para lo
/// único que aquí se echaría de menos —quedarse abajo, como una terminal—: eso
/// sale de un `column-reverse`, donde el principio del rollo es el final del
/// registro y el desplazamiento en reposo es justo el que se quiere. Con
/// JavaScript habría además que sincronizarlo tras cada recarga, que es estado
/// duplicado para conseguir lo mismo.
abstract final class ElRegistroComoHtml {
  /// El esquema con el que la página le habla a la app. Ver [LoQuePideLaPagina].
  static const esquema = 'nexus';

  /// Lo que se pide con este esquema desde aquí: `nexus://registro/...`.
  static const que = 'registro';

  static String escribe({
    required List<LineaDeLaVentana> lineas,
    required TextosDelRegistro textos,
    required bool viva,
    String? escuchandoEn,
    bool escuchando = false,
  }) {
    // **Del revés a propósito.** El rollo es un `column-reverse`, así que lo
    // primero que se escribe queda abajo — y abajo es donde está lo último que
    // pasó, que es lo que se busca cuando algo falla.
    final cuerpo = lineas.isEmpty
        ? '<p class="vacio">${_e(textos.vacio)}</p>'
        : lineas.reversed.map(_linea).join('\n');

    final botones = StringBuffer();
    if (escuchandoEn != null) {
      botones.write(
        '<a class="chip${escuchando ? ' vivo' : ''}" '
        'href="$esquema://$que/escucha/${_e(escuchandoEn)}">'
        '${_e(textos.escucha ?? '')}</a>',
      );
    }
    if (textos.nivel case final nivel?) {
      botones.write(
        '<a class="chip" href="$esquema://$que/nivel">${_e(nivel)}</a>',
      );
    }

    return '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_e(textos.titulo)} · ${_e(textos.dispositivo)}</title>
<style>
  :root{
    --bg:#0b0d10; --panel:#111419; --ink:#e8eaee; --faint:#6e7683; --line:#22262e;
    --ok:#6fd39b; --warn:#e0a86a; --acento:#7aa0ff; --err:#f08a8a;
    --mono:ui-monospace,SFMono-Regular,Menlo,monospace;
    --sans:-apple-system,BlinkMacSystemFont,sans-serif;
  }
  @media (prefers-color-scheme:light){
    :root{ --bg:#f3f2f0; --panel:#fff; --ink:#16181d; --faint:#8b91a0;
           --line:#e4e2dd; --ok:#1c7a4a; --warn:#8a5a1c; --acento:#2f5bd7;
           --err:#b02a2a; }
  }
  *{box-sizing:border-box}
  /* La ventana entera es el registro: cabecera fija arriba y el rollo debajo,
     con **una sola barra de desplazamiento**. Con el documento rodando por su
     cuenta salían dos pegadas y la rueda hacía una cosa u otra según dónde
     estuviera el puntero — ya pasó en la ventana de la actividad. */
  html,body{height:100%}
  body{margin:0;background:var(--bg);font-family:var(--mono);font-size:12px;
       line-height:1.55;color:var(--ink);display:flex;flex-direction:column;
       overflow:hidden}
  header{display:flex;align-items:center;gap:9px;padding:9px 12px;flex:none;
         background:var(--panel);border-bottom:1px solid var(--line)}
  h1{font-size:10.5px;margin:0;font-weight:700;letter-spacing:.1em;
     text-transform:uppercase;color:var(--acento);font-family:var(--sans)}
  .donde{color:var(--faint);font-size:11px;overflow:hidden;white-space:nowrap;
         text-overflow:ellipsis}
  .chips{margin-left:auto;display:flex;gap:6px;flex:none}
  .chip{font-family:var(--sans);font-size:10px;letter-spacing:.04em;
        padding:2px 7px;border-radius:5px;border:1px solid var(--line);
        color:var(--faint);text-decoration:none;white-space:nowrap}
  .chip:hover{color:var(--ink);border-color:var(--faint)}
  .chip.vivo{color:var(--ok);border-color:color-mix(in srgb,var(--ok) 45%,transparent)}

  .gira{display:inline-block;width:9px;height:9px;border-radius:50%;flex:none;
        border:1.5px solid color-mix(in srgb,var(--acento) 30%,transparent);
        border-top-color:var(--acento);animation:vuelta .7s linear infinite}
  @keyframes vuelta{to{transform:rotate(360deg)}}
  .punto{display:inline-block;width:7px;height:7px;border-radius:50%;flex:none;
         background:var(--line)}

  /* 🔴 **Del revés, y por eso se queda abajo.** Una terminal enseña lo último;
     una página recién cargada enseña lo primero. Con `column-reverse` el
     desplazamiento en reposo —el que trae cada recarga— es el final del
     registro, sin una línea de JavaScript que lo empuje. */
  main{flex:1;overflow:auto;display:flex;flex-direction:column-reverse;
       padding:8px 12px}
  .l{margin:0;white-space:pre-wrap;word-break:break-word;color:var(--faint)}
  .l.aviso{color:var(--warn)}
  .l.error{color:var(--err)}
  .tag{color:var(--acento);opacity:.85}
  .vacio{color:var(--faint);margin:0}
  @media (prefers-reduced-motion:reduce){ .gira{animation:none} }
</style></head>
<body>
  <header>
    ${viva ? '<span class="gira"></span>' : '<span class="punto"></span>'}
    <h1>${_e(textos.titulo)}</h1>
    <span class="donde">${_e(textos.dispositivo)}</span>
    <span class="chips">$botones</span>
  </header>
  <main>
$cuerpo
  </main>
</body></html>
''';
  }

  static String _linea(LineaDeLaVentana linea) {
    final clase = switch (linea.tono) {
      TonoDeLinea.error => 'l error',
      TonoDeLinea.aviso => 'l aviso',
      TonoDeLinea.normal => 'l',
    };
    final tag = linea.etiqueta ?? '';
    final etiqueta = tag.isEmpty ? '' : '<span class="tag">${_e(tag)}</span> ';
    return '<p class="$clase">$etiqueta${_e(linea.texto)}</p>';
  }

  /// Una línea de registro **no es HTML**, y aquí se pintaría como si lo fuera:
  /// un volcado con `<` se come el resto de la página. No es teórico — cualquier
  /// traza de Gradle o un `logcat` de un `WebView` lo trae.
  static String _e(String texto) => texto
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

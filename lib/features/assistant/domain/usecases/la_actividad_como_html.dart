import 'package:nexus/features/assistant/presentation/state/activity_layout.dart';

/// Los textos de la página, que vienen de fuera.
///
/// **Se reciben en vez de escribirse aquí**: el idioma se elige en Ajustes y
/// puede no ser el del sistema. La página de las pruebas nació en español a
/// pelo y es deuda anotada; esta no se suma a ella.
class TextosDeActividad {
  const TextosDeActividad({
    required this.titulo,
    required this.progreso,
    required this.trabajando,
    required this.escribe,
    required this.seEjecuto,
    required this.devolvio,
    required this.todaviaCorriendo,
    required this.sinPasos,
  });

  final String titulo;
  final String Function(int hechos, int total) progreso;
  final String trabajando;
  final String escribe;
  final String seEjecuto;
  final String devolvio;
  final String todaviaCorriendo;
  final String sinPasos;
}

/// Lo que está haciendo el encargo, escrito como una página.
///
/// **Existe para poder verlo en una ventana aparte sin escribir nada nativo.**
/// El visor de Nexus es una `NSWindow` con un `WKWebView` que vigila el archivo
/// y se recarga cuando cambia, así que reescribir en cada paso da lo que se
/// pidió: una ventana movible, que se deja al lado, y que **no impide seguir
/// trabajando** — que es lo que sí hacía el diálogo que había antes.
///
/// **Sin una línea de JavaScript.** El giro es una animación de CSS y el
/// desplegable es `<details>`, que el navegador ya sabe abrir. Así no hay
/// estado que sincronizar entre la página y la app, que es el error obvio aquí
/// y el que habría hecho falta depurar en dos sitios.
///
/// Autocontenida: sin fuentes ni hojas de fuera. La ventana carga un archivo
/// local y cualquier petición a la red sería un hueco en blanco.
abstract final class LaActividadComoHtml {
  static String escribe({
    required List<ActivityRow> filas,
    required int terminados,
    required bool viva,
    required TextosDeActividad textos,
  }) {
    final cuerpo = filas.isEmpty
        ? '<p class="vacio">${_e(textos.sinPasos)}</p>'
        : filas.map((fila) => _fila(fila, textos)).join('\n');

    return '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_e(textos.titulo)}</title>
<style>
  :root{
    --bg:#0b0d10; --panel:#111419; --ink:#e8eaee; --faint:#6e7683; --line:#22262e;
    --ok:#6fd39b; --warn:#e0a86a; --acento:#7aa0ff;
    --mono:ui-monospace,SFMono-Regular,Menlo,monospace;
    --sans:-apple-system,BlinkMacSystemFont,sans-serif;
  }
  @media (prefers-color-scheme:light){
    :root{ --bg:#f3f2f0; --panel:#fff; --ink:#16181d; --faint:#8b91a0;
           --line:#e4e2dd; --ok:#1c7a4a; --warn:#8a5a1c; --acento:#2f5bd7; }
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);font-family:var(--mono);font-size:12.5px;
       line-height:1.6;color:var(--ink);padding:10px}
  .tarjeta{background:var(--panel);border:1px solid var(--line);
           border-radius:10px;overflow:hidden}
  header{display:flex;align-items:center;gap:10px;padding:12px 14px;
         border-bottom:1px solid var(--line)}
  h1{font-size:11px;margin:0;font-weight:700;letter-spacing:.1em;
     text-transform:uppercase;color:var(--acento);font-family:var(--sans)}
  .cuenta{margin-left:auto;color:var(--faint);font-size:11px;
          font-variant-numeric:tabular-nums}

  /* El giro, en CSS: la página no lleva JavaScript.
     `inline-block` no es decorativo — a un `span` inline no se le aplican
     `width` ni `height` y el círculo queda en una astilla vertical. */
  .gira{display:inline-block;width:9px;height:9px;border-radius:50%;flex:none;
        border:1.5px solid color-mix(in srgb,var(--acento) 30%,transparent);
        border-top-color:var(--acento);animation:vuelta .7s linear infinite}
  @keyframes vuelta{to{transform:rotate(360deg)}}
  .punto{display:inline-block;width:7px;height:7px;border-radius:50%;flex:none}
  .punto.hecho{background:var(--ok)}
  .punto.espera{background:var(--line)}

  details{border-bottom:1px solid var(--line)}
  details:last-child{border-bottom:none}
  /* El sangrado de lo que hizo un subagente, con su guía: se lee de un vistazo
     que ese trabajo es de quien recibió el encargo, no de quien lo repartió. */
  details.hijo{padding-left:18px;
               border-left:2px solid color-mix(in srgb,var(--acento) 25%,transparent)}

  summary{display:flex;align-items:center;gap:8px;padding:7px 14px;
          cursor:default;list-style:none}
  summary::-webkit-details-marker{display:none}
  details[open] summary{background:color-mix(in srgb,var(--acento) 8%,transparent)}
  /* 🔴 **Una línea por paso, y punto.** Un comando encadenado ocupaba tres o
     cuatro y la lista dejaba de ser una lista: para saber por dónde iba había
     que leerla entera. Lo que no cabe está debajo, al desplegar. */
  .que{flex:1;min-width:0;white-space:nowrap;overflow:hidden;
       text-overflow:ellipsis;color:var(--faint)}
  .curso .que{color:var(--ink)}
  .chapa{flex:none;font-family:var(--sans);font-size:10px;font-weight:700;
         letter-spacing:.04em;padding:1px 5px;border-radius:3px;
         color:var(--warn);background:color-mix(in srgb,var(--warn) 14%,transparent)}
  .flecha{flex:none;color:var(--line);font-size:10px}
  details[hasdetalle] summary{cursor:pointer}

  .dentro{padding:0 14px 10px 32px}
  .caja{background:var(--bg);border:1px solid var(--line);border-radius:6px;
        padding:9px 11px;margin-top:6px}
  .rotulo{font-family:var(--sans);font-size:10px;font-weight:700;
          letter-spacing:.08em;color:var(--faint);margin-bottom:3px}
  /* Envuelve en vez de rodar: la única barra de la página es la del documento.
     Con scroll propio salían dos pegadas y la rueda del ratón hacía una cosa u
     otra según dónde estuviera el puntero. */
  pre{margin:0;white-space:pre-wrap;word-break:break-word;font-family:var(--mono)}
  .cmd{color:var(--acento)}
  .sal{color:var(--faint)}
  .vacio{color:var(--faint);padding:14px;margin:0}
  @media (prefers-reduced-motion:reduce){ .gira{animation:none} }
</style></head>
<body>
  <div class="tarjeta">
    <header>
      ${viva ? '<span class="gira"></span>' : '<span class="punto hecho"></span>'}
      <h1>${_e(textos.titulo)}</h1>
      <span class="cuenta">${_e(textos.progreso(terminados, filas.length))}</span>
    </header>
    $cuerpo
  </div>
</body></html>
''';
  }

  static String _fila(ActivityRow fila, TextosDeActividad textos) {
    final item = fila.item;
    final hay = item.hasDetail;
    final marca = item.done
        ? '<span class="punto hecho"></span>'
        : (fila.running
              ? '<span class="gira"></span>'
              : '<span class="punto espera"></span>');

    final dentro = StringBuffer('<div class="dentro">');
    if (item.detail case final detalle? when detalle.isNotEmpty) {
      dentro.write(
        '<div class="caja"><div class="rotulo">${_e(textos.seEjecuto)}</div>'
        '<pre class="cmd">${_e(detalle)}</pre></div>',
      );
    }
    if (item.output case final salida? when salida.isNotEmpty) {
      dentro.write(
        '<div class="caja"><div class="rotulo">${_e(textos.devolvio)}</div>'
        '<pre class="sal">${_e(salida)}</pre></div>',
      );
    } else if (!item.done) {
      dentro.write(
        '<div class="caja"><pre class="sal">'
        '${_e(textos.todaviaCorriendo)}</pre></div>',
      );
    }
    dentro.write('</div>');

    return '<details class="${fila.depth > 0 ? 'hijo' : ''}"'
        '${hay ? ' hasdetalle' : ''}>'
        '<summary class="${fila.running ? 'curso' : ''}">'
        '$marca<span class="que">${_e(item.description)}</span>'
        '${item.writes ? '<span class="chapa">${_e(textos.escribe)}</span>' : ''}'
        '${hay ? '<span class="flecha">▾</span>' : ''}'
        '</summary>'
        '${hay || !item.done ? dentro : ''}'
        '</details>';
  }

  /// Lo que devuelve un comando **no es HTML**, y aquí se pinta como si lo
  /// fuera si no se escapa: una salida con `<` se comería el resto de la
  /// página. No es una preocupación teórica — un `curl` o un `grep` sobre
  /// cualquier archivo web lo trae.
  static String _e(String texto) => texto
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

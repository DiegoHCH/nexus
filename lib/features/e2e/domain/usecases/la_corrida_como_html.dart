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
abstract final class LaCorridaComoHtml {
  static String escribe({
    required String flow,
    required List<String> pasos,
    required List<EstadoDePaso>? estados,
    required List<String> lineas,
    required int terminados,
    required bool viva,
    required bool fallo,
  }) {
    final filas = estados == null
        // Sin emparejamiento posible —`runFlow`, un bucle— se enseña la salida y
        // no un estado inventado.
        ? ''
        : [
            for (final (i, paso) in pasos.indexed)
              '<li class="${_clase(estados[i])}">${_escapa(paso)}</li>',
          ].join('\n');

    final estado = viva
        ? 'corriendo'
        : fallo
        ? 'falló'
        : 'pasó';

    return '''
<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>$flow</title>
<style>
  :root{
    --bg:#0b0d10; --ink:#e8eaee; --faint:#7b8290; --line:#22262e;
    --ok:#6fd39b; --err:#f08a8a; --run:#7aa0ff;
    --mono:"Geist Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
  }
  @media (prefers-color-scheme:light){
    :root{ --bg:#faf9f7; --ink:#16181d; --faint:#6b7280; --line:#e4e2dd;
           --ok:#1c7a4a; --err:#b02a2a; --run:#2f5bd7; }
  }
  body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--mono);
       font-size:12.5px;line-height:1.7;padding:16px}
  header{display:flex;gap:8px;align-items:baseline;
         border-bottom:1px solid var(--line);padding-bottom:10px;margin-bottom:12px}
  h1{font-size:14px;margin:0;font-weight:600}
  .estado{color:var(--faint)}
  .estado.viva{color:var(--run)}
  .estado.mal{color:var(--err)}
  .estado.bien{color:var(--ok)}
  ol{list-style:none;padding:0;margin:0}
  li{padding:2px 0 2px 20px;position:relative;color:var(--ink);
     word-break:break-word}
  li:before{position:absolute;left:0;width:14px;text-align:center}
  li.hecho:before{content:"✓";color:var(--ok)}
  li.curso:before{content:"◍";color:var(--run)}
  li.fallo:before{content:"✕";color:var(--err)}
  li.espera{color:var(--faint)}
  li.espera:before{content:"–";color:var(--line)}
  h2{font-size:11px;letter-spacing:.08em;text-transform:uppercase;
     color:var(--faint);margin:18px 0 6px}
  pre{margin:0;white-space:pre-wrap;word-break:break-word;color:var(--faint)}
</style></head><body>
<header>
  <h1>${_escapa(flow)}</h1>
  <span class="estado ${viva ? 'viva' : (fallo ? 'mal' : 'bien')}">$estado</span>
  <span class="estado">$terminados/${pasos.length}</span>
</header>
${filas.isEmpty ? '' : '<ol>\n$filas\n</ol>'}
${lineas.isEmpty ? '' : '<h2>salida</h2><pre>${_escapa(lineas.join('\n'))}</pre>'}
</body></html>
''';
  }

  static String _clase(EstadoDePaso estado) => switch (estado) {
    EstadoDePaso.hecho => 'hecho',
    EstadoDePaso.enCurso => 'curso',
    EstadoDePaso.fallado => 'fallo',
    EstadoDePaso.pendiente => 'espera',
  };

  /// Lo que imprime Maestro y lo que escribe alguien en un `.yaml` acaban aquí
  /// dentro, así que hay que escaparlos: un `assertVisible: "<b>"` no puede
  /// convertirse en negrita, y una comilla partiría el atributo de al lado.
  static String _escapa(String texto) => texto
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

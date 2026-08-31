import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/domain/usecases/la_actividad_como_html.dart';
import 'package:nexus/features/assistant/presentation/state/activity_layout.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';

// La página que se abre en su propia ventana. Se prueba el HTML y no el widget
// porque el widget ya no existe: lo que se enseña ahora es esto, cargado por el
// visor de documentos.
//
// «Que sea una ventana independiente como los archivos o las pruebas e2e, para
// poderla mover y seguir haciendo otra cosa.» Un diálogo se pone encima y no
// deja trabajar; esto es una NSWindow de verdad.
void main() {
  const strings = NexusStringsEs();
  final textos = TextosDeActividad(
    titulo: strings.rightNow,
    progreso: strings.stepsProgress,
    trabajando: strings.working,
    escribe: strings.writesTag,
    seEjecuto: strings.ranLabel,
    devolvio: strings.returnedLabel,
    todaviaCorriendo: strings.stillRunning,
    sinPasos: strings.noStepsYet,
  );

  String pinta(List<ActivityItem> pasos, {bool viva = true}) =>
      LaActividadComoHtml.escribe(
        filas: layoutActivity(pasos),
        terminados: pasos.where((p) => p.done).length,
        viva: viva,
        textos: textos,
      );

  test('sin pasos todavía, se cuenta la espera', () {
    final html = pinta(const []);

    expect(html, contains('Pensando'));
  });

  test('cada paso es un desplegable, y el detalle va dentro', () {
    final html = pinta([
      ActivityItem(
        id: 'a1',
        description: 'Corriendo git status',
        writes: false,
        detail: 'git status --porcelain',
        output: 'nada',
        done: true,
      ),
    ]);

    // `<details>` y no JavaScript: el navegador ya sabe abrirlo, así que no hay
    // estado que sincronizar entre la página y la app.
    expect(html, contains('<details'));
    expect(html, contains('Corriendo git status'));
    expect(html, contains('git status --porcelain'));
    expect(
      html,
      isNot(contains('<script')),
      reason: 'la página no lleva una línea de JavaScript',
    );
  });

  test('lo que escribe se marca, y lo que no, no', () {
    final conEscritura = pinta([
      ActivityItem(id: 'a1', description: 'Escribiendo x.dart', writes: true),
    ]);
    final sinEscritura = pinta([
      ActivityItem(id: 'a1', description: 'Leyendo x.dart', writes: false),
    ]);

    expect(conEscritura, contains(strings.writesTag));
    expect(sinEscritura, isNot(contains(strings.writesTag)));
  });

  test('lo del subagente va sangrado bajo quien lo mandó', () {
    final html = pinta([
      ActivityItem(id: 'jefe', description: 'Delegando', writes: false),
      ActivityItem(
        id: 'peon',
        description: 'Buscando ActivityColumn',
        writes: false,
        parentId: 'jefe',
      ),
    ]);

    expect(html, contains('class="hijo"'));
  });

  // 🔴 Lo que devuelve un comando no es HTML, y aquí se pinta. Un `curl` o un
  // `grep` sobre cualquier archivo web trae `<`, y sin escapar se comería el
  // resto de la página.
  test('la salida de un comando no se cuela como HTML', () {
    final html = pinta([
      ActivityItem(
        id: 'a1',
        description: 'Corriendo curl',
        writes: false,
        output: '<script>robar()</script>',
        done: true,
      ),
    ]);

    expect(html, isNot(contains('<script>robar()')));
    expect(html, contains('&lt;script&gt;robar()'));
  });

  test('viva gira; terminada, no', () {
    final paso = [
      ActivityItem(id: 'a1', description: 'Corriendo algo', writes: false),
    ];

    expect(pinta(paso).contains('class="gira"'), isTrue);
    expect(
      pinta([paso.first.asDone()], viva: false),
      isNot(contains('class="gira"')),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/widgets/gauge.dart';

/// En el ancho de verdad: el panel del compositor mide **300 px**, y una prueba
/// de widget falla sola si algo se sale. Es el único tipo de prueba que ve este
/// fallo — ni el análisis ni las de reglas lo tocan.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: NexusTheme.dark(),
      builder: (context, inner) =>
          StringsScope(strings: const NexusStringsEs(), child: inner!),
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('el medidor normal, con sus tres cifras', (tester) async {
    await _pump(
      tester,
      const Gauge(
        label: 'Ventana de contexto',
        percent: 6,
        value: '63,3k / 1,0M (6 %)',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un valor largo se recorta en vez de desbordar el panel', (
    tester,
  ) async {
    // La frase que lo rompió de verdad: 62 caracteres en el hueco del valor
    // sacaban la fila 192 px fuera del panel. Ahora tiene que caber recortada.
    await _pump(
      tester,
      const Gauge(
        label: 'Ventana de contexto',
        percent: 0,
        value: 'Sin dato: esa cuenta no tiene sesión abierta o el acceso caducó.',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('y la etiqueta larga tampoco lo saca', (tester) async {
    await _pump(
      tester,
      const Gauge(
        label: 'Una etiqueta absurdamente larga que nadie escribiría a mano',
        percent: 50,
        value: '129 h 27 m',
        note: 'Se renueva en 129 h 27 m',
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

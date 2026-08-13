import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/stats/domain/entities/usage_stats.dart';
import 'package:nexus/features/stats/domain/usecases/model_label.dart';
import 'package:nexus/features/stats/presentation/widgets/activity_heatmap.dart';
import 'package:nexus/features/stats/presentation/widgets/models_chart.dart';

/// Que se dibujen en el ancho que tienen de verdad.
///
/// La sección de Ajustes mide 600 px, y una prueba de widget **falla sola** si
/// algo se sale — que es exactamente el fallo que ni el análisis ni las pruebas
/// de reglas ven, y el que ya se coló una vez en la barra de Ajustes.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: NexusTheme.dark(),
      builder: (context, inner) =>
          StringsScope(strings: const NexusStringsEs(), child: inner!),
      home: Scaffold(
        body: Center(child: SizedBox(width: 600, child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('el gráfico de modelos, con el más pequeño en 0,1%', (
    tester,
  ) async {
    await _pump(
      tester,
      const ModelsChart(
        stats: UsageStats(
          sessions: 1,
          messages: 1,
          input: 10,
          output: 1000000,
          cached: 0,
          activeDays: 1,
          currentStreak: 1,
          longestStreak: 1,
          peakHour: 12,
          models: [
            ModelUsage(
              model: 'claude-opus-5',
              input: 8,
              output: 999000,
              share: 0.999,
            ),
            // El que se usó una vez: sin ancho mínimo su barra desaparece y la
            // fila se lee como un fallo de dibujo.
            ModelUsage(
              model: 'claude-haiku-4-5-20251001',
              input: 2,
              output: 1000,
              share: 0.001,
            ),
          ],
          days: [],
        ),
      ),
    );

    expect(find.text('Opus 5'), findsOneWidget);
    expect(find.text('Haiku 4.5'), findsOneWidget);
    expect(find.text('99.9%'), findsOneWidget);
  });

  // Un año de actividad no puede empujar la columna: el mapa se desplaza solo.
  testWidgets('el mapa de calor con un año dentro no desborda', (tester) async {
    final hoy = DateTime.now();
    await _pump(
      tester,
      ActivityHeatmap(
        days: [
          for (var i = 0; i < 365; i += 2)
            DayActivity(
              day: DateTime(
                hoy.year,
                hoy.month,
                hoy.day,
              ).subtract(Duration(days: i)),
              messages: i,
            ),
        ],
      ),
    );

    expect(find.byType(ActivityHeatmap), findsOneWidget);
  });

  testWidgets('sin días, el mapa no ocupa sitio', (tester) async {
    await _pump(tester, const ActivityHeatmap(days: []));
    expect(tester.getSize(find.byType(ActivityHeatmap)).height, 0);
  });

  group('el nombre del modelo', () {
    test('el identificador corriente', () {
      expect(modelLabel('claude-opus-5'), 'Opus 5');
      expect(modelLabel('claude-fable-5'), 'Fable 5');
    });

    test('una versión con dos tramos', () {
      expect(modelLabel('claude-opus-4-8'), 'Opus 4.8');
    });

    // La fecha de publicación no es parte del nombre: sin este corte salía
    // «Haiku 4.5.20251001», que es lo que encontró la prueba de dibujo.
    test('la fecha del final no se cuela en la versión', () {
      expect(modelLabel('claude-haiku-4-5-20251001'), 'Haiku 4.5');
    });

    test('el sufijo de ventana larga tampoco', () {
      expect(modelLabel('claude-opus-5[1m]'), 'Opus 5');
    });
  });
}

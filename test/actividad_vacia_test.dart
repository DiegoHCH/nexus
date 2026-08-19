import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/widgets/activity_column.dart';

// «No aparece lo que está haciendo, solo dice AHORA MISMO y ya.»
//
// No estaba roto el conducto: comprobado contra el binario, el CLI emite sus
// `tool_use` y el puente los convierte en actividad. Lo que pasa es que entre
// aceptar el encargo y la primera herramienta pueden pasar segundos, y hay
// encargos que se resuelven **sin abrir nada** — y entonces la columna se
// quedaba con el título y el vacío debajo, que se lee como una avería.
void main() {
  const strings = NexusStringsEs();

  Future<void> montar(WidgetTester tester, List<ActivityItem> items) =>
      tester.pumpWidget(
        MaterialApp(
          theme: NexusTheme.dark(),
          builder: (context, child) =>
              StringsScope(strings: strings, child: child!),
          home: Scaffold(
            body: ActivityColumn(items: items, onStop: () {}),
          ),
        ),
      );

  testWidgets('sin pasos todavía, se cuenta la espera', (tester) async {
    await montar(tester, const []);

    expect(find.text(strings.rightNow), findsOne);
    expect(
      find.textContaining('Pensando'),
      findsOne,
      reason: 'la cabecera sola parece una avería',
    );
  });

  testWidgets('y en cuanto hay un paso, la espera desaparece', (tester) async {
    await montar(tester, [
      ActivityItem(id: '1', description: 'Leyendo pubspec.yaml', writes: false),
    ]);

    expect(find.text('Leyendo pubspec.yaml'), findsOne);
    expect(
      find.textContaining('Pensando'),
      findsNothing,
      reason: 'con pasos a la vista, decir que piensa sobra',
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/widgets/activity_button.dart';

// «Este historial ya no quiero que se vea en el chat.»
//
// La lista entera colgaba de la conversación y crecía con el turno: quince
// pasos empujando hacia arriba lo que se acababa de responder. Se resume en una
// línea, pero **la línea tiene que seguir diciendo qué pasa**: la columna
// existía porque un giro sin texto no distingue trabajar de estar colgado, y
// cambiarla por una ruleta sería volver justo a eso.
void main() {
  const strings = NexusStringsEs();
  var abierto = 0;

  Future<void> montar(WidgetTester tester, List<ActivityItem> items) {
    abierto = 0;
    return tester.pumpWidget(
      MaterialApp(
        theme: NexusTheme.dark(),
        builder: (context, child) =>
            StringsScope(strings: strings, child: child!),
        home: Scaffold(
          body: ActivityButton(items: items, onOpen: () => abierto++),
        ),
      ),
    );
  }

  testWidgets('enseña el paso en curso y no los que ya terminaron', (
    tester,
  ) async {
    await montar(tester, [
      ActivityItem(
        id: '1',
        description: 'Leyendo pubspec.yaml',
        writes: false,
        done: true,
      ),
      ActivityItem(
        id: '2',
        description: 'Corriendo flutter test',
        writes: false,
      ),
    ]);

    expect(find.text('Corriendo flutter test'), findsOne);
    expect(
      find.text('Leyendo pubspec.yaml'),
      findsNothing,
      reason: 'el historial es justo lo que se saca del chat',
    );
    expect(find.text(strings.stepsProgress(1, 2)), findsOne);
  });

  testWidgets('el loader se ve mientras hay trabajo', (tester) async {
    await montar(tester, [
      ActivityItem(
        id: '1',
        description: 'Corriendo flutter test',
        writes: false,
      ),
    ]);

    expect(find.byType(CircularProgressIndicator), findsOne);
  });

  testWidgets('entre una herramienta y la siguiente, dice que trabaja', (
    tester,
  ) async {
    // Todos terminados y el turno vivo: son los segundos que hay entre que una
    // herramienta acaba y llega la siguiente. Dejar la línea en blanco ahí se
    // leería como que se colgó, que es el fallo que esto viene a evitar.
    await montar(tester, [
      ActivityItem(
        id: '1',
        description: 'Leyendo pubspec.yaml',
        writes: false,
        done: true,
      ),
    ]);

    expect(find.text(strings.working), findsOne);
  });

  testWidgets('y al pulsarlo se pide el detalle', (tester) async {
    await montar(tester, [
      ActivityItem(
        id: '1',
        description: 'Corriendo flutter test',
        writes: false,
      ),
    ]);

    await tester.tap(find.byType(ActivityButton));
    await tester.pump();

    expect(abierto, 1);
  });
}

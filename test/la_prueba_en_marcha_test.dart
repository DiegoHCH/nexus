import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/prueba_en_marcha_page.dart';

/// La prueba corriendo, en su propia vista.
///
/// Está aparte de la hoja porque se mira mientras avanza: medio minuto y ocho
/// pasos que van cambiando. Estas pruebas viven en su propio archivo por lo mismo.
class _Fija extends PruebaEnMarchaController {
  _Fija(this._valor);

  final PruebaEnMarcha _valor;

  @override
  PruebaEnMarcha? build() => _valor;
}

Future<void> _abrir(WidgetTester tester, PruebaEnMarcha prueba) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [pruebaEnMarchaProvider.overrideWith(() => _Fija(prueba))],
      child: MaterialApp(
        theme: NexusTheme.dark(),
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: const PruebaEnMarchaPage(),
      ),
    ),
  );
  // Pumps acotados: una prueba viva enseña un indicador que nunca deja de
  // animarse, y `pumpAndSettle` se rendiría por plazo esperando su final.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  const strings = NexusStringsEs();

  testWidgets('los pasos del YAML con su estado, y la cuenta', (tester) async {
    await _abrir(
      tester,
      const PruebaEnMarcha(
        flow: 'login',
        pasos: ['launchApp', 'tapOn: entrar', 'assertVisible: hola'],
        terminados: 1,
      ),
    );

    // Los pasos del archivo, no la redacción de Maestro: emparejar por texto es
    // imposible, así que se enseña lo que alguien escribió.
    expect(find.text('launchApp'), findsOneWidget);
    expect(find.text('tapOn: entrar'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text(strings.e2eStop), findsOneWidget);
  });

  testWidgets('**si lo ejecutado no cuadra, la salida en plano**', (
    tester,
  ) async {
    // Pasa con `runFlow` y con los bucles: lo impreso no son las líneas del
    // archivo. Degradarse es mejor que pintar un estado inventado.
    await _abrir(
      tester,
      const PruebaEnMarcha(
        flow: 'login',
        pasos: ['launchApp'],
        terminados: 9,
        lineas: ['Launch app... COMPLETED', 'Tap on... COMPLETED'],
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('Launch app'), findsOneWidget);
  });

  testWidgets('terminada no ofrece cortar, y dice cómo acabó', (tester) async {
    await _abrir(
      tester,
      const PruebaEnMarcha(
        flow: 'login',
        pasos: ['launchApp'],
        terminados: 1,
        viva: false,
        fallo: true,
      ),
    );

    expect(find.text(strings.e2eStop), findsNothing);
    expect(find.byIcon(Icons.close), findsWidgets);
  });

  testWidgets('la salida va debajo de los pasos, no en su lugar', (
    tester,
  ) async {
    // Cuando un paso falla, el motivo está en la salida y en ningún otro sitio.
    await _abrir(
      tester,
      const PruebaEnMarcha(
        flow: 'login',
        pasos: ['launchApp'],
        terminados: 1,
        viva: false,
        lineas: ['Launch app... COMPLETED'],
      ),
    );

    expect(find.text('launchApp'), findsOneWidget);
    expect(find.text(strings.runLogs), findsOneWidget);
  });
}

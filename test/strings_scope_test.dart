import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';

/// Los textos tienen que alcanzar también a lo que se abre **encima** de la
/// pantalla principal.
///
/// Ajustes es una ruta nueva, y las rutas se construyen fuera del hijo de
/// `home`. Con el scope colgado ahí abajo, la app funcionaba entera y reventaba
/// solo al abrir Ajustes: «falta un StringsScope». Se ve al usar esa pantalla y
/// no antes, que es justo la clase de fallo que conviene dejar clavada.
void main() {
  testWidgets('una pantalla abierta encima sigue teniendo textos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Text(context.strings.settings),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text(const NexusStringsEs().settings), findsOneWidget);
  });
}

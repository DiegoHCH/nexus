import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/artifacts/domain/entities/modelo_de_imagen.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/settings_chooser.dart';

/// «Hay overflow en el menú de imágenes.»
///
/// El desplegable metía dos textos sueltos en un `Row` sin nada que los ciñera.
/// Con las opciones que ya había —una voz, un idioma— cabían de casualidad; con
/// «Nano Banana 2 Lite» y su precio detrás, dejaron de caber.
///
/// Se prueba **con la columna estrecha**, que es donde ocurre: a lo ancho de un
/// portátil no se ve, y por eso llegó hasta la pantalla de alguien.
void main() {
  Future<void> montar(WidgetTester tester, double ancho) async {
    tester.view.physicalSize = Size(ancho, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: NexusTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: ancho,
              child: SettingsChooser<ModeloDeImagen>(
                value: ModeloDeImagen.nanoBanana2,
                options: ModeloDeImagen.values,
                label: (modelo) => modelo.nombre,
                detail: (modelo) => '${modelo.precio} por imagen',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('el selector cabe en una columna estrecha', (tester) async {
    await montar(tester, 320);

    expect(
      tester.takeException(),
      isNull,
      reason: 'la fila del desplegable desborda con etiquetas largas',
    );
  });

  testWidgets('y desplegado, cada opción también', (tester) async {
    await montar(tester, 320);

    await tester.tap(find.byType(SettingsChooser<ModeloDeImagen>));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/emulators/presentation/widgets/dispositivos_menu.dart';
import 'package:nexus/features/emulators/presentation/widgets/dispositivos_panel.dart';

/// El icono de dispositivos del compositor.
///
/// Lo que se prueba es lo que el icono **dice sin abrirse** y que al abrirse
/// enseña el mismo panel que Ajustes. La lista y sus botones ya están probados en
/// `la_seccion_de_emuladores_test.dart`: es el mismo widget, y repetir aquí sus
/// casos sería probar dos veces lo mismo y quedarse con dos sitios que arreglar.
class _Falsa extends EmuladoresDataSource {
  const _Falsa(this._emuladores);

  final List<Emulador> _emuladores;

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async =>
      (emuladores: _emuladores, error: null);

  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => const [];
}

const _android = Emulador(
  id: 'Medium_Phone_API_36.1',
  nombre: 'Medium Phone API 36.1',
  fabricante: 'Generic',
  plataforma: PlataformaEmulador.android,
);

Future<void> _montar(WidgetTester tester, EmuladoresDataSource ds) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [emuladoresDataSourceProvider.overrideWithValue(ds)],
      // **El scope de textos en `builder` y no en `home`**, igual que
      // `main.dart:181`. Un `PopupMenuButton` abre su panel en el Overlay, que
      // está *por encima* de `home`: con el scope colgado ahí abajo, el panel
      // revienta con «Falta un StringsScope por encima de este widget» y se pinta
      // vacío. Es literalmente el fallo que vigila `strings_scope_test.dart`, y
      // esta prueba lo cometió antes de leerlo.
      child: MaterialApp(
        theme: NexusTheme.dark(),
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: const Scaffold(body: Center(child: DispositivosMenu())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const strings = NexusStringsEs();

  testWidgets('con nada arriba, el icono está apagado y sin punto', (
    tester,
  ) async {
    await _montar(tester, const _Falsa([_android]));

    final icono = tester.widget<Icon>(find.byType(Icon));
    expect(icono.color, isNot(NexusColors.dark.accent));
    // El punto es un `Container` con decoración; sin nada arriba no hay ninguno
    // dentro del icono.
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('con algo arriba, el icono se enciende y saca su punto', (
    tester,
  ) async {
    // **El punto es la razón de ser del icono.** Si hay que desplegar el menú
    // para saber si queda un emulador encendido, el atajo no ahorra nada: se
    // seguiría abriendo algo para preguntar.
    await _montar(
      tester,
      _Falsa([_android.conEstado(corriendo: true, deviceId: 'emulator-5554')]),
    );

    final icono = tester.widget<Icon>(find.byType(Icon));
    expect(icono.color, NexusColors.dark.accent);
    expect(find.byType(Container), findsOneWidget);
  });

  testWidgets('al desplegarlo sale el panel, con sus botones', (tester) async {
    await _montar(tester, const _Falsa([_android]));

    await tester.tap(find.byType(DispositivosMenu));
    await tester.pumpAndSettle();

    // El mismo panel que Ajustes, no una lista reimplementada aquí.
    expect(find.byType(DispositivosPanel), findsOneWidget);
    // El mismo panel que Ajustes: si esto se ve, es que el menú no reimplementó
    // la lista por su cuenta.
    expect(find.text('Medium Phone API 36.1'), findsOneWidget);
    expect(find.text(strings.emulatorsLaunch), findsOneWidget);
    // En compacto no cabe la frase larga; el título corto sí.
    expect(find.text(strings.emulatorsExplainer), findsNothing);
    expect(find.text(strings.sectionEmulators), findsOneWidget);
  });
}

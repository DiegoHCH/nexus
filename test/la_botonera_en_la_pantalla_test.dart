import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer_bar.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/widgets/la_botonera_de_corridas.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// La botonera, en la pantalla de verdad y no en un `Stack` de laboratorio.
///
/// 🔴 **Existe porque no apareció.** Se probó montada en un `Stack` del tamaño
/// de la pantalla y allí salía perfecta; en la app no se veía nada, dos veces
/// seguidas. La causa no era la botonera: el `Stack` del HUD vive dentro de un
/// `Column`, entre la barra de arriba y el compositor, así que **es bastante
/// más bajo que la ventana** — y un `Stack` recorta lo que se sale. El sitio se
/// calculaba con el alto de la ventana y la barra caía justo debajo del
/// recorte.
///
/// La lección, que es la que hace falta escrita: una prueba de geometría en una
/// caja que no es la de verdad **no prueba la geometría**.
const _deviceId = 'emulator-5554';

class _Corridas extends CorridasController {
  @override
  Map<String, Corrida> build() => const {
    _deviceId: Corrida(
      deviceId: _deviceId,
      dispositivo: 'Medium Phone API 36.1',
      proyecto: '/Users/alguien/proyecto',
      configuracion: 'Tienda (dev)',
      plataforma: PlataformaEmulador.android,
      estado: EstadoDeCorrida.corriendo,
      appId: 'abc',
    ),
  };
}

/// Sin carpeta emparejada la casa enseña el emparejamiento y no el HUD, así
/// que no habría dónde mirar.
final _conUnaCarpeta = [
  corridasProvider.overrideWith(_Corridas.new),
  workspaceControllerProvider.overrideWith(
    () => FixedWorkspace(
      const Workspace(
        folders: [
          PairedFolder(
            path: '/Users/alguien/proyecto',
            modality: FolderModality.textOnly,
          ),
        ],
        activePath: '/Users/alguien/proyecto',
      ),
    ),
  ),
];

void main() {
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('con la app corriendo, la botonera se ve entera', (tester) async {
    await pumpScreen(tester, const HomePage(), overrides: _conUnaCarpeta);
    await tester.pump(const Duration(milliseconds: 100));

    final barra = tester.getRect(find.byKey(LaBotoneraDeCorridas.laLlave));
    final hud = tester.getRect(find.byType(LaBotoneraDeCorridas));

    expect(
      find.byKey(LaBotoneraDeCorridas.laLlave),
      findsOneWidget,
      reason: 'la botonera es lo único que gobierna la corrida',
    );
    // Dentro de su caja por los cuatro lados: fuera, el `Stack` la recorta y no
    // se ve — que es literalmente lo que pasó.
    expect(barra.left, greaterThanOrEqualTo(hud.left));
    expect(barra.top, greaterThanOrEqualTo(hud.top));
    expect(barra.right, lessThanOrEqualTo(hud.right));
    expect(
      barra.bottom,
      lessThanOrEqualTo(hud.bottom),
      reason: 'asomaba por debajo del recorte y ahí no se pinta nada',
    );
  });

  // Y no tapa la caja de escribir, que es lo otro que se pidió: flota, no
  // estorba.
  testWidgets('no se pone encima del compositor', (tester) async {
    await pumpScreen(tester, const HomePage(), overrides: _conUnaCarpeta);
    await tester.pump(const Duration(milliseconds: 100));

    final barra = tester.getRect(find.byKey(LaBotoneraDeCorridas.laLlave));
    final compositor = tester.getRect(find.byType(ComposerBar));

    expect(barra.bottom, lessThanOrEqualTo(compositor.top));
  });
}

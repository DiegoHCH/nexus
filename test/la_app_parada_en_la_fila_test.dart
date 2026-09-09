import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/usecases/el_freno_de_la_app.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// **Lo que la fila dice cuando la app está parada.**
///
/// 🔴 Punto 7 del repaso. Una app detenida en una excepción **sigue estando
/// «corriendo» para el daemon** —el proceso vive, `app.started` ya pasó—, así
/// que sin decidirlo la fila diría «Ejecutando» en verde con la app congelada
/// delante. Es la clase de mentira que hace desconfiar de la pantalla entera, y
/// es lo único de esto que no se puede comprobar leyendo el protocolo.
const _deviceId = 'emulator-5554';

const _laParada = LaParadaDeLaApp(
  isolate: 'isolates/1234',
  excepcion: 'Bad state: setState() called during build',
  funcion: 'StocksGate.build',
  archivo: 'package:app/features/stocks/gate.dart',
  posicion: 1897,
  linea: 78,
);

Corrida _corrida({LaParadaDeLaApp? parada, ModoDePausa? freno}) => Corrida(
  deviceId: _deviceId,
  dispositivo: 'Medium Phone API 36.1',
  proyecto: '/Users/alguien/proyecto',
  configuracion: 'Tienda (dev)',
  plataforma: PlataformaEmulador.android,
  estado: EstadoDeCorrida.corriendo,
  appId: 'abc',
  // El VM service es lo que hace que el freno se pueda ofrecer: sin `wsUri` no
  // hay a quién pedírselo.
  url: 'ws://127.0.0.1:52111/abc=/ws',
  freno: freno ?? ModoDePausa.ninguna,
  parada: parada,
);

class _Corridas extends CorridasController {
  _Corridas(this._corridas);

  final Map<String, Corrida> _corridas;

  @override
  Map<String, Corrida> build() => _corridas;
}

List<Object> _con(Corrida corrida) => [
  corridasProvider.overrideWith(() => _Corridas({_deviceId: corrida})),
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

  testWidgets('parada, la fila dice dónde y no «Ejecutando»', (tester) async {
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: _con(_corrida(parada: _laParada, freno: ModoDePausa.sinDueno)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Parada en gate.dart:78 · StocksGate.build'), findsOne);
    expect(
      find.text('corriendo'),
      findsNothing,
      reason: 'para el daemon sigue corriendo, y decirlo así sería mentir',
    );
    // Y los pasos, que solo tienen sentido con la app detenida.
    expect(find.byTooltip('Seguir'), findsOne);
    expect(find.byTooltip('Siguiente línea'), findsOne);
    expect(find.byTooltip('Entrar en la llamada'), findsOne);
    expect(find.byTooltip('Salir de la función'), findsOne);
  });

  // 🔴 **Y esta prueba encontró un desbordamiento de verdad.** La barra mide
  // 380 px fijos —los mide para no bailar al cambiar el texto— y con los cuatro
  // pasos puestos se pasaba **61 px**, que en la app es la franja amarilla de
  // «RenderFlex overflowed». La respuesta no fue apretar los iconos: recargar
  // con la app detenida no recarga nada, primero hay que soltarla.
  //
  // Que esta prueba pase **es** el guardia: un desbordamiento de layout lanza
  // en las pruebas de widget, así que el día que la fila gane otro botón se
  // sabrá aquí y no en una captura de pantalla.
  testWidgets('y con la app parada no se ofrece recargar', (tester) async {
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: _con(_corrida(parada: _laParada, freno: ModoDePausa.sinDueno)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('Recargar'), findsNothing);
    expect(
      find.byTooltip('Parar'),
      findsOne,
      reason: 'parar sí: es la salida de una app que no quieres soltar',
    );
  });

  // 🔴 **Un «entrar en la llamada» con la app corriendo no tiene a dónde
  // entrar**: el VM service contesta un error que nadie ve, y un botón que no
  // hace nada enseña a no pulsarlo.
  testWidgets('corriendo, no hay pasos que dar', (tester) async {
    await pumpScreen(tester, const HomePage(), overrides: _con(_corrida()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('corriendo'), findsOne);
    expect(find.byTooltip('Seguir'), findsNothing);
    expect(find.byTooltip('Siguiente línea'), findsNothing);
  });

  testWidgets('el freno se ofrece con la app arriba y se marca', (
    tester,
  ) async {
    await pumpScreen(tester, const HomePage(), overrides: _con(_corrida()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('Pararse en los errores'), findsOne);
  });

  // Antes de `app.started` no hay isolates a los que ponerle nada, y una
  // corrida de web no tiene VM service al que hablarle: el `url` que trae es
  // http.
  testWidgets('pero no cuando no hay a quién pedírselo', (tester) async {
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: _con(
        Corrida(
          deviceId: _deviceId,
          dispositivo: 'Chrome',
          proyecto: '/Users/alguien/proyecto',
          configuracion: 'Tienda (dev)',
          plataforma: PlataformaEmulador.android,
          estado: EstadoDeCorrida.corriendo,
          appId: 'abc',
          url: 'http://127.0.0.1:52111',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip('Pararse en los errores'), findsNothing);
  });
}

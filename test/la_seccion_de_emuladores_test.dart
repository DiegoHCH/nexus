import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/emulators/presentation/widgets/emuladores_section.dart';

/// La sección de Ajustes: qué botón sale y qué se le pide a la máquina.
///
/// El data source se sustituye entero. Lo que se prueba aquí es la decisión de la
/// pantalla —arrancar o cerrar, en frío o normal— y no que `flutter emulators`
/// funcione: eso ya está probado contra las salidas reales en
/// `los_emuladores_de_la_maquina_test.dart`.
class _Falsa extends EmuladoresDataSource {
  _Falsa(this._emuladores, {this.errorAlListar, this.dispositivos = const []});

  final List<Emulador> _emuladores;
  final List<DispositivoConectado> dispositivos;
  final String? errorAlListar;

  final lanzados = <({String id, bool frio})>[];
  final cerrados = <String>[];
  String? errorAlLanzar;

  /// Si se pone, `lanzar` no vuelve hasta que alguien lo complete. Sirve para
  /// mirar la fila **mientras** arranca, que es la mitad que se rompió en vivo.
  Completer<void>? esperaEnLanzar;

  /// Cuántas veces se ha pedido la lista, y una espera para la segunda. Con eso
  /// se puede mirar la pantalla en el hueco entre «ya lanzó» y «ya tengo la
  /// lista nueva», que es donde se colaba el parpadeo.
  var vecesListado = 0;
  Completer<void>? esperaEnElSegundoListado;

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async {
    vecesListado++;
    // La sección refresca al abrirse, así que el primer listado que ve una
    // prueba es el de arranque y el segundo el de después de actuar.
    if (vecesListado == 3) await esperaEnElSegundoListado?.future;
    return (
      emuladores: vecesListado >= 3 ? _traslanzar ?? _emuladores : _emuladores,
      error: errorAlListar,
    );
  }

  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => dispositivos;

  /// Lo que devuelve la lista a partir del segundo intento, para simular que el
  /// emulador ya arrancó.
  List<Emulador>? _traslanzar;
  set traslanzar(List<Emulador> lista) => _traslanzar = lista;

  @override
  Future<String?> lanzar(
    Emulador emulador, {
    bool frio = false,
    Duration cada = const Duration(seconds: 2),
    int intentos = 45,
  }) async {
    lanzados.add((id: emulador.id, frio: frio));
    await esperaEnLanzar?.future;
    return errorAlLanzar;
  }

  @override
  Future<String?> cerrar(Emulador emulador) async {
    cerrados.add(emulador.id);
    return null;
  }
}

const _android = Emulador(
  id: 'Medium_Phone_API_36.1',
  nombre: 'Medium Phone API 36.1',
  fabricante: 'Generic',
  plataforma: PlataformaEmulador.android,
);

const _ios = Emulador(
  id: 'apple_ios_simulator',
  nombre: 'iOS Simulator',
  fabricante: 'Apple',
  plataforma: PlataformaEmulador.ios,
);

Future<void> _montar(WidgetTester tester, _Falsa falsa) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [emuladoresDataSourceProvider.overrideWithValue(falsa)],
      child: MaterialApp(
        theme: NexusTheme.dark(),
        home: StringsScope(
          strings: const NexusStringsEs(),
          child: const Scaffold(
            body: SingleChildScrollView(child: EmuladoresSection()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const strings = NexusStringsEs();

  testWidgets('uno apagado ofrece arrancar; el que está arriba, cerrar', (
    tester,
  ) async {
    final falsa = _Falsa([
      _android.conEstado(corriendo: true, deviceId: 'emulator-5554'),
      _ios,
    ]);
    await _montar(tester, falsa);

    // **El botón dice lo que va a hacer.** Ofrecer «arrancar» sobre uno que ya
    // corre no rompe nada —arrancarlo dos veces no duplica— pero estaría
    // mintiendo, y de eso no se vuelve.
    expect(find.text(strings.emulatorsClose), findsOneWidget);
    expect(find.text(strings.emulatorsLaunch), findsOneWidget);
  });

  testWidgets('cerrar el de Android va por su dispositivo', (tester) async {
    final falsa = _Falsa([
      _android.conEstado(corriendo: true, deviceId: 'emulator-5554'),
    ]);
    await _montar(tester, falsa);

    await tester.tap(find.text(strings.emulatorsClose));
    await tester.pumpAndSettle();

    expect(falsa.cerrados, ['Medium_Phone_API_36.1']);
  });

  testWidgets('el arranque en frío solo se ofrece en Android', (tester) async {
    await _montar(tester, _Falsa([_android, _ios]));

    // `--cold` no existe para un simulador de iOS: un botón ahí no haría nada
    // distinto del de al lado.
    expect(find.text(strings.emulatorsColdBoot), findsOneWidget);
  });

  testWidgets('en frío llega como en frío, y lo normal como normal', (
    tester,
  ) async {
    final falsa = _Falsa([_android]);
    await _montar(tester, falsa);

    await tester.tap(find.text(strings.emulatorsColdBoot));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.emulatorsLaunch));
    await tester.pumpAndSettle();

    expect(falsa.lanzados, [
      (id: 'Medium_Phone_API_36.1', frio: true),
      (id: 'Medium_Phone_API_36.1', frio: false),
    ]);
  });

  testWidgets('el error de la herramienta se enseña literal', (tester) async {
    // Sin traducir y tal cual, como los del CLI en el panel de MCP: «No se
    // encontró Flutter…» dice qué hacer, y un «no se pudo» manda a la terminal.
    await _montar(
      tester,
      _Falsa(const [], errorAlListar: 'No se encontró Flutter. Se buscó en …'),
    );

    expect(find.textContaining('No se encontró Flutter'), findsOneWidget);
    expect(find.text(strings.emulatorsLaunch), findsNothing);
  });

  testWidgets('un fallo al lanzar sale en pantalla y no se calla', (
    tester,
  ) async {
    // El caso que motiva media feature: `flutter emulators --launch` sale con 0
    // aunque falle, así que sin esto la app se quedaría tan tranquila.
    final falsa = _Falsa([_android])
      ..errorAlLanzar = 'No se encontró ese emulador';
    await _montar(tester, falsa);

    await tester.tap(find.text(strings.emulatorsLaunch));
    await tester.pumpAndSettle();

    expect(find.text('No se encontró ese emulador'), findsOneWidget);
  });

  testWidgets('mientras arranca, la fila enseña el indicador y no un botón', (
    tester,
  ) async {
    // **El fallo visto en vivo.** El comando de lanzar vuelve en ~1 s pero el
    // emulador tarda ~20 s en existir, así que la espera vive dentro de `lanzar`
    // y la fila tiene que estar girando todo ese rato. Antes volvía enseguida a
    // «en frío + Arrancar» con el emulador abriéndose en pantalla, que es la
    // clase de cosa que hace desconfiar de la lista entera.
    final falsa = _Falsa([_android])..esperaEnLanzar = Completer<void>();
    await _montar(tester, falsa);

    await tester.tap(find.text(strings.emulatorsLaunch));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(strings.emulatorsLaunch), findsNothing);
    expect(find.text(strings.emulatorsColdBoot), findsNothing);

    falsa.esperaEnLanzar!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('la fila no vuelve a gris entre lanzar y tener la lista nueva', (
    tester,
  ) async {
    // **El segundo fallo visto en vivo**, y más sutil que el primero: «alcanza a
    // mostrar de nuevo el estado gris con los botones pero después cambió».
    //
    // Pasaba por soltar la fila con un `invalidate` a secas, que dispara el
    // refresco y sigue: en el hueco hasta que llega la lista nueva se pintaba la
    // **vieja**, con el emulador ya arrancado en gris y ofreciendo «Arrancar».
    final falsa = _Falsa([_android])
      ..traslanzar = [
        _android.conEstado(corriendo: true, deviceId: 'emulator-5554'),
      ]
      ..esperaEnElSegundoListado = Completer<void>();
    await _montar(tester, falsa);

    await tester.tap(find.text(strings.emulatorsLaunch));
    await tester.pump();

    // El lanzamiento ya volvió, pero la lista nueva aún no. Aquí es donde se veía
    // el parpadeo, y lo que lo delata es el **botón**: si aparece «Arrancar», la
    // lista vieja se ha colado. Los indicadores son dos ahora —el de la fila y el
    // del refresco en la cabecera— y contarlos sería fijar una decoración.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(
      find.text(strings.emulatorsLaunch),
      findsNothing,
      reason: 'la lista vieja se está colando en el hueco del refresco',
    );
    expect(find.text(strings.emulatorsColdBoot), findsNothing);

    falsa.esperaEnElSegundoListado!.complete();
    await tester.pumpAndSettle();

    // Y al aterrizar, directamente el estado bueno.
    expect(find.text(strings.emulatorsClose), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('los teléfonos enchufados salen aparte y sin botón', (
    tester,
  ) async {
    await _montar(
      tester,
      _Falsa(
        [_android],
        dispositivos: const [
          DispositivoConectado(
            id: '36c56d94',
            nombre: '24069PC21G',
            plataforma: PlataformaEmulador.android,
          ),
        ],
      ),
    );

    expect(find.text(strings.emulatorsConnected), findsOneWidget);
    expect(find.text('24069PC21G'), findsOneWidget);
    // El id debajo, que es lo que pide `-d`.
    expect(find.textContaining('36c56d94'), findsOneWidget);
    // Un solo «Arrancar»: el del emulador. El teléfono no se arranca, ya está.
    expect(find.text(strings.emulatorsLaunch), findsOneWidget);
  });

  testWidgets('sin teléfonos enchufados no hay grupo vacío', (tester) async {
    await _montar(tester, _Falsa([_android]));
    expect(find.text(strings.emulatorsConnected), findsNothing);
  });

  testWidgets('una máquina sin emuladores lo dice', (tester) async {
    await _montar(tester, _Falsa(const []));

    expect(find.text(strings.emulatorsEmpty), findsOneWidget);
  });
}

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
  _Falsa(this._emuladores, {this.errorAlListar});

  final List<Emulador> _emuladores;
  final String? errorAlListar;

  final lanzados = <({String id, bool frio})>[];
  final cerrados = <String>[];
  String? errorAlLanzar;

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async =>
      (emuladores: _emuladores, error: errorAlListar);

  @override
  Future<String?> lanzar(Emulador emulador, {bool frio = false}) async {
    lanzados.add((id: emulador.id, frio: frio));
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

  testWidgets('una máquina sin emuladores lo dice', (tester) async {
    await _montar(tester, _Falsa(const []));

    expect(find.text(strings.emulatorsEmpty), findsOneWidget);
  });
}

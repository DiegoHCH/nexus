import 'dart:async';

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
import 'package:nexus/features/run/data/datasources/configs_data_source.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/run_providers.dart';
import 'package:nexus/features/run/presentation/widgets/correr_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El menú de correr la app en el compositor.
class _ConfigsFalsas extends ConfigsDataSource {
  const _ConfigsFalsas(this.porProyecto);

  final Map<String, List<ConfigDeArranque>> porProyecto;

  @override
  Future<List<ConfigDeArranque>> deProyecto(String proyecto) async =>
      porProyecto[proyecto] ?? const [];
}

class _MaquinaFalsa extends EmuladoresDataSource {
  const _MaquinaFalsa(this._emuladores);

  final List<Emulador> _emuladores;

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async =>
      (emuladores: _emuladores, error: null);

  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => const [];
}

/// Una máquina que no contesta: los proveedores se quedan cargando.
///
/// Es el estado que la interfaz no sabía contar. No es teórico: `adb devices`
/// cuesta 14 ms medidos, pero arrancar su daemon la primera vez o un
/// `devicectl` en frío se van a segundos.
class _MaquinaQueTarda extends EmuladoresDataSource {
  const _MaquinaQueTarda();

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() =>
      Completer<({List<Emulador> emuladores, String? error})>().future;

  @override
  Future<List<DispositivoConectado>> listarDispositivos() =>
      Completer<List<DispositivoConectado>>().future;
}

/// Un controlador con corridas puestas, para mirar la fila sin lanzar procesos.
class _CorridasFijas extends CorridasController {
  _CorridasFijas(this._inicial);

  final Map<String, Corrida> _inicial;

  @override
  Map<String, Corrida> build() => _inicial;
}

const _arrancado = Emulador(
  id: 'Medium_Phone_API_36.1',
  nombre: 'Medium Phone API 36.1',
  fabricante: 'Generic',
  plataforma: PlataformaEmulador.android,
  corriendo: true,
  deviceId: 'emulator-5554',
);

const _apagado = Emulador(
  id: 'Small_Phone',
  nombre: 'Small Phone',
  fabricante: 'Generic',
  plataforma: PlataformaEmulador.android,
);

Future<void> _montar(
  WidgetTester tester, {
  String? proyecto = '/casa/tienda',
  List<ConfigDeArranque> configs = const [
    ConfigDeArranque(nombre: 'Tienda (dev)'),
    ConfigDeArranque(nombre: 'Tienda (prod)'),
  ],
  List<Emulador> emuladores = const [_arrancado, _apagado],
  Map<String, Corrida> corridas = const {},
  EmuladoresDataSource? maquina,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        configsDataSourceProvider.overrideWithValue(
          _ConfigsFalsas({'/casa/tienda': configs}),
        ),
        emuladoresDataSourceProvider.overrideWithValue(
          maquina ?? _MaquinaFalsa(emuladores),
        ),
        corridasProvider.overrideWith(() => _CorridasFijas(corridas)),
      ],
      child: MaterialApp(
        theme: NexusTheme.dark(),
        // En `builder` y no en `home`: el panel abre en el Overlay, por encima.
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: Scaffold(
          body: Center(child: CorrerMenu(proyecto: proyecto)),
        ),
      ),
    ),
  );
  // Con la máquina que tarda no se puede asentar: la rueda gira para siempre y
  // esperar a que pare sería esperar el tope del test.
  if (maquina == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Corrida _corrida({
  EstadoDeCorrida estado = EstadoDeCorrida.corriendo,
  String? appId = 'abc',
  String? progreso,
}) => Corrida(
  deviceId: 'emulator-5554',
  dispositivo: 'Medium Phone API 36.1',
  proyecto: '/casa/tienda',
  configuracion: 'Tienda (dev)',
  plataforma: PlataformaEmulador.android,
  estado: estado,
  appId: appId,
  progreso: progreso,
);

void main() {
  const strings = NexusStringsEs();

  testWidgets('sin nada corriendo el icono está apagado', (tester) async {
    await _montar(tester);
    expect(
      tester.widget<Icon>(find.byType(Icon)).color,
      isNot(NexusColors.dark.accent),
    );
  });

  testWidgets('con la app corriendo el icono se enciende y saca su punto', (
    tester,
  ) async {
    await _montar(tester, corridas: {'emulator-5554': _corrida()});
    expect(
      tester.widget<Icon>(find.byType(Icon)).color,
      NexusColors.dark.accent,
    );
    expect(find.byType(Container), findsOneWidget);
  });

  testWidgets('el panel ofrece las configuraciones de ESE proyecto', (
    tester,
  ) async {
    await _montar(tester);
    await tester.tap(find.byType(CorrerMenu));
    await tester.pumpAndSettle();

    await tester.tap(find.text(strings.runTitle).last);
    await tester.pumpAndSettle();

    expect(find.text('Tienda (dev)'), findsWidgets);
    expect(find.text('Tienda (prod)'), findsWidgets);
  });

  testWidgets('un proyecto sin configuraciones lo dice, no se queda mudo', (
    tester,
  ) async {
    await _montar(tester, configs: const []);
    await tester.tap(find.byType(CorrerMenu));
    await tester.pumpAndSettle();

    expect(find.text(strings.runNoConfigs), findsOneWidget);
    expect(find.text(strings.runStart), findsNothing);
  });

  testWidgets('sin proyecto no hay nada que correr, y se explica', (
    tester,
  ) async {
    await _montar(tester, proyecto: null);
    await tester.tap(find.byType(CorrerMenu));
    await tester.pumpAndSettle();

    expect(find.text(strings.runNoProject), findsOneWidget);
  });

  testWidgets('solo se ofrecen dispositivos encendidos', (tester) async {
    // `flutter run -d` sobre un emulador apagado falla, así que ofrecerlo sería
    // ofrecer ese fallo. Para encenderlo está el icono de al lado.
    await _montar(tester);
    await tester.tap(find.byType(CorrerMenu));
    await tester.pumpAndSettle();

    await tester.tap(find.text(strings.runChooseDevice).last);
    await tester.pumpAndSettle();

    // El id sigue estando —es lo que pide `-d`— pero **con su nombre delante**:
    // un id no dice cuál es cuál.
    expect(find.textContaining('emulator-5554'), findsWidgets);
    expect(find.textContaining('Medium Phone API 36.1'), findsWidgets);
    // Y el apagado no se ofrece, ni por id ni por nombre.
    expect(find.textContaining('Small_Phone'), findsNothing);
    expect(find.textContaining('Small Phone'), findsNothing);
  });

  testWidgets('correr está apagado hasta elegir las dos cosas', (tester) async {
    await _montar(tester);
    await tester.tap(find.byType(CorrerMenu));
    await tester.pumpAndSettle();

    final boton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, strings.runStart),
    );
    expect(boton.onPressed, isNull);
  });

  group('la fila de una corrida', () {
    testWidgets('mientras compila no ofrece recargar, y dice qué compila', (
      tester,
    ) async {
      // Antes de `app.started` no hay a quién pedírselo: un botón que contesta
      // «todavía está compilando» es un botón que no debía estar encendido.
      await _montar(
        tester,
        corridas: {
          'emulator-5554': _corrida(
            estado: EstadoDeCorrida.arrancando,
            appId: null,
            progreso: 'Compilando lib/main.dart',
          ),
        },
      );
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.byTooltip(strings.runReload), findsNothing);
      // **En su propia línea**, no pegado al dispositivo: ahí se cortaba en una
      // letra —«Medium Phone API 36.1 · R…»— y era lo único que decía que algo
      // estaba pasando.
      expect(find.text('Compilando lib/main.dart'), findsOneWidget);
      expect(find.text('Medium Phone API 36.1'), findsOneWidget);
      // Parar sí, que es lo único que se puede hacer con algo que compila.
      expect(find.byTooltip(strings.runStop), findsOneWidget);
    });

    testWidgets('corriendo ofrece recargar, reiniciar y parar', (tester) async {
      await _montar(tester, corridas: {'emulator-5554': _corrida()});
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.byTooltip(strings.runReload), findsOneWidget);
      expect(find.byTooltip(strings.runRestart), findsOneWidget);
      expect(find.byTooltip(strings.runStop), findsOneWidget);
      // Y se dice con qué entorno corre: dos corridas iguales serían
      // indistinguibles y «¿esto es dev o prod?» no tendría respuesta.
      expect(find.text('Tienda (dev)'), findsWidgets);
    });

    testWidgets('parando no vuelve a ofrecer parar', (tester) async {
      await _montar(
        tester,
        corridas: {'emulator-5554': _corrida(estado: EstadoDeCorrida.parando)},
      );
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.byTooltip(strings.runStop), findsNothing);
      expect(find.text(strings.runStopping), findsOneWidget);
    });
  });

  group('la configuración por defecto', () {
    testWidgets('la recordada aparece puesta al abrir', (tester) async {
      SharedPreferences.setMockInitialValues({
        'run.configPorDefecto': '{"/casa/tienda":"Tienda (prod)"}',
      });
      await _montar(tester);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      // Con catorce configuraciones, elegir a mano cada vez es un peaje diario.
      expect(find.text('Tienda (prod)'), findsWidgets);
      final boton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, strings.runStart),
      );
      // Falta el dispositivo, así que sigue apagado — pero la mitad ya está.
      expect(boton.onPressed, isNull);
    });

    testWidgets('una recordada que ya no existe no se ofrece', (tester) async {
      // **Por esto se guarda el nombre y no un índice.** Alguien borra esa
      // configuración del launch.json, y lo correcto es pedir que elijas otra —
      // no correr la que quedó en ese hueco.
      SharedPreferences.setMockInitialValues({
        'run.configPorDefecto': '{"/casa/tienda":"La que ya no está"}',
      });
      await _montar(tester);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.text('La que ya no está'), findsNothing);
      expect(find.text(strings.runTitle), findsWidgets);
    });

    testWidgets('cada proyecto recuerda la suya', (tester) async {
      // Una preferencia global sería peor que ninguna: pondría el flavor de un
      // repo como cabeza de otro.
      SharedPreferences.setMockInitialValues({
        'run.configPorDefecto': '{"/casa/otro":"Tienda (prod)"}',
      });
      await _montar(tester);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.text('Tienda (prod)'), findsNothing);
    });

    testWidgets('una preferencia corrupta no impide abrir el menú', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'run.configPorDefecto': 'esto no es json',
      });
      await _montar(tester);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.text(strings.runTitle), findsWidgets);
    });
  });

  group('el registro', () {
    testWidgets('se abre desde la fila y el botón queda marcado', (
      tester,
    ) async {
      // Se recogía y no se enseñaba en ningún sitio, que es tenerlo y no tenerlo.
      await _montar(tester, corridas: {'emulator-5554': _corrida()});
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsNothing);

      await tester.tap(find.byTooltip(strings.runLogs));
      await tester.pumpAndSettle();

      // Vacío se dice, no se deja en blanco: un hueco negro se lee como roto.
      expect(find.text(strings.runCompiling), findsWidgets);
    });

    testWidgets('enseña lo que imprimió la corrida', (tester) async {
      // Cuando una compilación falla, el motivo está aquí y en ningún otro sitio.
      await _montar(tester, corridas: {'emulator-5554': _corrida()});
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      final contenedor = tester.element(find.byType(CorrerMenu));
      ProviderScope.containerOf(contenedor, listen: false)
          .read(registrosProvider.notifier)
          .anota('emulator-5554', "lib/main.dart:12:3: Error: Expected ';'");
      await tester.pump();

      await tester.tap(find.byTooltip(strings.runLogs));
      await tester.pumpAndSettle();

      expect(find.textContaining("Expected ';'"), findsOneWidget);
    });

    testWidgets('un bloque con saltos dentro se parte en líneas', (
      tester,
    ) async {
      // Gradle imprime párrafos: sin partirlos el registro son cuatro líneas
      // gigantes y el tope de 200 no significa nada.
      await _montar(tester, corridas: {'emulator-5554': _corrida()});
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(CorrerMenu)),
        listen: false,
      );
      contenedor
          .read(registrosProvider.notifier)
          .anota('emulator-5554', 'una\n\notra\ntercera');

      expect(contenedor.read(registrosProvider)['emulator-5554'], [
        'una',
        'otra',
        'tercera',
      ]);
    });

    testWidgets('el registro está acotado: se quedan las últimas', (
      tester,
    ) async {
      // Un `flutter run` de un proyecto grande escupe miles de líneas, y
      // guardarlas todas es una fuga de memoria con forma de función útil.
      await _montar(tester);
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(CorrerMenu)),
        listen: false,
      );
      final notifier = contenedor.read(registrosProvider.notifier);
      for (var i = 0; i < RegistrosController.tope + 50; i++) {
        notifier.anota('emulator-5554', 'linea $i');
      }

      final guardadas = contenedor.read(registrosProvider)['emulator-5554']!;
      expect(guardadas.length, RegistrosController.tope);
      // Las últimas, que son las que se leen cuando algo falla.
      expect(guardadas.last, 'linea ${RegistrosController.tope + 49}');
    });
  });

  group('la recarga automática', () {
    testWidgets('viene apagada de fábrica', (tester) async {
      // Recargar la app sin que nadie lo pida es una sorpresa la primera vez.
      SharedPreferences.setMockInitialValues({});
      await _montar(tester);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      final boton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.bolt),
      );
      expect(boton.color, isNot(NexusColors.dark.accent));
    });

    testWidgets('encendida se recuerda y se ve marcada', (tester) async {
      SharedPreferences.setMockInitialValues({'run.autoRecarga': true});
      await _montar(tester);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.bolt))
            .color,
        NexusColors.dark.accent,
      );
    });

    testWidgets('con nada corriendo no hace nada ni revienta', (tester) async {
      await _montar(tester);
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(CorrerMenu)),
        listen: false,
      );

      await expectLater(
        contenedor
            .read(corridasProvider.notifier)
            .alTerminarUnEncargo(
              proyecto: '/casa/tienda',
              rutas: const ['lib/a.dart'],
              diff: '',
            ),
        completes,
      );
    });

    testWidgets('lo que pide recompilar se dice y NO se recompila', (
      tester,
    ) async {
      // Son minutos y aquí hay alguien esperando: el mismo criterio de los
      // comandos bloqueados. Se dice y la decisión se deja en quien mira.
      await _montar(tester, corridas: {'emulator-5554': _corrida()});
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(CorrerMenu)),
        listen: false,
      );

      await contenedor
          .read(corridasProvider.notifier)
          .alTerminarUnEncargo(
            proyecto: '/casa/tienda',
            rutas: const ['android/app/build.gradle'],
            diff: '',
          );

      final registro = contenedor
          .read(registrosProvider)['emulator-5554']!
          .join('\n');
      expect(registro, contains('recompilar'));
      // La corrida sigue en pie: no se paró ni se relanzó nada.
      expect(contenedor.read(corridasProvider).length, 1);
    });

    testWidgets('anota el motivo, que si no parece un capricho', (
      tester,
    ) async {
      await _montar(tester, corridas: {'emulator-5554': _corrida()});
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(CorrerMenu)),
        listen: false,
      );

      await contenedor
          .read(corridasProvider.notifier)
          .alTerminarUnEncargo(
            proyecto: '/casa/tienda',
            rutas: const ['lib/a.dart'],
            diff: '--- a/lib/a.dart\n+++ b/lib/a.dart\n+enum Estado { uno }',
          );

      final registro = contenedor
          .read(registrosProvider)['emulator-5554']!
          .join('\n');
      expect(registro, contains('reiniciando'));
      expect(registro, contains('enum'));
    });

    testWidgets('un proyecto distinto no se toca', (tester) async {
      await _montar(tester, corridas: {'emulator-5554': _corrida()});
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(CorrerMenu)),
        listen: false,
      );

      await contenedor
          .read(corridasProvider.notifier)
          .alTerminarUnEncargo(
            proyecto: '/casa/otro',
            rutas: const ['lib/a.dart'],
            diff: '',
          );

      expect(contenedor.read(registrosProvider)['emulator-5554'], isNull);
    });
  });

  group('los tres estados del selector de dispositivos', () {
    // 🔴 Reportado mirando la pantalla: «no tiene un loading mientras no hay
    // dispositivos disponibles, entonces uno le da clic y parece que se hubiera
    // quedado pegada la interfaz». No lo parecía: estaba buscando. Los dos
    // estados iban aplanados a uno con un `?? const []`.
    testWidgets('mientras busca lo dice, en vez de parecer colgado', (
      tester,
    ) async {
      await _montar(tester, maquina: const _MaquinaQueTarda());
      await tester.tap(find.byType(CorrerMenu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(strings.runSearchingDevices), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(
        find.text(strings.runNoDevices),
        findsNothing,
        reason: 'todavía no se sabe: decir «ninguno» sería afirmar de más',
      );
    });

    testWidgets('sin ninguno conectado lo dice, y no se queda mudo', (
      tester,
    ) async {
      await _montar(tester, emuladores: const []);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.text(strings.runNoDevices), findsOneWidget);
      expect(find.text(strings.runSearchingDevices), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('y con alguno, la pista vuelve a ser elegir', (tester) async {
      await _montar(tester);
      await tester.tap(find.byType(CorrerMenu));
      await tester.pumpAndSettle();

      expect(find.text(strings.runChooseDevice), findsOneWidget);
      expect(find.text(strings.runNoDevices), findsNothing);
    });
  });
}

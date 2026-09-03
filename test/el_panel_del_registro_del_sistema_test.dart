import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/data/datasources/registros_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/emulators/presentation/providers/registro_del_sistema_providers.dart';
import 'package:nexus/features/run/data/datasources/configs_data_source.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/run_providers.dart';
import 'package:nexus/features/run/presentation/widgets/correr_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El panel del registro del sistema, abierto de verdad desde el menú.
///
/// 🔴 **Es la mitad de la respuesta a «por qué se cayó».** Un crash nativo no
/// pasa por el daemon de Flutter, así que el registro de arriba no lo ve — y
/// hasta ahora eso obligaba a salir a la terminal.
const _deviceId = 'emulator-5554';

class _Corridas extends CorridasController {
  _Corridas(this._inicial);
  final Map<String, Corrida> _inicial;
  @override
  Map<String, Corrida> build() => _inicial;
}

class _Configs extends ConfigsDataSource {
  const _Configs();
  @override
  Future<List<ConfigDeArranque>> deProyecto(String proyecto) async => const [
    ConfigDeArranque(nombre: 'Tienda (dev)'),
  ];
}

class _SinMaquinas extends EmuladoresDataSource {
  const _SinMaquinas();
  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async =>
      (emuladores: const <Emulador>[], error: null);
  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => const [];
}

/// Un dispositivo que dice lo que se le mande, cuando se le mande.
class _Dispositivo extends RegistrosDataSource {
  _Dispositivo(this.control);
  final StreamController<LineaDeRegistro> control;
  @override
  Stream<LineaDeRegistro> escuchar({
    required PlataformaEmulador plataforma,
    required String deviceId,
    bool desdeAhora = true,
  }) => control.stream;
}

void main() {
  const strings = NexusStringsEs();
  late StreamController<LineaDeRegistro> dice;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dice = StreamController<LineaDeRegistro>.broadcast();
  });
  tearDown(() => dice.close());

  Future<void> abrirElRegistro(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configsDataSourceProvider.overrideWithValue(const _Configs()),
          emuladoresDataSourceProvider.overrideWithValue(const _SinMaquinas()),
          registrosDataSourceProvider.overrideWithValue(_Dispositivo(dice)),
          corridasProvider.overrideWith(
            () => _Corridas({
              _deviceId: const Corrida(
                deviceId: _deviceId,
                dispositivo: 'Medium Phone API 36.1',
                proyecto: '/casa/tienda',
                configuracion: 'Tienda (dev)',
                plataforma: PlataformaEmulador.android,
                estado: EstadoDeCorrida.corriendo,
                appId: 'abc',
              ),
            }),
          ),
        ],
        child: MaterialApp(
          theme: NexusTheme.dark(),
          builder: (context, child) =>
              StringsScope(strings: strings, child: child!),
          home: const Scaffold(
            body: Center(child: CorrerMenu(proyecto: '/casa/tienda')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CorrerMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(strings.runSystemLog));
    await tester.pumpAndSettle();
  }

  testWidgets('se abre escuchando, y lo dice en vez de dejar un hueco', (
    tester,
  ) async {
    await abrirElRegistro(tester);

    expect(find.text(strings.runSystemLogWaiting), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo que dice el teléfono aparece', (tester) async {
    await abrirElRegistro(tester);

    dice.add(
      const LineaDeRegistro(
        nivel: NivelDeRegistro.fatal,
        etiqueta: 'libc',
        texto: 'Fatal signal 11 (SIGSEGV)',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Fatal signal 11'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // El filtro es de quien mira, no del teléfono: se sube una vez y vale.
  testWidgets('subir el nivel esconde lo que ya no interesa', (tester) async {
    await abrirElRegistro(tester);

    dice
      ..add(
        const LineaDeRegistro(
          nivel: NivelDeRegistro.info,
          etiqueta: 'Choreographer',
          texto: 'skipped frames',
        ),
      )
      ..add(
        const LineaDeRegistro(
          nivel: NivelDeRegistro.error,
          etiqueta: 'AndroidRuntime',
          texto: 'FATAL EXCEPTION',
        ),
      );
    await tester.pumpAndSettle();
    expect(find.textContaining('skipped frames'), findsOneWidget);

    await tester.tap(find.text(strings.nivelTodo));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.nivelDesdeAvisos));
    await tester.pumpAndSettle();

    expect(find.textContaining('skipped frames'), findsNothing);
    expect(find.textContaining('FATAL EXCEPTION'), findsOneWidget);
  });

  // Un volcado real son cientos de líneas largas, y es justo cuando hay que
  // poder leerlo.
  testWidgets('un volcado largo no desborda', (tester) async {
    await abrirElRegistro(tester);

    for (var i = 0; i < 200; i++) {
      dice.add(
        LineaDeRegistro(
          nivel: NivelDeRegistro.error,
          etiqueta: 'AndroidRuntime',
          texto:
              '\tat com.ejemplo.app.pantallas.perfil.PerfilFragment'
              '.onCreateView(PerfilFragment.kt:$i)',
        ),
      );
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('PerfilFragment.kt:'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

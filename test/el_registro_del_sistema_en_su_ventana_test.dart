import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/core/platform/lo_que_pide_la_pagina.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/data/datasources/registros_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/emulators/presentation/providers/registro_del_sistema_providers.dart';
import 'package:nexus/features/run/data/datasources/configs_data_source.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/usecases/el_registro_como_html.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/la_ventana_del_registro.dart';
import 'package:nexus/features/run/presentation/providers/run_providers.dart';
import 'package:nexus/features/run/presentation/widgets/correr_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El registro del sistema, abierto de verdad desde el menú y **en su ventana**.
///
/// 🔴 **Es la mitad de la respuesta a «por qué se cayó».** Un crash nativo no
/// pasa por el daemon de Flutter, así que el registro de la corrida no lo ve — y
/// hasta ahora eso obligaba a salir a la terminal.
///
/// Lo que cambió es dónde se lee: era un cuadro que crecía dentro del menú y
/// ahora es una página que se escribe y se abre en una ventana del sistema. Por
/// eso lo que se mira aquí ya no son widgets sino **lo que se pintó**, y los
/// botones de la página —el nivel, la pausa— llegan como lo que son: enlaces
/// `nexus://` que el visor reenvía.
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

/// Las páginas que se habrían escrito, sin tocar el disco ni abrir ventanas.
class _Pintor {
  final paginas = <({String nombre, String html, bool primeraVez})>[];

  Future<void> pinta(
    String nombre,
    String html, {
    required bool primeraVez,
  }) async => paginas.add((nombre: nombre, html: html, primeraVez: primeraVez));

  String get ultima => paginas.last.html;
}

void main() {
  const strings = NexusStringsEs();
  late StreamController<LineaDeRegistro> dice;
  late _Pintor pintor;
  late ProviderContainer contenedor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dice = StreamController<LineaDeRegistro>.broadcast();
    pintor = _Pintor();
  });
  tearDown(() {
    LoQuePideLaPagina.olvidarTodo();
    return dice.close();
  });

  /// Lo que manda el visor cuando se pulsa un enlace de la página.
  Future<void> comoSiPidieran(String que, {String ruta = ''}) {
    final canal = LoQuePideLaPagina.canal;
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          canal.name,
          canal.codec.encodeMethodCall(
            MethodCall('desdeLaPagina', {'que': que, 'ruta': ruta}),
          ),
          (_) {},
        );
  }

  /// Lo que llega por el teléfono no se pinta al momento: se junta lo de este
  /// rato y se escribe una vez. Ver [LasVentanasDelRegistro.ritmo].
  Future<void> alRitmo(WidgetTester tester) async {
    await tester.pump(
      LasVentanasDelRegistro.ritmo + const Duration(milliseconds: 20),
    );
    await tester.pumpAndSettle();
  }

  Future<void> abrirElRegistro(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configsDataSourceProvider.overrideWithValue(const _Configs()),
          emuladoresDataSourceProvider.overrideWithValue(const _SinMaquinas()),
          registrosDataSourceProvider.overrideWithValue(_Dispositivo(dice)),
          elPintorDeVentanasProvider.overrideWithValue(pintor.pinta),
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
    contenedor = ProviderScope.containerOf(
      tester.element(find.byType(CorrerMenu)),
      listen: false,
    );
    await tester.tap(find.byTooltip(strings.runSystemLog));
    await tester.pumpAndSettle();
  }

  /// Los de la página, que salen del idioma elegido en Ajustes: la ventana no
  /// está dentro del árbol de la app y no ve su `StringsScope`.
  NexusStrings deLaPagina() => contenedor.read(stringsProvider);

  testWidgets('abrirlo escribe su página y enciende la escucha', (
    tester,
  ) async {
    await abrirElRegistro(tester);

    expect(pintor.paginas.single.nombre, 'sistema-emulator-5554');
    expect(pintor.paginas.single.primeraVez, isTrue);
    // Vacío se dice, no se deja en blanco: un hueco negro se lee como roto y lo
    // que pasa es que todavía no ha dicho nada.
    expect(pintor.ultima, contains(deLaPagina().runSystemLogWaiting));
    expect(
      contenedor
          .read(registroDelSistemaProvider.notifier)
          .escuchando(_deviceId),
      isTrue,
      reason: 'abrir la ventana es la petición: antes lo era abrir el cuadro',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo que dice el teléfono aparece en la página', (tester) async {
    await abrirElRegistro(tester);

    dice.add(
      const LineaDeRegistro(
        nivel: NivelDeRegistro.fatal,
        etiqueta: 'libc',
        texto: 'Fatal signal 11 (SIGSEGV)',
      ),
    );
    await alRitmo(tester);

    expect(pintor.ultima, contains('Fatal signal 11'));
    expect(pintor.ultima, contains('libc'));
    expect(
      pintor.paginas.last.primeraVez,
      isFalse,
      reason: 'ya estaba abierta',
    );
    expect(tester.takeException(), isNull);
  });

  // 🔴 **Cien líneas no son cien archivos.** Un `logcat` de un teléfono de
  // verdad son cientos por minuto, y escribir el archivo por cada una es
  // machacar el disco y pedirle al visor una recarga por línea.
  testWidgets('una ráfaga se escribe una sola vez', (tester) async {
    await abrirElRegistro(tester);
    final antes = pintor.paginas.length;

    for (var i = 0; i < 100; i++) {
      dice.add(
        LineaDeRegistro(
          nivel: NivelDeRegistro.error,
          etiqueta: 'AndroidRuntime',
          texto: '\tat com.ejemplo.PerfilFragment.onCreateView(Perfil.kt:$i)',
        ),
      );
    }
    await alRitmo(tester);

    expect(pintor.paginas.length - antes, 1);
    expect(pintor.ultima, contains('Perfil.kt:99'));
  });

  // El filtro es de quien mira, no del teléfono: se sube una vez y vale. Y
  // ahora se sube desde la página, que es donde se está mirando.
  testWidgets('subir el nivel desde la página esconde lo que no interesa', (
    tester,
  ) async {
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
    await alRitmo(tester);
    expect(pintor.ultima, contains('skipped frames'));

    await comoSiPidieran(ElRegistroComoHtml.que, ruta: '/nivel');
    await tester.pumpAndSettle();

    expect(pintor.ultima, isNot(contains('skipped frames')));
    expect(pintor.ultima, contains('FATAL EXCEPTION'));
    expect(
      pintor.ultima,
      contains(deLaPagina().nivelDesdeAvisos),
      reason: 'el chip dice en qué nivel está, o subirlo es a ciegas',
    );
  });

  // 🔴 **Se podía encender y no apagar.** El `logcat` seguía vivo el resto de la
  // sesión —un proceso, el cable ocupado y batería del teléfono— aunque
  // cerraras el panel.
  testWidgets('y se puede apagar desde la página', (tester) async {
    await abrirElRegistro(tester);

    await comoSiPidieran(ElRegistroComoHtml.que, ruta: '/escucha/$_deviceId');
    await tester.pumpAndSettle();

    expect(
      contenedor
          .read(registroDelSistemaProvider.notifier)
          .escuchando(_deviceId),
      isFalse,
    );
    expect(pintor.ultima, contains(deLaPagina().runSystemLogOff));
  });

  // Cerrar la ventana no lo sabe nadie salvo el visor, que lo dice. Sin esto se
  // seguiría escribiendo un archivo cada trescientos milisegundos para algo que
  // ya no existe, y el botón del panel seguiría marcado.
  testWidgets('al cerrarla, se deja de pintar', (tester) async {
    await abrirElRegistro(tester);
    final antes = pintor.paginas.length;

    await comoSiPidieran(
      'cerrada',
      ruta: '/casa/.ventana/sistema-emulator-5554.html',
    );
    await tester.pumpAndSettle();

    expect(contenedor.read(lasVentanasDelRegistroProvider), isEmpty);

    dice.add(
      const LineaDeRegistro(
        nivel: NivelDeRegistro.error,
        etiqueta: 'libc',
        texto: 'ya no hay quien lo lea',
      ),
    );
    await alRitmo(tester);

    expect(pintor.paginas.length, antes);
  });
}

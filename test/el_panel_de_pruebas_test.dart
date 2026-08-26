import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/design_system/selector_compacto.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/pruebas_sheet.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';

/// El panel de pruebas: lanzar, ver correr, y el historial.
class _Maquina extends EmuladoresDataSource {
  const _Maquina({this.encendidos = 1, this.conIphone = false});

  /// Cuántos emuladores hay arriba. Con dos hay que elegir; con uno, no.
  final int encendidos;

  /// Si además hay un iPhone enchufado. Aparte y apagado por defecto para que las
  /// pruebas de «no hay nada» y «hay uno solo» sigan diciendo eso.
  final bool conIphone;

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async => (
    emuladores: [
      for (var i = 0; i < 2; i++)
        Emulador(
          id: 'Emu$i',
          nombre: 'Medium Phone $i',
          fabricante: 'Generic',
          plataforma: PlataformaEmulador.android,
          corriendo: i < encendidos,
          deviceId: i < encendidos ? 'emulator-555$i' : null,
        ),
    ],
    error: null,
  );

  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => conIphone
      ? const [
          DispositivoConectado(
            id: '00008030-000C390C1AC0C02E',
            nombre: 'iPhone 11',
            plataforma: PlataformaEmulador.ios,
          ),
        ]
      : const [];
}

class _Borrados extends E2eDataSource {
  const _Borrados(this.borrados, {this.instalada, this.enGit});

  final List<String> borrados;

  /// Qué contesta la comprobación de instalación: `null` es «no se pudo saber».
  final bool? instalada;

  /// Y la de git, con el mismo `null` de «no se pudo saber».
  final bool? enGit;

  @override
  Future<bool?> estaEnGit(String ruta) async => enGit;

  @override
  Future<bool?> estaInstalada({
    required String deviceId,
    required String appId,
  }) async => instalada;

  @override
  Future<void> abreElInforme(String registro) async => borrados.add('ver:$registro');

  @override
  Future<void> pintaLaCorrida({
    required String flow,
    required String html,
    required bool primeraVez,
    required String raizDeLaVentana,
  }) async {}

  @override
  Future<String?> borrar(String carpeta) async {
    borrados.add(carpeta);
    return null;
  }

  @override
  Future<String?> borrarPrueba(String ruta) async {
    borrados.add(ruta);
    return null;
  }

  /// Un tamaño fijo por corrida: lo que se comprueba es que el grupo lo sume y lo
  /// enseñe, no cómo se mide —eso tiene su propia prueba contra el disco.
  @override
  int bytesDe(String ruta) => 2048;
}

/// Un controlador que apunta los lanzamientos en vez de lanzar.
class _Lanzamientos extends PruebaEnMarchaController {
  _Lanzamientos(this.lanzados);

  final List<String> lanzados;

  @override
  PruebaEnMarcha? build() => null;

  @override
  Future<String?> lanzar({
    required Prueba prueba,
    required String proyecto,
    required String deviceId,
    required String perfil,
  }) async {
    lanzados.add('${prueba.nombre}@$deviceId');
    return null;
  }
}

CorridaDePrueba _corrida({
  String flow = 'login',
  ComoAcabo como = ComoAcabo.bien,
  String? proyecto = '/casa/tienda',
  int pasos = 8,
  int bien = 8,
  String carpeta = '/donde/sea/login',
  String? dispositivo,
}) => CorridaDePrueba(
  carpeta: carpeta,
  flow: flow,
  cuando: DateTime(2026, 8, 25, 16, 30),
  comoAcabo: como,
  proyecto: proyecto,
  pasos: pasos,
  pasosBien: bien,
  dispositivo: dispositivo,
);

Future<void> _abrir(
  WidgetTester tester, {
  String? proyecto = '/casa/tienda',
  List<Prueba> pruebas = const [Prueba(ruta: '/casa/tienda/.maestro/login.yaml', nombre: 'login')],
  List<CorridaDePrueba>? corridas,
  PruebaEnMarcha? enMarcha,
  int encendidos = 1,
  bool conIphone = false,
  List<String>? borrados,
  bool? instalada,
  bool? enGit,
  List<String>? lanzados,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        emuladoresDataSourceProvider.overrideWithValue(
          _Maquina(encendidos: encendidos, conIphone: conIphone),
        ),
        e2eDataSourceProvider.overrideWithValue(
          _Borrados(borrados ?? [], instalada: instalada, enGit: enGit),
        ),
        pruebasProvider('/casa/tienda').overrideWith((ref) async => pruebas),
        corridasDePruebaProvider.overrideWith(
          (ref) async => corridas ?? const [],
        ),
        if (enMarcha != null)
          pruebaEnMarchaProvider.overrideWith(() => _EnMarchaFija(enMarcha)),
        if (lanzados != null)
          pruebaEnMarchaProvider.overrideWith(() => _Lanzamientos(lanzados)),
      ],
      child: MaterialApp(
        theme: NexusTheme.dark(),
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: Scaffold(body: PruebasSheet(proyecto: proyecto)),
      ),
    ),
  );
  // **Pumps acotados y no `pumpAndSettle`.** Una prueba viva enseña un indicador
  // de progreso indeterminado, que nunca deja de animarse: `pumpAndSettle` se
  // queda esperando el final de una animación que no termina y se rinde por
  // plazo. Dos pumps bastan para resolver los futuros y pintar.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _EnMarchaFija extends PruebaEnMarchaController {
  _EnMarchaFija(this._valor);

  final PruebaEnMarcha _valor;

  @override
  PruebaEnMarcha? build() => _valor;
}

/// Un paso cualquiera del archivo. El número no importa en estas pruebas: lo que
/// se mira es la hoja, y los números tienen su propia prueba en el lector.
PasoDelFlow _paso(String texto) => PasoDelFlow(linea: 1, texto: texto);

/// Una línea de salida de un paso ya terminado, como la escribe Maestro.
///
/// **El avance se cuenta de la salida y no de un número que se pasa**, así que
/// aquí hay que darle salida de verdad: era `terminados: 1` y ahora es la línea que
/// produce ese 1. Es más largo de escribir y es lo mismo que ve la app.
String _hecho(String texto) => '$texto... COMPLETED\n';

/// Tocar algo que va a leer del disco, y esperar de verdad.
///
/// **`runAsync` no es opcional aquí.** `testWidgets` corre en tiempo falso y ahí
/// la E/S real no completa nunca: repetir una corrida lee el `.yaml` de la prueba
/// antes de lanzar —para saber el `appId` y avisar si la app no está instalada— y
/// sin esto ese `await` se queda colgado, el lanzamiento no llega, y la prueba
/// falla diciendo que no se lanzó nada. Que es lo que pasó.
Future<void> _tocarYEsperar(WidgetTester tester, Finder que) async {
  await tester.runAsync(() async {
    await tester.tap(que);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

void main() {
  const strings = NexusStringsEs();

  group('lanzar', () {
    testWidgets('salen las pruebas del proyecto con su botón', (tester) async {
      await _abrir(tester);
      expect(find.text('login'), findsOneWidget);
      expect(find.text(strings.e2eRun), findsOneWidget);
    });

    testWidgets('un proyecto sin pruebas lo dice', (tester) async {
      await _abrir(tester, pruebas: const []);
      expect(find.text(strings.e2eNone), findsOneWidget);
    });

    testWidgets('sin dispositivo encendido se explica y no se lanza', (
      tester,
    ) async {
      // `maestro test --device` contra un emulador apagado falla: ofrecerlo sería
      // ofrecer ese fallo, así que se dice antes.
      await _abrir(tester, encendidos: 0);
      await tester.tap(find.text(strings.e2eRun));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(strings.e2eNoDevice), findsOneWidget);
    });

    testWidgets('con una corriendo no se puede lanzar otra', (tester) async {
      // Dos corridas de Maestro sobre el mismo dispositivo se pelean por su
      // driver.
      await _abrir(
        tester,
        enMarcha: PruebaEnMarcha(
          flow: 'login',
          delFlow: [_paso('launchApp')],
        ),
      );

      final boton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, strings.e2eRun),
      );
      expect(boton.onPressed, isNull);
    });
  });

  group('el historial', () {
    testWidgets('sin corridas se explica en vez de dejar un hueco', (
      tester,
    ) async {
      await _abrir(tester);
      expect(find.text(strings.e2eNoRuns), findsOneWidget);
    });

    testWidgets('cada corrida dice cómo acabó y por dónde iba', (tester) async {
      await _abrir(
        tester,
        corridas: [_corrida(como: ComoAcabo.mal, bien: 2)],
      );

      // «2/8» dice dónde se rompió sin abrir nada.
      expect(find.textContaining('2/8'), findsOneWidget);
      expect(find.textContaining(strings.e2eFailed), findsOneWidget);
    });

    testWidgets('**las que no se pudieron atribuir se enseñan igual**', (
      tester,
    ) async {
      // No saber de qué proyecto salió una corrida es un problema nuestro;
      // esconderla se lo pasaría al usuario como historial incompleto.
      await _abrir(
        tester,
        corridas: [
          _corrida(),
          _corrida(flow: 'explora', proyecto: null, carpeta: '/otro/explora'),
        ],
      );

      expect(find.text(strings.e2eUnattributed), findsOneWidget);
      expect(find.text('explora'), findsOneWidget);
    });

    testWidgets('borrar una corrida borra su carpeta y solo esa', (
      tester,
    ) async {
      final borrados = <String>[];
      await _abrir(
        tester,
        corridas: [_corrida(carpeta: '/donde/sea/login')],
        borrados: borrados,
      );

      await tester.tap(find.text(strings.e2eDelete));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // **Nunca el `.yaml`**: lo que se borra aquí es reproducible, el flow es
      // código del usuario y vive en git.
      expect(borrados, ['/donde/sea/login']);
    });
  });

  group('elegir dónde correrla', () {
    testWidgets('con dos encendidos hay que elegir, y se ofrece', (
      tester,
    ) async {
      // **Lo que se reportó**: con el Redmi enchufado y un emulador arriba había
      // dos, y coger el primero era decidir por el usuario en silencio.
      await _abrir(tester, encendidos: 2);

      expect(find.byType(SelectorCompacto), findsOneWidget);
      expect(find.text(strings.e2eDevice), findsOneWidget);
    });

    testWidgets('con uno solo no se pregunta', (tester) async {
      // Una pregunta con una sola respuesta no es una pregunta.
      await _abrir(tester);
      expect(find.byType(SelectorCompacto), findsNothing);
    });

    testWidgets('sin elegir con dos, se pide en vez de adivinar', (
      tester,
    ) async {
      await _abrir(tester, encendidos: 2);
      await tester.tap(find.text(strings.e2eRun));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(strings.e2eDevice), findsWidgets);
    });
  });

  group('de quién son las pruebas', () {
    testWidgets('la lista dice de qué proyecto es', (tester) async {
      // El historial ya lo decía y la lista no, así que se leía como si las
      // pruebas fueran de nadie.
      await _abrir(tester);
      expect(find.text('tienda'), findsOneWidget);
    });
  });

  group('borrar una prueba', () {
    testWidgets('el primer toque avisa de que borra del repo', (tester) async {
      // Es código del usuario: se ofrece porque git lo recupera, y eso se dice
      // antes y no después. `enGit: true` porque **la frase ya depende de git**:
      // el aviso que se promete es este solo cuando el archivo está commiteado.
      final borrados = <String>[];
      await _abrir(tester, borrados: borrados, enGit: true);

      await tester.tap(find.byTooltip(strings.e2eDeleteTest));
      await tester.pump();

      // La advertencia va en el tooltip del mismo botón: dice qué va a hacer sin
      // ocupar una línea, y con dos palabras escritas la fila desbordaba.
      expect(find.byTooltip(strings.e2eDeleteTestAsk), findsOneWidget);
      expect(borrados, isEmpty, reason: 'borró al primer toque');
    });

    testWidgets('el segundo borra el archivo, y solo ese', (tester) async {
      final borrados = <String>[];
      await _abrir(tester, borrados: borrados, enGit: true);

      await tester.tap(find.byTooltip(strings.e2eDeleteTest));
      await tester.pump();
      await tester.tap(find.byTooltip(strings.e2eDeleteTestAsk));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(borrados, ['/casa/tienda/.maestro/login.yaml']);
    });
  });

  group('la prueba corriendo vive en otra vista', () {
    testWidgets('la hoja solo avisa, con su puerta', (tester) async {
      // La vista de una prueba en marcha se mira mientras avanza; compartir sitio
      // con una lista que no cambia la dejaba en un rincón.
      await _abrir(
        tester,
        enMarcha: PruebaEnMarcha(
          flow: 'login',
          delFlow: [_paso('launchApp'), _paso('tapOn: x')],
          salida: _hecho('Launch app "com.ejemplo"'),
        ),
      );

      expect(find.textContaining('login · 1/2'), findsOneWidget);
      expect(find.text(strings.e2eSee), findsOneWidget);
      // Los pasos no se pintan aquí ni en ninguna pantalla de la app: van en una
      // ventana del sistema aparte, para no impedir seguir trabajando.
      expect(find.text('launchApp'), findsNothing);
    });
  });

  group('antes de correr', () {
    testWidgets('sin nada encendido se ofrece arrancar uno', (tester) async {
      // **Maestro no arranca nada.** Y encenderlo es algo que Nexus ya sabe hacer,
      // así que decir «hace falta un dispositivo» era quedarse a medio camino.
      await _abrir(tester, encendidos: 0);

      expect(find.text(strings.e2eStartDevice), findsOneWidget);
    });

    testWidgets('con uno encendido no se ofrece', (tester) async {
      await _abrir(tester);
      expect(find.text(strings.e2eStartDevice), findsNothing);
    });
  });

  group('cuando la prueba acaba', () {
    testWidgets('el aviso de arriba desaparece', (tester) async {
      // **Lo reportado**: acabada, se veía arriba con «Ver» y abajo con «Borrar».
      // Enseñar lo mismo dos veces con acciones distintas en cada sitio hace
      // dudar de cuál es la de verdad.
      await _abrir(
        tester,
        enMarcha: PruebaEnMarcha(
          flow: 'login',
          delFlow: [_paso('launchApp')],
          salida: _hecho('Launch app "com.ejemplo"'),
          viva: false,
        ),
        corridas: [_corrida()],
      );

      expect(find.textContaining('login · 1/1'), findsNothing);
    });

    testWidgets('mientras corre sí se avisa arriba', (tester) async {
      await _abrir(
        tester,
        enMarcha: PruebaEnMarcha(
          flow: 'login',
          delFlow: [_paso('launchApp')],
        ),
      );
      expect(find.textContaining('login · 0/1'), findsOneWidget);
    });

    testWidgets('la fila del historial tiene ver y borrar', (tester) async {
      final borrados = <String>[];
      await _abrir(
        tester,
        corridas: [_corrida(carpeta: '/donde/sea/login.json')],
        borrados: borrados,
      );

      expect(find.text(strings.e2eSee), findsOneWidget);
      expect(find.text(strings.e2eDelete), findsOneWidget);

      // Ver abre su informe en la misma ventana aparte, no una segunda forma de
      // enseñar lo mismo.
      await tester.tap(find.text(strings.e2eSee));
      await tester.pump();
      expect(borrados, ['ver:/donde/sea/login.json']);
    });
  });

  group('los nombres de los dispositivos', () {
    testWidgets('**el desplegable enseña nombres, no ids**', (tester) async {
      // Lo reportado dos veces: `36c56d94` y `00008030-000C390C1AC0C02E` no dicen
      // cuál es cuál. Los nombres ya los traía el data source; lo que faltaba era
      // enseñarlos, que era un fallo mío en la UI y no en la lectura.
      await _abrir(tester, encendidos: 1, conIphone: true);
      await tester.tap(find.byType(SelectorCompacto));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('iPhone 11'), findsWidgets);
      expect(find.textContaining('Medium Phone 0'), findsWidgets);
    });

    testWidgets('el id va detrás, que es lo que pide --device', (tester) async {
      // Y porque puede haber dos aparatos con el mismo nombre.
      await _abrir(tester, encendidos: 1, conIphone: true);
      await tester.tap(find.byType(SelectorCompacto));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('emulator-5550'), findsWidgets);
    });
  });

  group('repetir una corrida', () {
    testWidgets('la vuelve a correr donde corrió, si sigue encendido', (
      tester,
    ) async {
      // Con dos encendidos y ninguno elegido, la lista de arriba no puede lanzar
      // —no va a decidir por el usuario—. Repetir sí sabe dónde: en el de la
      // corrida. Eso es lo que se comprueba aquí.
      final lanzados = <String>[];
      await _abrir(
        tester,
        encendidos: 2,
        lanzados: lanzados,
        corridas: [_corrida(dispositivo: 'emulator-5551')],
      );

      await _tocarYEsperar(tester, find.byIcon(Icons.replay));

      expect(lanzados, ['login@emulator-5551']);
    });

    testWidgets('si ese dispositivo ya no está, usa el que haya', (
      tester,
    ) async {
      // Un `emulator-5554` de hace tres días no es el mismo emulador: se
      // comprueba contra lo que hay ahora en vez de pasárselo a Maestro.
      final lanzados = <String>[];
      await _abrir(
        tester,
        lanzados: lanzados,
        corridas: [_corrida(dispositivo: 'emulator-9999')],
      );

      await _tocarYEsperar(tester, find.byIcon(Icons.replay));

      expect(lanzados, ['login@emulator-5550']);
    });

    testWidgets('si la prueba ya no está en el repo, lo dice y no lanza', (
      tester,
    ) async {
      // El caso que había que resolver antes de ofrecer el botón: repetir una
      // corrida de la semana pasada con el flow borrado. Se dice aquí, no se
      // falla dentro de Maestro con un «file not found».
      final lanzados = <String>[];
      await _abrir(
        tester,
        pruebas: const [],
        lanzados: lanzados,
        corridas: [_corrida(dispositivo: 'emulator-5550')],
      );

      await tester.tap(find.byIcon(Icons.replay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(strings.e2eFlowGone), findsOneWidget);
      expect(lanzados, isEmpty);
    });

    testWidgets('sin proyecto atribuido no se ofrece repetir', (tester) async {
      // Sin saber en qué repo vive el flow, el botón solo podría contestar «no sé
      // de dónde salió esto», y eso es peor que no ofrecerlo.
      await _abrir(tester, corridas: [_corrida(proyecto: null)]);
      expect(find.byIcon(Icons.replay), findsNothing);
    });

    testWidgets('sin nada encendido lo explica en la propia fila', (
      tester,
    ) async {
      final lanzados = <String>[];
      await _abrir(
        tester,
        encendidos: 0,
        lanzados: lanzados,
        corridas: [_corrida(dispositivo: 'emulator-5550')],
      );

      await tester.tap(find.byIcon(Icons.replay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(strings.e2eNoDevice), findsOneWidget);
      expect(lanzados, isEmpty);
    });
  });

  group('borrar las corridas de un proyecto', () {
    testWidgets('el grupo dice cuántas hay y cuánto ocupan', (tester) async {
      // Es lo que hace falta para decidir si borrarlas: un grupo de corridas con
      // capturas son decenas de megas y nada lo decía.
      await _abrir(
        tester,
        corridas: [
          _corrida(carpeta: '/donde/sea/uno'),
          _corrida(carpeta: '/donde/sea/dos'),
        ],
      );

      expect(find.text(strings.e2eRunsSize(2, '4 kB')), findsOneWidget);
    });

    testWidgets('pide confirmación antes de llevárselas', (tester) async {
      final borrados = <String>[];
      await _abrir(
        tester,
        borrados: borrados,
        corridas: [_corrida(carpeta: '/donde/sea/uno')],
      );

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pump();

      expect(borrados, isEmpty, reason: 'borró al primer toque');
    });

    testWidgets('al segundo toque se lleva las de ese proyecto y no las otras', (
      tester,
    ) async {
      final borrados = <String>[];
      await _abrir(
        tester,
        borrados: borrados,
        corridas: [
          _corrida(proyecto: '/casa/otra', carpeta: '/donde/sea/ajena'),
          _corrida(carpeta: '/donde/sea/uno'),
          _corrida(carpeta: '/donde/sea/dos'),
        ],
      );

      // Los grupos van ordenados por proyecto: «otra» antes que «tienda».
      final sweep = find.byIcon(Icons.delete_sweep_outlined);
      await tester.tap(sweep.at(1));
      await tester.pump();
      await tester.tap(sweep.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(borrados, ['/donde/sea/uno', '/donde/sea/dos']);
    });
  });

  testWidgets('la fila con sus tres acciones no desborda en estrecho', (
    tester,
  ) async {
    // Esta fila ya desbordó tres veces —9 px, 71 px, 235 px— y la última dejó el
    // botón fuera de la hoja, sin que se notara a ojo. Repetir entró como icono
    // por eso: «Ver» y «Borrar» escritos más una tercera palabra es justo lo que
    // no cabe. Se comprueba en estrecho, que es donde se rompe.
    tester.view.physicalSize = const Size(760, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _abrir(
      tester,
      corridas: [
        _corrida(flow: 'un_nombre_de_prueba_bastante_largo_de_verdad'),
      ],
    );

    expect(find.byIcon(Icons.replay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('el aviso al borrar una prueba', () {
    /// El aviso vive en el tooltip del botón, y solo al pedir confirmación.
    Future<void> pedirConfirmacion(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('si está en git, dice que se recupera', (tester) async {
      await _abrir(tester, enGit: true);
      await pedirConfirmacion(tester);

      expect(find.byTooltip(strings.e2eDeleteTestAsk), findsOneWidget);
    });

    testWidgets('si no está, dice que se pierde', (tester) async {
      // Este es el caso por el que existe la comprobación: un flow recién escrito
      // y sin commitear. Prometerle «se recupera con git» era mentirle justo
      // cuando más importa.
      await _abrir(tester, enGit: false);
      await pedirConfirmacion(tester);

      expect(find.byTooltip(strings.e2eDeleteTestAskLost), findsOneWidget);
    });

    testWidgets('si no se puede saber, no promete nada', (tester) async {
      // Sin git o fuera de un repositorio. Decir «esto se pierde» sin tener ni
      // idea es el mismo error que la promesa de antes, con el signo cambiado.
      await _abrir(tester);
      await pedirConfirmacion(tester);

      expect(find.byTooltip(strings.e2eDeleteTestAskPlain), findsOneWidget);
    });
  });
}

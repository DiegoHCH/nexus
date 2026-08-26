import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/design_system/selector_compacto.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
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
  const _Borrados(this.borrados, {this.instalada});

  final List<String> borrados;

  /// Qué contesta la comprobación de instalación: `null` es «no se pudo saber».
  final bool? instalada;

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
}

CorridaDePrueba _corrida({
  String flow = 'login',
  ComoAcabo como = ComoAcabo.bien,
  String? proyecto = '/casa/tienda',
  int pasos = 8,
  int bien = 8,
  String carpeta = '/donde/sea/login',
}) => CorridaDePrueba(
  carpeta: carpeta,
  flow: flow,
  cuando: DateTime(2026, 8, 25, 16, 30),
  comoAcabo: como,
  proyecto: proyecto,
  pasos: pasos,
  pasosBien: bien,
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        emuladoresDataSourceProvider.overrideWithValue(
          _Maquina(encendidos: encendidos, conIphone: conIphone),
        ),
        e2eDataSourceProvider.overrideWithValue(
          _Borrados(borrados ?? [], instalada: instalada),
        ),
        pruebasProvider('/casa/tienda').overrideWith((ref) async => pruebas),
        corridasDePruebaProvider.overrideWith(
          (ref) async => corridas ?? const [],
        ),
        if (enMarcha != null)
          pruebaEnMarchaProvider.overrideWith(() => _EnMarchaFija(enMarcha)),
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
        enMarcha: const PruebaEnMarcha(flow: 'login', pasos: ['launchApp']),
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
      // antes y no después.
      final borrados = <String>[];
      await _abrir(tester, borrados: borrados);

      await tester.tap(find.byTooltip(strings.e2eDeleteTest));
      await tester.pump();

      // La advertencia va en el tooltip del mismo botón: dice qué va a hacer sin
      // ocupar una línea, y con dos palabras escritas la fila desbordaba.
      expect(find.byTooltip(strings.e2eDeleteTestAsk), findsOneWidget);
      expect(borrados, isEmpty, reason: 'borró al primer toque');
    });

    testWidgets('el segundo borra el archivo, y solo ese', (tester) async {
      final borrados = <String>[];
      await _abrir(tester, borrados: borrados);

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
        enMarcha: const PruebaEnMarcha(
          flow: 'login',
          pasos: ['launchApp', 'tapOn: x'],
          terminados: 1,
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
        enMarcha: const PruebaEnMarcha(
          flow: 'login',
          pasos: ['launchApp'],
          terminados: 1,
          viva: false,
        ),
        corridas: [_corrida()],
      );

      expect(find.textContaining('login · 1/1'), findsNothing);
    });

    testWidgets('mientras corre sí se avisa arriba', (tester) async {
      await _abrir(
        tester,
        enMarcha: const PruebaEnMarcha(
          flow: 'login',
          pasos: ['launchApp'],
          terminados: 0,
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
}

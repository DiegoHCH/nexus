import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
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
  const _Maquina({this.encendido = true});

  final bool encendido;

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async => (
    emuladores: [
      Emulador(
        id: 'Medium',
        nombre: 'Medium',
        fabricante: 'Generic',
        plataforma: PlataformaEmulador.android,
        corriendo: encendido,
        deviceId: encendido ? 'emulator-5554' : null,
      ),
    ],
    error: null,
  );

  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => const [];
}

class _Borrados extends E2eDataSource {
  const _Borrados(this.borrados);

  final List<String> borrados;

  @override
  Future<String?> borrar(String carpeta) async {
    borrados.add(carpeta);
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
  bool dispositivoEncendido = true,
  List<String>? borrados,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        emuladoresDataSourceProvider.overrideWithValue(
          _Maquina(encendido: dispositivoEncendido),
        ),
        if (borrados != null)
          e2eDataSourceProvider.overrideWithValue(_Borrados(borrados)),
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
      await _abrir(tester, dispositivoEncendido: false);
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

  group('la vista en vivo', () {
    testWidgets('los pasos salen con su estado y la cuenta', (tester) async {
      await _abrir(
        tester,
        enMarcha: const PruebaEnMarcha(
          flow: 'login',
          pasos: ['launchApp', 'tapOn: entrar', 'assertVisible: hola'],
          terminados: 1,
        ),
      );

      // Los tres pasos del YAML, no la redacción de Maestro.
      expect(find.text('launchApp'), findsOneWidget);
      expect(find.text('tapOn: entrar'), findsOneWidget);
      expect(find.text('assertVisible: hola'), findsOneWidget);
      // Y la cuenta, que dice dónde va sin contar iconos.
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text(strings.e2eStop), findsOneWidget);
    });

    testWidgets('**si lo ejecutado no cuadra, enseña la salida en plano**', (
      tester,
    ) async {
      // Pasa con `runFlow` y con los bucles: los pasos impresos no son las líneas
      // del archivo. Degradarse es mejor que pintar un estado inventado.
      await _abrir(
        tester,
        enMarcha: const PruebaEnMarcha(
          flow: 'login',
          pasos: ['launchApp'],
          terminados: 9,
          lineas: ['Launch app... COMPLETED', 'Tap on... COMPLETED'],
        ),
      );

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('Launch app'), findsOneWidget);
    });

    testWidgets('terminada no ofrece cortar', (tester) async {
      await _abrir(
        tester,
        enMarcha: const PruebaEnMarcha(
          flow: 'login',
          pasos: ['launchApp'],
          terminados: 1,
          viva: false,
        ),
      );
      expect(find.text(strings.e2eStop), findsNothing);
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
}

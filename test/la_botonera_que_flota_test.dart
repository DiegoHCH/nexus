import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/donde_flota_la_botonera.dart';
import 'package:nexus/features/run/presentation/providers/la_ventana_del_registro.dart';
import 'package:nexus/features/run/presentation/widgets/la_botonera_de_corridas.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La botonera de la corrida, flotando encima de la conversación.
///
/// 🔴 **Los botones vivían dentro del panel de correr**, que es un menú: para
/// recargar había que abrirlo, apuntar a la fila y pulsar, con la lista de
/// entornos delante — y el panel se cierra al pulsar fuera, así que gobernar una
/// corrida obligaba a reabrirlo cada vez. Lo que se prueba aquí es lo que se
/// pidió: que esté siempre a la vista, que **no bloquee** y que se pueda
/// apartar y quedarse donde se apartó.
const _deviceId = 'emulator-5554';

Corrida _corrida({
  EstadoDeCorrida estado = EstadoDeCorrida.corriendo,
  String? appId = 'abc',
  String? progreso,
}) => Corrida(
  deviceId: _deviceId,
  dispositivo: 'Medium Phone API 36.1',
  proyecto: '/casa/tienda',
  configuracion: 'Tienda (dev)',
  plataforma: PlataformaEmulador.android,
  estado: estado,
  appId: appId,
  progreso: progreso,
);

class _Corridas extends CorridasController {
  _Corridas(this._inicial);

  final Map<String, Corrida> _inicial;

  @override
  Map<String, Corrida> build() => _inicial;

  final pedidos = <String>[];

  @override
  Future<Map<String, ({bool ok, String? error})>> recargar({
    String? deviceId,
    bool completa = false,
  }) async {
    pedidos.add(completa ? 'reinicio' : 'recarga');
    return const {};
  }

  @override
  Future<String?> parar(String deviceId) async {
    pedidos.add('parar');
    return null;
  }
}

class _Pintor {
  final paginas = <String>[];

  Future<void> pinta(
    String nombre,
    String html, {
    required bool primeraVez,
  }) async => paginas.add(nombre);
}

void main() {
  const strings = NexusStringsEs();
  late _Corridas corridas;
  late _Pintor pintor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pintor = _Pintor();
  });

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    Map<String, Corrida> conCorridas = const {},
  }) async {
    corridas = _Corridas(conCorridas);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          corridasProvider.overrideWith(() => corridas),
          elPintorDeVentanasProvider.overrideWithValue(pintor.pinta),
        ],
        child: MaterialApp(
          theme: NexusTheme.dark(),
          builder: (context, child) =>
              StringsScope(strings: strings, child: child!),
          home: const Scaffold(body: Stack(children: [LaBotoneraDeCorridas()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(LaBotoneraDeCorridas)),
      listen: false,
    );
  }

  testWidgets('sin nada corriendo no hay botonera', (tester) async {
    await montar(tester);

    expect(find.text(strings.runToolbarDrag), findsNothing);
    expect(find.byTooltip(strings.runStop), findsNothing);
  });

  testWidgets('mientras compila dice qué compila, y solo ofrece parar', (
    tester,
  ) async {
    // Antes de `app.started` no hay a quién pedirle una recarga: un botón que
    // contesta «todavía está compilando» es un botón que no debía estar
    // encendido.
    await montar(
      tester,
      conCorridas: {
        _deviceId: _corrida(
          estado: EstadoDeCorrida.arrancando,
          appId: null,
          progreso: 'Compilando lib/main.dart',
        ),
      },
    );

    expect(find.byTooltip(strings.runReload), findsNothing);
    // **En su propia línea**, no pegado al dispositivo: ahí se cortaba en una
    // letra —«Medium Phone API 36.1 · R…»— y era lo único que decía que algo
    // estaba pasando.
    expect(find.text('Compilando lib/main.dart'), findsOneWidget);
    expect(find.text('Medium Phone API 36.1'), findsOneWidget);
    expect(find.byTooltip(strings.runStop), findsOneWidget);
  });

  testWidgets('corriendo ofrece recargar, reiniciar y parar', (tester) async {
    await montar(tester, conCorridas: {_deviceId: _corrida()});

    expect(find.byTooltip(strings.runReload), findsOneWidget);
    expect(find.byTooltip(strings.runRestart), findsOneWidget);
    expect(find.byTooltip(strings.runStop), findsOneWidget);
  });

  testWidgets('y cada botón pide lo suyo', (tester) async {
    await montar(tester, conCorridas: {_deviceId: _corrida()});

    await tester.tap(find.byTooltip(strings.runReload));
    await tester.tap(find.byTooltip(strings.runRestart));
    await tester.tap(find.byTooltip(strings.runStop));
    await tester.pump();

    expect(corridas.pedidos, ['recarga', 'reinicio', 'parar']);
  });

  testWidgets('parando no vuelve a ofrecer parar', (tester) async {
    // Pulsarlo dos veces no para dos veces: manda otro `app.stop` a algo que ya
    // se está muriendo.
    await montar(
      tester,
      conCorridas: {_deviceId: _corrida(estado: EstadoDeCorrida.parando)},
    );

    expect(find.byTooltip(strings.runStop), findsNothing);
    expect(find.text(strings.runStopping), findsOneWidget);
  });

  // El reinicio en verde y el parar en rojo, como cualquier barra de
  // depuración: cuatro siluetas grises seguidas se pulsan a ciegas.
  testWidgets('el reinicio y el parar se distinguen por color', (tester) async {
    await montar(tester, conCorridas: {_deviceId: _corrida()});

    IconButton boton(IconData icono) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icono));

    expect(boton(Icons.restart_alt).color, NexusColors.dark.ok);
    expect(boton(Icons.stop_rounded).color, NexusColors.dark.err);
  });

  testWidgets('los registros se abren desde aquí', (tester) async {
    await montar(tester, conCorridas: {_deviceId: _corrida()});

    await tester.tap(find.byTooltip(strings.runLogs));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(strings.runSystemLog));
    await tester.pumpAndSettle();

    expect(pintor.paginas, ['registro-emulator-5554', 'sistema-emulator-5554']);
  });

  group('la recarga automática', () {
    testWidgets('viene apagada de fábrica', (tester) async {
      // Recargar la app sin que nadie lo pida es una sorpresa la primera vez.
      await montar(tester, conCorridas: {_deviceId: _corrida()});

      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.bolt))
            .color,
        isNot(NexusColors.dark.accent),
      );
    });

    testWidgets('encendida se ve marcada', (tester) async {
      SharedPreferences.setMockInitialValues({'run.autoRecarga': true});
      await montar(tester, conCorridas: {_deviceId: _corrida()});
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.bolt))
            .color,
        NexusColors.dark.accent,
      );
    });
  });

  group('el sitio donde flota', () {
    testWidgets('nace abajo a la derecha, lejos del orbe y del muelle', (
      tester,
    ) async {
      await montar(tester, conCorridas: {_deviceId: _corrida()});

      final ventana = tester.view.physicalSize / tester.view.devicePixelRatio;
      final caja = tester.getRect(find.byType(LaBotoneraDeCorridas));

      expect(caja.width, LaBotoneraDeCorridas.ancho);
      expect(caja.right, closeTo(ventana.width - 32, 0.01));
      expect(caja.top, lessThan(ventana.height));
      expect(caja.top, greaterThan(ventana.height / 2));
    });

    testWidgets('se arrastra por el asa, y el sitio se recuerda', (
      tester,
    ) async {
      final contenedor = await montar(
        tester,
        conCorridas: {_deviceId: _corrida()},
      );
      final antes = tester.getRect(find.byType(LaBotoneraDeCorridas));

      await tester.drag(
        find.byIcon(Icons.drag_indicator),
        const Offset(-120, -60),
      );
      await tester.pumpAndSettle();

      final ahora = tester.getRect(find.byType(LaBotoneraDeCorridas));
      expect(ahora.left, closeTo(antes.left - 120, 0.01));
      expect(ahora.top, closeTo(antes.top - 60, 0.01));

      // 🔴 **Y se guarda al soltar, no en cada tirón**: escribir en disco por
      // cada `onPanUpdate` son cien escrituras en un arrastre. Lo que importa
      // aquí es que al final quede guardado, porque un asa que no se recuerda
      // enseña que moverla no cuenta.
      expect(
        contenedor.read(dondeFlotaLaBotoneraProvider),
        Offset(antes.left - 120, antes.top - 60),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('run.botonera.x'), antes.left - 120);
    });

    // Arrastrarla fuera la dejaría irrecuperable: no queda asa que agarrar para
    // traerla de vuelta.
    test('nunca se sale del todo de la ventana', () {
      const ventana = Size(1200, 800);

      final aLaDerecha = LaBotoneraDeCorridas.dentroDe(
        ventana,
        const Offset(5000, 5000),
      );
      expect(aLaDerecha.dx, ventana.width - LaBotoneraDeCorridas.margen);
      expect(aLaDerecha.dy, ventana.height - 48);

      final aLaIzquierda = LaBotoneraDeCorridas.dentroDe(
        ventana,
        const Offset(-5000, -5000),
      );
      expect(
        aLaIzquierda.dx,
        LaBotoneraDeCorridas.margen - LaBotoneraDeCorridas.ancho,
      );
      expect(aLaIzquierda.dy, 0);
    });

    // Lo de la última vez puede caer fuera si la ventana se hizo más pequeña.
    test('una ventana más pequeña la trae de vuelta', () {
      final donde = LaBotoneraDeCorridas.dentroDe(
        const Size(600, 400),
        LaBotoneraDeCorridas.dondeNace(const Size(1600, 1000)),
      );

      expect(donde.dx, lessThanOrEqualTo(600 - LaBotoneraDeCorridas.margen));
      expect(donde.dy, lessThanOrEqualTo(400 - 48));
    });
  });
}

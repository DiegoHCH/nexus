import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/domain/usecases/la_sesion_de_puerta.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

// El arranque sin conversaciones: se saluda, se pregunta dónde, y **no hay caja**.
//
// 🔴 Nace de quitar un caso, no de arreglarlo: esa pantalla enseñaba el
// compositor con los chips de la conversación que acababas de cerrar —carpeta,
// repo, rama y cuenta— y escribir mandaba el encargo ahí sin decírtelo.
//
// Y la caja vuelve en cuanto la puerta no puede hablar. Una puerta que no habla
// no puede ser la única entrada: eso no es un arranque distinto, es un arranque
// cerrado.

class _PuertaFalsa implements LaSesionDePuerta {
  final controlador = StreamController<LoQuePasaEnLaPuerta>.broadcast();
  String? saludoPedido;
  List<PairedFolder>? carpetasOfrecidas;

  @override
  Stream<LoQuePasaEnLaPuerta> abrir({
    required String saludo,
    required List<PairedFolder> carpetas,
  }) {
    saludoPedido = saludo;
    carpetasOfrecidas = carpetas;
    return controlador.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const strings = NexusStringsEs();
  late _PuertaFalsa puerta;
  late Directory support;

  setUp(() {
    support = prepareScreenTest();
    // Con el tour ya visto y sin conversaciones guardadas: si la lista no está
    // leída, la casa enseña «esperando» y no se llega a la puerta siquiera.
    SharedPreferences.setMockInitialValues({'flutter.tour_seen': true});
    puerta = _PuertaFalsa();
  });
  tearDown(() {
    puerta.controlador.close();
    support.deleteSync(recursive: true);
  });

  Future<void> abrirLaCasa(WidgetTester tester, {bool conVoz = true}) =>
      pumpScreen(
        tester,
        const HomePage(),
        conPuerta: conVoz,
        overrides: [
          workspaceControllerProvider.overrideWith(
            () => FixedWorkspace(workspaceWith()),
          ),
          laSesionDePuertaProvider.overrideWithValue(puerta),
        ],
      );

  testWidgets('con la puerta abierta no hay caja de texto', (tester) async {
    await abrirLaCasa(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text(strings.composerHint),
      findsNothing,
      reason: 'la caja mandaba el encargo a la carpeta anterior sin decirlo',
    );
  });

  testWidgets('y saluda con la hora, tu nombre y la pregunta', (tester) async {
    await abrirLaCasa(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(puerta.saludoPedido, isNotNull);
    expect(puerta.saludoPedido, contains('vamos a trabajar hoy'));
    // El saludo se pinta ya, sin esperar a que suene: una pantalla muda en el
    // arranque se lee como una app que no arrancó.
    expect(find.text(puerta.saludoPedido!), findsOneWidget);
  });

  // Decidido a la vista: viaja el nombre, no el contenido.
  testWidgets('se le ofrecen todas las carpetas emparejadas', (tester) async {
    await abrirLaCasa(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      puerta.carpetasOfrecidas,
      isNotEmpty,
      reason: 'sin carpetas no habría nada que elegir',
    );
  });

  // 🔴 **Se acumula, no se reemplaza.** La transcripción llega a pedazos, así
  // que pintando solo el último trozo el saludo aparecía y se iba borrando solo
  // delante de quien lo estaba leyendo. Reportado mirándolo.
  testWidgets('lo que va diciendo se acumula debajo del orbe', (tester) async {
    await abrirLaCasa(tester);
    await tester.pump(const Duration(milliseconds: 50));

    puerta.controlador.add(const LaPuertaDice(' ¿En cuál '));
    puerta.controlador.add(const LaPuertaDice('de las dos?'));
    await tester.pump(const Duration(milliseconds: 50));

    // El saludo pintado es un adelanto: el primer trozo que dice de verdad lo
    // sustituye, o se veía dos veces —reportado mirándolo—.
    expect(find.textContaining('¿En cuál de las dos?'), findsOneWidget);
    expect(
      find.textContaining(puerta.saludoPedido!),
      findsNothing,
      reason: 'lo que dice él sustituye al adelanto, no se suma',
    );
  });

  // 🔴 La puerta no puede ser la única entrada.
  testWidgets('si se cae, vuelve la caja de siempre', (tester) async {
    await abrirLaCasa(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(strings.composerHint), findsNothing);

    puerta.controlador.add(const LaPuertaSeCayo('se cortó'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(strings.composerHint), findsOneWidget);

    // Y se le deja tiempo a lo que la caja arranca al construirse: aparece al
    // final de la prueba, y con el árbol cerrándose encima queda un
    // temporizador vivo que hace fallar el cierre.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('y sin micrófono no se abre: la pantalla de siempre', (
    tester,
  ) async {
    await abrirLaCasa(tester, conVoz: false);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(strings.composerHint), findsOneWidget);
    expect(puerta.saludoPedido, isNull, reason: 'ni se intentó saludar');
  });
}

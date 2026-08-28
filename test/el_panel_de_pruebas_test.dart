import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/design_system/selector_compacto.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/por_que_se_cayo.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/pruebas_sheet.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El panel de pruebas: lanzar, ver correr, y el historial.
class _Maquina extends EmuladoresDataSource {
  const _Maquina({
    this.encendidos = 1,
    this.conIphone = false,
    this.demora = Duration.zero,
  });

  /// Lo que tarda la búsqueda. **Hace falta que se pueda tardar**: buscar los
  /// dispositivos lanza dos procesos, y el estado intermedio —que existía y no se
  /// enseñaba— es justo el que se reportó.
  final Duration demora;

  /// Cuántos emuladores hay arriba. Con dos hay que elegir; con uno, no.
  final int encendidos;

  /// Si además hay un iPhone enchufado. Aparte y apagado por defecto para que las
  /// pruebas de «no hay nada» y «hay uno solo» sigan diciendo eso.
  final bool conIphone;

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async {
    if (demora > Duration.zero) await Future<void>.delayed(demora);
    return _lista();
  }

  ({List<Emulador> emuladores, String? error}) _lista() => (
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
  Future<List<DispositivoConectado>> listarDispositivos() async {
    if (demora > Duration.zero) await Future<void>.delayed(demora);
    return _conectados;
  }

  List<DispositivoConectado> get _conectados => conIphone
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
  const _Borrados(
    this.borrados, {
    this.instalada,
    this.enGit,
    this.variables = const {},
  });

  final List<String> borrados;

  /// Qué contesta la comprobación de instalación: `null` es «no se pudo saber».
  final bool? instalada;

  /// Y la de git, con el mismo `null` de «no se pudo saber».
  final bool? enGit;

  @override
  Future<bool?> estaEnGit(String ruta) async => enGit;

  /// Las credenciales del proyecto. **Solo nombres en las aserciones**: si una
  /// prueba tuviera que comprobar un valor, el valor estaría en un sitio donde no
  /// debe estar.
  final Map<String, String> variables;

  @override
  Map<String, String> variablesDe(
    String proyecto, {
    String? carpetaDePruebas,
  }) => variables;

  @override
  Future<bool?> estaInstalada({
    required String deviceId,
    required String appId,
  }) async => instalada;

  @override
  Future<void> abreElInforme(
    String registro, {
    String Function(PorQueSeCayo)? explica,
  }) async => borrados.add('ver:$registro');

  @override
  Future<void> pintaLaPasada({
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

  /// Un tamaño fijo por pasada: lo que se comprueba es que el grupo lo sume y lo
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
    Map<String, String>? credenciales,
  }) async {
    // El perfil y el origen de las credenciales se apuntan también: es lo que
    // distingue una pasada del proyecto de una del repo de pruebas, y sin eso el
    // doble no podría notar que se lanzó la que no era.
    lanzados.add(
      '${prueba.nombre}@$deviceId'
      '${credenciales == null ? '' : ' con $perfil (${credenciales.length})'}',
    );
    return null;
  }
}

PasadaDePrueba _corrida({
  String flow = 'login',
  ComoAcabo como = ComoAcabo.bien,
  String? proyecto = '/casa/tienda',
  int pasos = 8,
  int bien = 8,
  String carpeta = '/donde/sea/login',
  String? dispositivo,
}) => PasadaDePrueba(
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
  List<Prueba> pruebas = const [
    Prueba(ruta: '/casa/tienda/.maestro/login.yaml', nombre: 'login'),
  ],
  List<PasadaDePrueba>? pasadas,
  PruebaEnMarcha? enMarcha,
  int encendidos = 1,
  bool conIphone = false,
  Duration demora = Duration.zero,
  List<String>? borrados,
  bool? instalada,
  bool? enGit,
  Map<String, String> variables = const {},
  List<String>? lanzados,
  void Function()? alLeerElRepo,
  List<String> emparejadas = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        emuladoresDataSourceProvider.overrideWithValue(
          _Maquina(
            encendidos: encendidos,
            conIphone: conIphone,
            demora: demora,
          ),
        ),
        e2eDataSourceProvider.overrideWithValue(
          _Borrados(
            borrados ?? [],
            instalada: instalada,
            enGit: enGit,
            variables: variables,
          ),
        ),
        if (emparejadas.isNotEmpty)
          workspaceControllerProvider.overrideWith(
            () => _WorkspaceFijo(emparejadas),
          ),
        pruebasProvider('/casa/tienda').overrideWith((ref) async {
          alLeerElRepo?.call();
          return pruebas;
        }),
        pasadasDePruebaProvider.overrideWith(
          (ref) async => pasadas ?? const [],
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
/// la E/S real no completa nunca: repetir una pasada lee el `.yaml` de la prueba
/// antes de lanzar —para saber el `appId` y avisar si la app no está instalada— y
/// sin esto ese `await` se queda colgado, el lanzamiento no llega, y la prueba
/// falla diciendo que no se lanzó nada. Que es lo que pasó.
/// Bombea y espera **de verdad**, varias veces, porque lo que se dispara al tocar
/// es una cadena de `await`: leer el `.yaml`, resolver el proveedor de credenciales
/// —que a su vez le pregunta a git— y comprobar la instalación. Con una sola espera
/// se quedaba a medias y la prueba decía que no se había lanzado nada.
Future<void> _tocarYEsperar(WidgetTester tester, Finder que) async {
  await tester.runAsync(() async {
    await tester.tap(que);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
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

    testWidgets('un proyecto sin pruebas no ocupa sitio', (tester) async {
      // **Antes esta prueba esperaba el mensaje «no hay pruebas».** Se cambió el
      // requisito (27 ago 2026): una carpeta vacía pintaba cabecera, selector y
      // aviso —tres filas para decir que no hay nada— justo encima de lo que sí
      // hay. Si no hay, no se enseña.
      await _abrir(tester, pruebas: const []);
      expect(find.text(strings.e2eNone), findsNothing);
      expect(find.text(strings.e2eRun), findsNothing);
    });

    testWidgets('sin dispositivo encendido, el botón no deja ni tocarlo', (
      tester,
    ) async {
      // **Antes esta prueba tocaba el botón y esperaba la explicación.** Eso era
      // enterarse tarde de algo que ya se sabía: `maestro test --device` contra un
      // emulador apagado falla, así que el botón no puede ofrecerlo. Ahora está
      // apagado y el motivo va en su tooltip, que es lo que evita el otro problema
      // —un botón muerto sin explicación—.
      await _abrir(tester, encendidos: 0);

      final boton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, strings.e2eRun),
      );
      expect(boton.onPressed, isNull);
      expect(find.byTooltip(strings.e2eNoDevice), findsOneWidget);
    });

    testWidgets('con una corriendo no se puede lanzar otra', (tester) async {
      // Dos pasadas de Maestro sobre el mismo dispositivo se pelean por su
      // driver.
      await _abrir(
        tester,
        enMarcha: PruebaEnMarcha(flow: 'login', delFlow: [_paso('launchApp')]),
      );

      final boton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, strings.e2eRun),
      );
      expect(boton.onPressed, isNull);
    });
  });

  group('el historial', () {
    testWidgets('sin pasadas se explica en vez de dejar un hueco', (
      tester,
    ) async {
      await _abrir(tester);
      expect(find.text(strings.e2eNoRuns), findsOneWidget);
    });

    testWidgets('cada pasada dice cómo acabó y por dónde iba', (tester) async {
      await _abrir(tester, pasadas: [_corrida(como: ComoAcabo.mal, bien: 2)]);

      // «2/8» dice dónde se rompió sin abrir nada.
      expect(find.textContaining('2/8'), findsOneWidget);
      expect(find.textContaining(strings.e2eFailed), findsOneWidget);
    });

    testWidgets('**las que no se pudieron atribuir se enseñan igual**', (
      tester,
    ) async {
      // No saber de qué proyecto salió una pasada es un problema nuestro;
      // esconderla se lo pasaría al usuario como historial incompleto.
      await _abrir(
        tester,
        pasadas: [
          _corrida(),
          _corrida(flow: 'explora', proyecto: null, carpeta: '/otro/explora'),
        ],
      );

      expect(find.text(strings.e2eUnattributed), findsOneWidget);
      expect(find.text('explora'), findsOneWidget);
    });

    testWidgets('borrar una pasada borra su carpeta y solo esa', (
      tester,
    ) async {
      final borrados = <String>[];
      await _abrir(
        tester,
        pasadas: [_corrida(carpeta: '/donde/sea/login')],
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
    testWidgets('con varios apagados se puede elegir cuál', (tester) async {
      // **Maestro no arranca nada.** Y encenderlo es algo que Nexus ya sabe hacer,
      // así que decir «hace falta un dispositivo» era quedarse a medio camino.
      //
      // Uno por emulador y con su nombre: antes arrancaba «el primero apagado» sin
      // decir cuál, y con dos definidos eso es encender el que no era la mitad de
      // las veces.
      await _abrir(tester, encendidos: 0);

      expect(find.text('Medium Phone 0'), findsOneWidget);
      expect(find.text('Medium Phone 1'), findsOneWidget);
    });

    testWidgets('con uno solo apagado, el botón no pregunta cuál', (
      tester,
    ) async {
      await _abrir(tester, encendidos: 1);
      expect(find.text(strings.e2eStartDevice), findsOneWidget);
    });

    testWidgets('con un dispositivo ya presente se sigue ofreciendo', (
      tester,
    ) async {
      // **Lo reportado, y la condición que lo causaba.** Se ofrecía solo cuando no
      // había ningún dispositivo, y basta un iPhone emparejado por wifi —que aparece
      // solo, sin cable— para que Nexus crea que ya hay dónde correr. Resultado: no
      // te deja encender el emulador, que además es el único de los dos donde Maestro
      // funciona de verdad.
      await _abrir(tester, encendidos: 0, conIphone: true);

      expect(find.text('Medium Phone 0'), findsOneWidget);
    });

    testWidgets('sin ninguno apagado no se ofrece nada', (tester) async {
      // Con los dos arriba no hay nada que encender, y un botón que no puede hacer
      // nada es peor que ninguno: se traga la pulsación y no lo dice.
      await _abrir(tester, encendidos: 2);
      expect(find.text(strings.e2eStartDevice), findsNothing);
      expect(find.text('Medium Phone 0'), findsNothing);
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
        pasadas: [_corrida()],
      );

      expect(find.textContaining('login · 1/1'), findsNothing);
    });

    testWidgets('mientras corre sí se avisa arriba', (tester) async {
      await _abrir(
        tester,
        enMarcha: PruebaEnMarcha(flow: 'login', delFlow: [_paso('launchApp')]),
      );
      expect(find.textContaining('login · 0/1'), findsOneWidget);
    });

    testWidgets('la fila del historial tiene ver y borrar', (tester) async {
      final borrados = <String>[];
      await _abrir(
        tester,
        pasadas: [_corrida(carpeta: '/donde/sea/login.json')],
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

  group('repetir una pasada', () {
    testWidgets('la vuelve a correr donde corrió, si sigue encendido', (
      tester,
    ) async {
      // Con dos encendidos y ninguno elegido, la lista de arriba no puede lanzar
      // —no va a decidir por el usuario—. Repetir sí sabe dónde: en el de la
      // pasada. Eso es lo que se comprueba aquí.
      final lanzados = <String>[];
      await _abrir(
        tester,
        encendidos: 2,
        lanzados: lanzados,
        pasadas: [_corrida(dispositivo: 'emulator-5551')],
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
        pasadas: [_corrida(dispositivo: 'emulator-9999')],
      );

      await _tocarYEsperar(tester, find.byIcon(Icons.replay));

      expect(lanzados, ['login@emulator-5550']);
    });

    testWidgets('si la prueba ya no está en el repo, lo dice y no lanza', (
      tester,
    ) async {
      // El caso que había que resolver antes de ofrecer el botón: repetir una
      // pasada de la semana pasada con el flow borrado. Se dice aquí, no se
      // falla dentro de Maestro con un «file not found».
      final lanzados = <String>[];
      await _abrir(
        tester,
        pruebas: const [],
        lanzados: lanzados,
        pasadas: [_corrida(dispositivo: 'emulator-5550')],
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
      await _abrir(tester, pasadas: [_corrida(proyecto: null)]);
      expect(find.byIcon(Icons.replay), findsNothing);
    });

    testWidgets('sin nada encendido, repetir tampoco se deja tocar', (
      tester,
    ) async {
      // **Antes esto tocaba el icono y esperaba la explicación en la fila.** Igual
      // que en la lista de arriba, eso era enterarse tarde: sin dónde correr,
      // repetir no puede pasar. Un icono apagado dice todavía menos que un botón
      // apagado, así que el motivo va en su tooltip.
      final lanzados = <String>[];
      await _abrir(
        tester,
        encendidos: 0,
        lanzados: lanzados,
        pasadas: [_corrida(dispositivo: 'emulator-5550')],
      );

      final icono = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.replay),
      );
      expect(icono.onPressed, isNull);
      expect(icono.tooltip, strings.e2eNoDevice);
      expect(lanzados, isEmpty);
    });
  });

  group('borrar las pasadas de un proyecto', () {
    testWidgets('el grupo dice cuántas hay y cuánto ocupan', (tester) async {
      // Es lo que hace falta para decidir si borrarlas: un grupo de pasadas con
      // capturas son decenas de megas y nada lo decía.
      await _abrir(
        tester,
        pasadas: [
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
        pasadas: [_corrida(carpeta: '/donde/sea/uno')],
      );

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pump();

      expect(borrados, isEmpty, reason: 'borró al primer toque');
    });

    testWidgets(
      'al segundo toque se lleva las de ese proyecto y no las otras',
      (tester) async {
        final borrados = <String>[];
        await _abrir(
          tester,
          borrados: borrados,
          pasadas: [
            _corrida(proyecto: '/casa/otra', carpeta: '/donde/sea/ajena'),
            _corrida(carpeta: '/donde/sea/uno'),
            _corrida(carpeta: '/donde/sea/dos'),
          ],
        );

        // Los grupos van ordenados por proyecto: «otra» antes que «tienda».
        final sweep = find.byIcon(Icons.delete_sweep_outlined);
        // El historial vive debajo de la sección del repo, así que puede quedar
        // fuera de la ventana del test. Se acerca antes de tocar: el fallo que
        // daba sin esto era del viewport, no de la pantalla.
        await tester.ensureVisible(sweep.at(1));
        await tester.pump();
        await tester.tap(sweep.at(1));
        await tester.pump();
        await tester.tap(sweep.at(1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(borrados, ['/donde/sea/uno', '/donde/sea/dos']);
      },
    );
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
      pasadas: [_corrida(flow: 'un_nombre_de_prueba_bastante_largo_de_verdad')],
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

  group('las credenciales del proyecto', () {
    /// Un flow de verdad en disco: el aviso depende de leer su texto.
    Prueba unFlowQueUsa(String variable, Directory casa) {
      Directory('${casa.path}/.maestro').createSync(recursive: true);
      final ruta = '${casa.path}/.maestro/login.yaml';
      File(ruta).writeAsStringSync(
        'appId: com.ejemplo\n---\n- inputText: \${$variable}\n',
      );
      return Prueba(ruta: ruta, nombre: 'login');
    }

    late Directory casa;
    setUp(() => casa = Directory.systemTemp.createTempSync('panelvars'));
    tearDown(() => casa.deleteSync(recursive: true));

    testWidgets('dice cuántas hay cargadas, sin enseñar ninguna', (
      tester,
    ) async {
      // Es la diferencia entre saber que el `.env.local` se leyó y suponerlo.
      await _abrir(tester, variables: const {'CORREO': 'a@b.c', 'CLAVE': 'x'});

      expect(find.text(strings.e2eVarsLoaded(2)), findsOneWidget);
      // Y el valor no aparece en ningún sitio de la pantalla.
      expect(find.textContaining('a@b.c'), findsNothing);
    });

    testWidgets('sin .env.local no se dice nada', (tester) async {
      await _abrir(tester);
      expect(find.textContaining('.env.local'), findsNothing);
    });

    testWidgets('si el archivo está en git, se avisa', (tester) async {
      // Un archivo de credenciales dentro de un repositorio es una fuga, y en un
      // repo compartido lo es para todo el equipo.
      await _abrir(tester, variables: const {'CORREO': 'a@b.c'}, enGit: true);

      expect(find.text(strings.e2eEnvInGit), findsOneWidget);
    });

    testWidgets('una variable que falta se dice antes de correr', (
      tester,
    ) async {
      // Sin esto, Maestro escribe el literal `${CORREO}` en el campo y la prueba
      // muere tres pasos después, en un sitio que no tiene que ver con la causa.
      final lanzados = <String>[];
      await _abrir(
        tester,
        pruebas: [unFlowQueUsa('CORREO', casa)],
        lanzados: lanzados,
      );

      await _tocarYEsperar(tester, find.text(strings.e2eRun));

      expect(find.text(strings.e2eMissingVars('CORREO')), findsOneWidget);
      expect(lanzados, isEmpty, reason: 'lanzó sin la credencial');
    });

    testWidgets('con la variable puesta, se lanza', (tester) async {
      final lanzados = <String>[];
      await _abrir(
        tester,
        pruebas: [unFlowQueUsa('CORREO', casa)],
        variables: const {'CORREO': 'a@b.c'},
        lanzados: lanzados,
      );

      await _tocarYEsperar(tester, find.text(strings.e2eRun));

      expect(lanzados, ['login@emulator-5550']);
    });
  });

  group('mientras se buscan los dispositivos', () {
    testWidgets('se dice que se está buscando', (tester) async {
      // Lo reportado: al abrir el panel no salía el selector de dónde correr. La
      // causa era que «todavía buscando» y «no hay ninguno» eran el mismo estado.
      await _abrir(tester, encendidos: 2, demora: const Duration(seconds: 1));

      expect(find.text(strings.e2eSearchingDevices), findsOneWidget);

      // Y al acabar la búsqueda, el selector aparece y el aviso se va.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(strings.e2eSearchingDevices), findsNothing);
      expect(find.byType(SelectorCompacto), findsOneWidget);
    });

    testWidgets('no se ofrece arrancar un emulador mientras no se sabe', (
      tester,
    ) async {
      // Mientras no se sabe, no se ofrece: un botón que aparece y desaparece medio
      // segundo después se lee como un parpadeo, no como una opción.
      await _abrir(tester, encendidos: 2, demora: const Duration(seconds: 1));

      expect(find.text(strings.e2eStartDevice), findsNothing);

      // Y al acabar tampoco, porque con los dos arriba no hay nada que encender.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(strings.e2eStartDevice), findsNothing);
    });

    testWidgets('sin ninguno, al acabar sí se ofrece', (tester) async {
      await _abrir(tester, encendidos: 1, demora: const Duration(seconds: 1));

      expect(find.text(strings.e2eStartDevice), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(strings.e2eStartDevice), findsOneWidget);
    });
  });

  group('una prueba recién creada', () {
    testWidgets('al abrir se vuelve a mirar el repo, sin reiniciar', (
      tester,
    ) async {
      // **El bucle entero de la feature dependía de esto**: se le pide a Nexus un
      // e2e, lo escribe en el `.maestro/` del repo, y no aparecía para correrlo
      // hasta reiniciar la app. La lista solo se refrescaba al borrar una prueba.
      var lecturas = 0;
      await _abrir(tester, alLeerElRepo: () => lecturas++);

      expect(
        lecturas,
        greaterThanOrEqualTo(2),
        reason: 'no se volvió a mirar el repo al abrir el panel',
      );
    });

    testWidgets('y la lista sigue puesta mientras se vuelve a mirar', (
      tester,
    ) async {
      // La otra mitad del criterio: el valor guardado evita el parpadeo. Refrescar
      // sin conservarlo cambiaría un problema por el otro.
      await _abrir(tester);
      expect(find.text('login'), findsOneWidget);
    });
  });

  group('de qué proyecto', () {
    testWidgets('con varios sale el desplegable y se puede cambiar', (
      tester,
    ) async {
      await _abrir(tester, emparejadas: ['/casa/tienda', '/casa/almacen']);

      expect(find.byKey(const ValueKey('de-que-proyecto')), findsOneWidget);
      // De partida, el de la conversación: mirar otro es una consulta, y de partida
      // uno mira donde está trabajando.
      expect(find.text('tienda'), findsWidgets);
    });

    testWidgets('con uno solo no hay desplegable, solo su nombre', (
      tester,
    ) async {
      // Un selector de una sola opción es pedir una decisión que no existe.
      await _abrir(tester);
      expect(find.byKey(const ValueKey('de-que-proyecto')), findsNothing);
    });
  });
}

/// Un espacio de trabajo con las carpetas que pida la prueba, para poder enseñar el
/// selector de proyecto sin tocar el disco.
class _WorkspaceFijo extends WorkspaceController {
  _WorkspaceFijo(this.carpetas);

  final List<String> carpetas;

  @override
  Workspace build() => Workspace(
    folders: [
      for (final ruta in carpetas)
        PairedFolder(path: ruta, modality: FolderModality.textOnly),
    ],
    activePath: carpetas.first,
  );
}

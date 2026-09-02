import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/providers/el_permiso_pendiente.dart';
import 'package:nexus/features/assistant/presentation/widgets/el_permiso_dialogo.dart';

// El permiso que se pregunta en vez de decidirse solo.
//
// Con `--permission-prompt-tool stdio` el CLI deja de resolver los permisos por
// su cuenta y los manda por el canal de control. Lo que se prueba aquí es lo que
// no depende de lanzar el proceso: cómo se decide el modo, qué se le enseña a la
// persona y —lo que de verdad cuelga si se rompe— que **toda pregunta acaba
// contestada**.

class _Espia implements ClaudeCliDataSource {
  String? modo;
  var lePasaronAQuienPreguntar = false;

  @override
  Stream<Map<String, dynamic>> run(
    String instruction, {
    required String workingDirectory,
    required String permissionMode,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? appendSystemPrompt,
    String? configDir,
    String? model,
    String? effort,
    List<String> disallowedTools = const [],
    List<String> herramientasMcp = const [],
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) {
    modo = permissionMode;
    lePasaronAQuienPreguntar = alPedirPermiso != null;
    return const Stream.empty();
  }
}

Future<String?> _modoCon({
  required bool canEdit,
  required bool hayQuienConteste,
}) async {
  final espia = _Espia();
  await ClaudeBridgeImpl(espia)
      .ask(
        'lo que sea',
        workingDirectory: '/tmp',
        canEdit: canEdit,
        alPedirPermiso: hayQuienConteste
            ? (_) async => const PermisoDenegado('no')
            : null,
      )
      .drain<void>();
  return espia.modo;
}

void main() {
  // El motivo de la negación sale de los textos de la app, y esos miran el
  // idioma del sistema: sin binding, `PlatformDispatcher.instance` no existe.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('con qué modo se lanza', () {
    test('con alguien delante pregunta en vez de conceder', () async {
      expect(await _modoCon(canEdit: true, hayQuienConteste: true), 'default');
    });

    // La regresión que importa: la agenda y la cola de la carpeta corren sin
    // nadie, y ahí `default` sería un encargo colgado esperando un diálogo que
    // no va a abrir nadie.
    test('sin nadie delante se sigue concediendo solo', () async {
      expect(
        await _modoCon(canEdit: true, hayQuienConteste: false),
        'acceptEdits',
      );
    });

    // Una carpeta de solo lectura **no** pregunta: ese modo promete que no se
    // toca el disco, y convertirlo en un botón sería cambiar la promesa.
    test(
      'la carpeta de solo lectura no pregunta ni con nadie delante',
      () async {
        expect(
          await _modoCon(canEdit: false, hayQuienConteste: true),
          'manual',
        );
      },
    );
  });

  // El JSON de aquí abajo está **copiado de una sesión real** del CLI 2.1.258,
  // no inventado: el protocolo de control no está documentado y lo único que
  // sostiene esta traducción es lo que se midió contra el binario.
  group('lo que manda el CLI', () {
    test('un can_use_tool se traduce a una pregunta', () {
      final peticion = ClaudeCliDataSource.peticionDe({
        'type': 'control_request',
        'request_id': 'ebc6dbda-d247-4fac-9e86-9791ddf456aa',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'Write',
          'display_name': 'Write',
          'input': {
            'file_path': '/private/tmp/prueba.txt',
            'content': 'hola\n',
          },
          'description': 'prueba.txt',
          'permission_suggestions': [
            {
              'type': 'setMode',
              'mode': 'acceptEdits',
              'destination': 'session',
            },
          ],
          'tool_use_id': 'toolu_019UAUgo7DqcExuZyH85xkZM',
        },
      });

      expect(peticion, isNotNull);
      expect(peticion!.id, 'ebc6dbda-d247-4fac-9e86-9791ddf456aa');
      expect(peticion.herramienta, 'Write');
      expect(peticion.resumen, 'prueba.txt');
      expect(peticion.escribe, isTrue);
      expect(peticion.toolUseId, 'toolu_019UAUgo7DqcExuZyH85xkZM');
      expect(peticion.entrada['file_path'], '/private/tmp/prueba.txt');
    });

    // Por el mismo canal llegan cosas que no son preguntas para nadie. Tomar
    // una de esas por un permiso sería contestar a lo que no se preguntó.
    test('lo que no es un can_use_tool no lo es', () {
      expect(
        ClaudeCliDataSource.peticionDe({
          'type': 'control_request',
          'request_id': 'x',
          'request': {'subtype': 'request_user_dialog'},
        }),
        isNull,
      );
      expect(
        ClaudeCliDataSource.peticionDe({
          'type': 'assistant',
          'message': <String, dynamic>{},
        }),
        isNull,
      );
    });
  });

  group('qué se le enseña a la persona', () {
    PeticionDePermiso peticion(
      String herramienta,
      Map<String, dynamic> entrada, {
      String? descripcion,
    }) => PeticionDePermiso(
      id: 'r1',
      herramienta: herramienta,
      nombreVisible: herramienta,
      entrada: entrada,
      descripcion: descripcion,
    );

    test('manda la descripción del CLI cuando la hay', () {
      expect(
        peticion('Write', {
          'file_path': '/a/b.txt',
        }, descripcion: 'b.txt').resumen,
        'b.txt',
      );
    });

    test('sin descripción se compone con el argumento que se lee', () {
      expect(peticion('Bash', {'command': 'rm -rf /'}).resumen, 'rm -rf /');
      expect(peticion('Write', {'file_path': '/a/b.txt'}).resumen, '/a/b.txt');
    });

    test('leer no avisa de que escribe; lo que no se conoce, sí', () {
      expect(peticion('Read', {'file_path': '/a'}).escribe, isFalse);
      expect(peticion('Write', {'file_path': '/a'}).escribe, isTrue);
      // Ante la duda se exagera: una herramienta MCP que nadie ha visto antes
      // se anuncia como escritora. Quedarse corto es el fallo caro.
      expect(peticion('mcp__loQueSea__borrar', const {}).escribe, isTrue);
    });
  });

  group('el diálogo', () {
    Future<ProviderContainer> pintar(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: NexusTheme.dark(),
            builder: (context, child) =>
                StringsScope(strings: const NexusStringsEs(), child: child!),
            home: Scaffold(
              body: Stack(children: [ElPermisoDialogo.enElArbol()]),
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('no se ve mientras no haya nada que preguntar', (tester) async {
      await pintar(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('aparece con la pregunta y contesta al pulsar', (tester) async {
      final container = await pintar(tester);
      final pendiente = container.read(elPermisoPendienteProvider.notifier);

      final respuesta = pendiente.preguntar(
        const PeticionDePermiso(
          id: 'r1',
          herramienta: 'Write',
          nombreVisible: 'Write',
          entrada: {'file_path': '/tmp/a.txt'},
          descripcion: 'a.txt',
        ),
      );
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      // Lo que se aprueba es el argumento, no el nombre de la herramienta: si
      // esto no se ve, el diálogo pide firmar en blanco.
      expect(find.text('a.txt'), findsOneWidget);
      expect(find.text(const NexusStringsEs().permisoEscribe), findsOneWidget);

      await tester.tap(find.text(const NexusStringsEs().permisoConceder));
      await tester.pump();

      expect(await respuesta, isA<PermisoConcedido>());
      expect(find.byType(AlertDialog), findsNothing);
    });

    // Leer no lleva el aviso de que escribe: si lo llevara todo, no avisaría
    // de nada.
    testWidgets('leer no se anuncia como escritura', (tester) async {
      final container = await pintar(tester);
      container
          .read(elPermisoPendienteProvider.notifier)
          .preguntar(
            const PeticionDePermiso(
              id: 'r2',
              herramienta: 'Read',
              nombreVisible: 'Read',
              entrada: {'file_path': '/tmp/a.txt'},
            ),
          );
      await tester.pump();

      expect(find.text(const NexusStringsEs().permisoEscribe), findsNothing);
    });
  });

  group('la fila de preguntas', () {
    late ProviderContainer container;
    late ElPermisoPendiente pendiente;

    PeticionDePermiso peticion(String id) => PeticionDePermiso(
      id: id,
      herramienta: 'Write',
      nombreVisible: 'Write',
      entrada: {'file_path': '/$id'},
    );

    setUp(() {
      // El idioma se lee del disco al construirse, y sin esto la lectura
      // revienta por detrás **después** de que el test haya pasado.
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
      pendiente = container.read(elPermisoPendienteProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('lo que se concede vuelve con la entrada intacta', () async {
      final respuesta = pendiente.preguntar(peticion('uno'));
      pendiente.conceder();
      expect((await respuesta as PermisoConcedido).entrada, {
        'file_path': '/uno',
      });
    });

    test('lo que se niega vuelve con un motivo para el modelo', () async {
      final respuesta = pendiente.preguntar(peticion('uno'));
      pendiente.denegar();
      expect((await respuesta as PermisoDenegado).motivo, isNotEmpty);
    });

    // 🔴 La que justifica que esto sea una cola y no un hueco de uno. Claude
    // pide dos escrituras en el mismo turno y con un solo hueco la segunda
    // sobreescribía a la primera: su `Completer` se quedaba sin completar, o
    // sea el CLI esperando una respuesta que ya no llegaba nunca.
    test('dos preguntas a la vez se contestan las dos, por orden', () async {
      final primera = pendiente.preguntar(peticion('uno'));
      final segunda = pendiente.preguntar(peticion('dos'));

      expect(container.read(elPermisoPendienteProvider)?.id, 'uno');
      pendiente.conceder();
      expect(container.read(elPermisoPendienteProvider)?.id, 'dos');
      pendiente.denegar();

      expect(await primera, isA<PermisoConcedido>());
      expect(await segunda, isA<PermisoDenegado>());
      expect(container.read(elPermisoPendienteProvider), isNull);
    });

    // Parar el encargo con un diálogo abierto: el proceso se va a morir, pero
    // mientras tanto hay que soltar a quien esté esperando.
    test('descartar contesta a todo lo que quedaba', () async {
      final primera = pendiente.preguntar(peticion('uno'));
      final segunda = pendiente.preguntar(peticion('dos'));
      pendiente.descartarTodo();

      expect(await primera, isA<PermisoDenegado>());
      expect(await segunda, isA<PermisoDenegado>());
      expect(container.read(elPermisoPendienteProvider), isNull);
    });
  });
}

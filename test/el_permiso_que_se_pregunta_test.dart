import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

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
      // La salida de «no me lo preguntes más» viene en la propia petición.
      expect(peticion.sugerencias, hasLength(1));
      expect(peticion.sugerencias.first['mode'], 'acceptEdits');
      expect(peticion.sePuedeConcederTodo, isTrue);
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
}

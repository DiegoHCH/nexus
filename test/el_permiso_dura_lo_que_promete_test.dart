import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/el_modo_que_se_concedio.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';

// «Permitir todo» tiene que durar lo que dice, y decía «el resto de la sesión».
//
// Reportado usando la app: **pide permiso cada vez que va a editar un archivo**,
// con la carpeta en «puede editar». No era la carpeta. Ese botón no devuelve una
// lista de permisos —medido contra el CLI 2.1.258, lo que ofrece un `Write` es
// `{"type":"setMode","mode":"acceptEdits","destination":"session"}`—, o sea que le
// pide al CLI cambiar el modo de **su** sesión. Y esa sesión es el proceso
// `claude -p`, que muere al terminar el encargo: el siguiente arrancaba otra vez
// en `default` y volvía a preguntar lo mismo.
//
// Lo que se prueba aquí es que el modo concedido sobreviva al encargo y **no
// suba nada** por el camino.

class _Espia implements ClaudeCliDataSource {
  String? modo;

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
    return const Stream.empty();
  }
}

Future<String?> _modoCon({
  required bool canEdit,
  required bool hayQuienConteste,
  String? concedido,
}) async {
  final espia = _Espia();
  await ClaudeBridgeImpl(espia)
      .ask(
        'lo que sea',
        workingDirectory: '/tmp',
        canEdit: canEdit,
        modoConcedido: concedido,
        alPedirPermiso: hayQuienConteste
            ? (_) async => const PermisoDenegado('no')
            : null,
      )
      .drain<void>();
  return espia.modo;
}

/// El puente que apunta con qué modo le llegó cada encargo y, si le dan a quien
/// preguntar, pregunta una vez — que es lo que dispara el guardado.
class _Puente implements ClaudeBridge {
  final modos = <String?>[];
  final respuestas = <RespuestaDePermiso>[];

  @override
  Stream<ClaudeEvent> ask(
    String instruction, {
    required String workingDirectory,
    required bool canEdit,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? claudeProfile,
    String? model,
    String? effort,
    String? artifactsFolder,
    String? carpetaDePruebas,
    List<String> disallowedTools = const [],
    List<String> comandosPermitidos = const [],
    String? constraintsNotice,
    String? language,
    String? nombres,
    String? modoConcedido,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    modos.add(modoConcedido);
    if (alPedirPermiso != null) {
      respuestas.add(
        await alPedirPermiso(
          const PeticionDePermiso(
            id: 'r1',
            herramienta: 'Write',
            nombreVisible: 'Write',
            entrada: {'file_path': 'notas.md'},
            sugerencias: [
              {
                'type': 'setMode',
                'mode': 'acceptEdits',
                'destination': 'session',
              },
            ],
          ),
        ),
      );
    }
    yield const ClaudeTurnCompleted(result: 'hecho');
  }
}

/// La memoria de verdad guarda en preferencias; aquí basta con que recuerde.
class _Memoria implements ConversationMemory {
  _Memoria({this.modo});

  String? modo;
  final guardados = <String>[];

  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      FolderMemory(permissionMode: modo);

  @override
  Future<void> rememberSession(
    String f,
    String id, {
    String? claudeProfile,
  }) async {}

  @override
  Future<void> rememberPrompt(String f, String p) async {}

  @override
  Future<void> rememberPermissionMode(
    String f,
    String mode, {
    String? claudeProfile,
  }) async {
    guardados.add(mode);
    modo = mode;
  }

  @override
  Future<void> forget(String f) async {
    modo = null;
  }
}

class _Awake implements StaysAwake {
  @override
  Future<void Function()> hold(String reason) async => () {};
}

AskClaude _armar(
  _Puente puente,
  _Memoria memoria, {
  required bool carpetaEscribe,
}) => AskClaude(
  puente,
  (_) async => (
    workingDirectory: '/repo',
    canEdit: carpetaEscribe,
    extraDirectories: const <String>[],
    language: 'español',
    claudeProfile: null,
    model: null,
    effort: null,
    artifactsFolder: null,
    carpetaDePruebas: null,
    nombres: null,
    disallowedTools: const <String>[],
    comandosPermitidos: const <String>[],
    constraintsNotice: null,
  ),
  memoria,
  FolderErrandQueue(),
  _Awake(),
);

Future<RespuestaDePermiso> _diQueSi(PeticionDePermiso peticion) async =>
    PermisoConcedido(peticion.entrada, permisosNuevos: peticion.sugerencias);

void main() {
  // El motivo de la negación sale de los textos de la app, y esos miran el
  // idioma del sistema: sin binding, `PlatformDispatcher.instance` no existe.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('qué modo quedó concedido', () {
    // El JSON está copiado de una sesión real del CLI 2.1.258, como el del resto
    // de este protocolo: no está documentado y lo único que sostiene la
    // traducción es lo medido contra el binario.
    test('un setMode de sesión se recuerda', () {
      expect(
        ElModoQueSeConcedio.en(
          const PermisoConcedido(
            {},
            permisosNuevos: [
              {
                'type': 'setMode',
                'mode': 'acceptEdits',
                'destination': 'session',
              },
            ],
          ),
        ),
        'acceptEdits',
      );
    });

    test('conceder solo esta vez no deja modo', () {
      expect(ElModoQueSeConcedio.en(const PermisoConcedido({})), isNull);
    });

    test('denegar tampoco', () {
      expect(ElModoQueSeConcedio.en(const PermisoDenegado('no')), isNull);
    });

    // Las reglas de los comandos viajan por otro camino que no está medido, y
    // traducir a ciegas un protocolo sin documentar es como se acaba guardando
    // un permiso más ancho del que se concedió.
    test('un addRules no se traduce a un modo', () {
      expect(
        ElModoQueSeConcedio.en(
          const PermisoConcedido(
            {},
            permisosNuevos: [
              {'type': 'addRules'},
            ],
          ),
        ),
        isNull,
      );
    });

    // 🔴 La lista es blanca a propósito. Con un filtro por exclusión, el día que
    // el CLI ofrezca esto, «permítele escribir este archivo» se guardaría como
    // «no vuelvas a preguntar nada nunca» — que no es lo que nadie pulsó.
    test('un modo que no conocemos no se guarda', () {
      expect(
        ElModoQueSeConcedio.en(
          const PermisoConcedido(
            {},
            permisosNuevos: [
              {
                'type': 'setMode',
                'mode': 'bypassPermissions',
                'destination': 'session',
              },
            ],
          ),
        ),
        isNull,
      );
    });

    // Lo que el CLI marca para otro destino no es de esta sesión, y guardarlo
    // sería estirar el permiso a donde no se dio.
    test('un modo que no es de la sesión no se guarda', () {
      expect(
        ElModoQueSeConcedio.en(
          const PermisoConcedido(
            {},
            permisosNuevos: [
              {
                'type': 'setMode',
                'mode': 'acceptEdits',
                'destination': 'localSettings',
              },
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('con qué modo arranca el encargo siguiente', () {
    test('lo concedido gana a preguntar', () async {
      expect(
        await _modoCon(
          canEdit: true,
          hayQuienConteste: true,
          concedido: 'acceptEdits',
        ),
        'acceptEdits',
      );
    });

    // 🔴 El orden que importa: lo concedido puede ahorrar una pregunta, **nunca**
    // abrir una carpeta que promete no tocar el disco. Si esto fallara, apagar
    // «puede editar» dejaría de significar nada en cuanto se hubiera concedido
    // algo antes.
    test('lo concedido NO gana a la solo lectura', () async {
      expect(
        await _modoCon(
          canEdit: false,
          hayQuienConteste: true,
          concedido: 'acceptEdits',
        ),
        'manual',
      );
    });

    test('sin nada concedido, se sigue preguntando', () async {
      expect(await _modoCon(canEdit: true, hayQuienConteste: true), 'default');
    });
  });

  group('de un encargo al siguiente', () {
    test('permitir todo se guarda y el siguiente no pregunta', () async {
      final puente = _Puente();
      final memoria = _Memoria();
      final ask = _armar(puente, memoria, carpetaEscribe: true);

      await ask('escribe algo', alPedirPermiso: _diQueSi).drain<void>();

      expect(memoria.guardados, ['acceptEdits']);
      // El primero llegó sin nada: es donde se preguntó.
      expect(puente.modos.first, isNull);

      await ask('y ahora otra cosa', alPedirPermiso: _diQueSi).drain<void>();

      expect(puente.modos.last, 'acceptEdits');
    });

    test('conceder solo esta vez no deja nada guardado', () async {
      final puente = _Puente();
      final memoria = _Memoria();

      await _armar(puente, memoria, carpetaEscribe: true)(
        'escribe algo',
        alPedirPermiso: (peticion) async => PermisoConcedido(peticion.entrada),
      ).drain<void>();

      expect(memoria.guardados, isEmpty);
    });

    // El tope del encargo es lo que trae el canal del teléfono sin la frase de
    // escritura. Heredar por aquí lo que se concedió desde el escritorio sería
    // devolverle justo lo que el tope le quitó.
    test('el tope cerrado no hereda lo concedido', () async {
      final puente = _Puente();
      final memoria = _Memoria(modo: 'acceptEdits');

      await _armar(puente, memoria, carpetaEscribe: true)(
        'escribe algo',
        allowWrites: false,
      ).drain<void>();

      expect(puente.modos.single, isNull);
    });

    test('la carpeta en solo lectura tampoco lo hereda', () async {
      final puente = _Puente();
      final memoria = _Memoria(modo: 'acceptEdits');

      await _armar(puente, memoria, carpetaEscribe: false)(
        'escribe algo',
      ).drain<void>();

      expect(puente.modos.single, isNull);
    });
  });
}

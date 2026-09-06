import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

// El tope de escritura: **baja lo que la carpeta concede, y nunca lo sube**.
//
// Es la mitad de seguridad de la fase 4.1. El canal del teléfono manda encargos con
// el tope en `false` mientras no tenga abierta la frase de escritura, y ese tope
// tiene que llegar hasta donde se decide el `canEdit` — que es un solo sitio.
//
// Y viaja **con el encargo** y no en un ajuste global a propósito: si fuera global,
// capar al teléfono caparía también los encargos lanzados desde el escritorio, y
// entonces tener el móvil conectado te quitaría permisos a ti.
class _Bridge implements ClaudeBridge {
  final permisos = <bool>[];

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
    String? laConsola,
    List<String> disallowedTools = const [],
    List<String> comandosPermitidos = const [],
    String? constraintsNotice,
    String? language,
    String? nombres,
    String? modoConcedido,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    // Lo único que esta prueba mira: con qué permiso llegó al puente, que es lo
    // último antes de `claude -p`.
    permisos.add(canEdit);
    yield const ClaudeTurnCompleted(result: 'hecho');
  }
}

class _Memory implements ConversationMemory {
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory(sessionId: null, prompts: []);
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
  }) async {}

  @override
  Future<void> forget(String f) async {}
}

class _Awake implements StaysAwake {
  @override
  Future<void Function()> hold(String reason) async => () {};
}

void main() {
  AskClaude armar(_Bridge bridge, {required bool carpetaEscribe}) => AskClaude(
    bridge,
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
      laConsola: null,
      nombres: null,
      disallowedTools: const <String>[],
      comandosPermitidos: const <String>[],
      constraintsNotice: null,
    ),
    _Memory(),
    FolderErrandQueue(),
    _Awake(),
  );

  // Las cuatro combinaciones, porque un AND mal escrito acierta en tres de ellas.
  test('carpeta escribe + tope abierto = escribe', () async {
    final bridge = _Bridge();
    await armar(bridge, carpetaEscribe: true)('haz algo').drain<void>();
    expect(bridge.permisos.single, isTrue);
  });

  test('carpeta escribe + tope cerrado = NO escribe', () async {
    // El caso del teléfono en solo lectura sobre una carpeta que sí permite
    // escribir. Es el que justifica que el tope exista.
    final bridge = _Bridge();
    await armar(bridge, carpetaEscribe: true)(
      'haz algo',
      allowWrites: false,
    ).drain<void>();
    expect(bridge.permisos.single, isFalse);
  });

  test('carpeta en solo lectura + tope abierto = NO escribe', () async {
    // El tope **no sube nada**: la carpeta manda hacia abajo. Si esto pasara, el
    // canal podría conceder lo que el Mac negó.
    final bridge = _Bridge();
    await armar(bridge, carpetaEscribe: false)('haz algo').drain<void>();
    expect(bridge.permisos.single, isFalse);
  });

  test('carpeta en solo lectura + tope cerrado = NO escribe', () async {
    final bridge = _Bridge();
    await armar(bridge, carpetaEscribe: false)(
      'haz algo',
      allowWrites: false,
    ).drain<void>();
    expect(bridge.permisos.single, isFalse);
  });

  test('por omisión el tope está abierto: el escritorio no cambia', () async {
    // Lo que protege a quien ya usaba la app: añadir el parámetro no puede haber
    // quitado permisos a los encargos que se lanzan escribiendo.
    final bridge = _Bridge();
    await armar(bridge, carpetaEscribe: true)('haz algo').drain<void>();
    expect(bridge.permisos.single, isTrue);
  });
}

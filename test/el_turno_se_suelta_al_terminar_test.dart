import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';

/// El turno de la carpeta se suelta cuando **termina el turno**, no cuando
/// muere el proceso.
///
/// 🔴 **Eran lo mismo hasta que se midió que no.** Un `claude -p` no sale hasta
/// que mueren sus servidores MCP, y con un MCP en JVM —Maestro— o en `uvx` eso
/// son minutos después de haber contestado.
///
/// Medido en la máquina: encargo arrancado a las 23:15:00, turno archivado a
/// las 23:15:09, y el proceso todavía vivo a las 23:18:25 con cinco hijos. La
/// carpeta quedaba tomada esos tres minutos por un encargo terminado, y lo
/// siguiente que se escribía contestaba «esperando a la otra conversación sobre
/// esta carpeta» — sin otra conversación y sin nadie trabajando. Se reportó
/// como un cuelgue, y es lo que era.
const _carpeta = '/repo';

/// Un puente que contesta y **deja el stream abierto**, como el proceso cuyos
/// MCP tardan en morir.
class _PuenteQueSeQuedaVivo implements ClaudeBridge {
  final apagado = Completer<void>();
  var vueltas = 0;

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
    Object? alPedirPermiso,
  }) async* {
    final mia = vueltas++;
    yield const ClaudeSessionStarted(
      sessionId: 'sesion',
      model: 'claude-opus-5',
    );
    yield ClaudeTurnCompleted(result: 'contestado $mia');
    // El primero se queda colgado apagando hijos; el segundo cierra enseguida,
    // porque lo que se mide es que el segundo **pueda entrar**.
    if (mia == 0) await apagado.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SinMemoria implements ConversationMemory {
  const _SinMemoria();
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory();
  @override
  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  }) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> forget(String folderPath) async {}
}

class _Despierto implements StaysAwake {
  var sueltos = 0;
  @override
  Future<void Function()> hold(String reason) async =>
      () => sueltos++;
}

void main() {
  late FolderErrandQueue cola;
  late _PuenteQueSeQuedaVivo puente;
  late _Despierto despierto;

  AskClaude construir() => AskClaude(
    puente,
    (_) async => (
      workingDirectory: _carpeta,
      canEdit: false,
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
    const _SinMemoria(),
    cola,
    despierto,
  );

  setUp(() {
    cola = FolderErrandQueue();
    puente = _PuenteQueSeQuedaVivo();
    despierto = _Despierto();
    // **El puente se desbloquea al acabar, y nunca se cancela la suscripción.**
    // Cancelar un generador suspendido en este completer espera a que termine
    // su limpieza, que es justo lo que el completer impide: la prueba se
    // colgaba treinta segundos y moría por plazo.
    addTearDown(() {
      if (!puente.apagado.isCompleted) puente.apagado.complete();
    });
  });

  /// Espera hasta que el turno haya terminado, sin fiarse de un número de
  /// vueltas: por delante hay varios `await` —el permiso del Mac, la cola, la
  /// memoria— y contar microtasks es adivinar.
  Future<void> hastaElFinDeTurno(List<ClaudeEvent> visto) async {
    for (var i = 0; i < 200; i++) {
      if (visto.whereType<ClaudeTurnCompleted>().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'con el turno terminado la carpeta queda libre, aunque el proceso siga',
    () async {
      final askClaude = construir();
      final visto = <ClaudeEvent>[];
      // Se escucha sin cancelar: cancelar sería el caso del `finally`, y lo que
      // se mide aquí es el otro —el encargo que terminó bien y no se ha ido—.
      askClaude('lo primero').listen(visto.add);
      await hastaElFinDeTurno(visto);

      expect(visto.whereType<ClaudeTurnCompleted>(), hasLength(1));
      expect(
        puente.apagado.isCompleted,
        isFalse,
        reason: 'el proceso sigue ahí',
      );
      expect(
        cola.isBusy(_carpeta),
        isFalse,
        reason:
            'el turno terminó: la carpeta no puede seguir tomada por los MCP '
            'que están tardando en morir',
      );
    },
  );

  test('y el encargo siguiente entra sin esperar ni anunciar espera', () async {
    final askClaude = construir();
    final primero = <ClaudeEvent>[];
    askClaude('lo primero').listen(primero.add);
    await hastaElFinDeTurno(primero);

    // El segundo se lanza con el primero todavía sin cerrar.
    final segundo = await askClaude('lo segundo').toList();

    expect(
      segundo.whereType<ClaudeQueued>(),
      isEmpty,
      reason:
          'no hay a quién esperar, así que tampoco hay que anunciar una '
          'espera: ese aviso es lo que se leía como un cuelgue',
    );
    expect(
      segundo.whereType<ClaudeTurnCompleted>().single.result,
      'contestado 1',
      reason: 'y sobre todo: contesta, en vez de quedarse en la cola',
    );
    expect(puente.apagado.isCompleted, isFalse);
  });

  test('el turno se suelta una vez, no dos', () async {
    final askClaude = construir();
    // Aquí el proceso sí muere enseguida: lo que se mide es que el `finally`
    // vuelva a soltar sobre un turno ya soltado sin reventar.
    puente.apagado.complete();
    final visto = await askClaude('lo primero y único').toList();

    expect(visto.whereType<ClaudeTurnCompleted>(), hasLength(1));
    // El `finally` vuelve a soltar cuando el stream cierra. Es idempotente a
    // propósito —`release` se guarda solo—, y si no lo fuera, esta segunda
    // llamada completaría un `Completer` ya completado y reventaría.
    expect(cola.isBusy(_carpeta), isFalse);
    expect(despierto.sueltos, 1, reason: 'y lo del Mac despierto, igual');
  });
}

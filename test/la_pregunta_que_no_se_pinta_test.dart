import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_no_se_puede_pintar.dart';

// La herramienta que se concedía y no se pintaba.
//
// Medido en una conversación de verdad: Claude abrió un `AskUserQuestion` para
// decidir por dónde resolver un `quoteId`, el permiso se concedió, y el turno
// siguiente empezó con «Quedó sin respuesta el diálogo; te lo dejo en texto por
// si no te llegó». La decisión se perdió y el trabajo siguió sin ella.

class _Espia implements ClaudeCliDataSource {
  List<String> negadas = const [];

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
    negadas = disallowedTools;
    return const Stream.empty();
  }
}

Future<List<String>> _negadasCon({required bool canEdit}) async {
  final espia = _Espia();
  await ClaudeBridgeImpl(
    espia,
  ).ask('lo que sea', workingDirectory: '/tmp', canEdit: canEdit).drain<void>();
  return espia.negadas;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no se le ofrece lo que no se puede enseñar', () async {
    expect(await _negadasCon(canEdit: true), contains('AskUserQuestion'));
  });

  // 🔴 **Siempre, escriba la carpeta o no.** Esto no es un permiso: es que la
  // interfaz no existe, y eso no depende de lo que la carpeta conceda.
  test('también en solo lectura', () async {
    expect(await _negadasCon(canEdit: false), contains('AskUserQuestion'));
  });

  test('sin llevarse por delante lo que ya se negaba', () async {
    final espia = _Espia();
    await ClaudeBridgeImpl(espia)
        .ask(
          'lo que sea',
          workingDirectory: '/tmp',
          canEdit: true,
          disallowedTools: const ['Bash(*pod install*)'],
        )
        .drain<void>();

    expect(espia.negadas, contains('Bash(*pod install*)'));
    expect(espia.negadas, contains('AskUserQuestion'));
  });

  // La lista existe para vaciarse: el día que el diálogo se pinte de verdad,
  // esto se queda sin motivo y se borra entero.
  test('la lista dice qué falta por pintar, y hoy es una sola cosa', () {
    expect(LoQueNoSePuedePintar.herramientas, ['AskUserQuestion']);
  });
}

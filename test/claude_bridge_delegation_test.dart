import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';

/// Un turno de verdad, grabado del binario.
///
/// `test/fixtures/delegacion_real.jsonl` salió de correr `claude -p` pidiéndole
/// que delegara en un subagente, y se guardó tal cual llegó. La forma del
/// stream no está documentada y ya cambió una vez —la herramienta se llama
/// `Task` en unas sesiones y `Agent` en otras—, así que probar contra un
/// ejemplo inventado solo confirmaría lo que creemos, no lo que manda.
class _RecordedDataSource extends ClaudeCliDataSource {
  const _RecordedDataSource();

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
  }) async* {
    final lines = File(
      'test/fixtures/delegacion_real.jsonl',
    ).readAsLinesSync().where((line) => line.trim().isNotEmpty);
    for (final line in lines) {
      yield jsonDecode(line) as Map<String, dynamic>;
    }
  }
}

void main() {
  test('los pasos del subagente vienen colgados de la delegación', () async {
    final events = await const ClaudeBridgeImpl(
      _RecordedDataSource(),
    ).ask('da igual', workingDirectory: '/tmp', canEdit: false).toList();

    final tools = events.whereType<ClaudeToolUsed>().toList();
    final delegation = tools.singleWhere(
      (tool) => tool.description.startsWith('Delegando:'),
    );

    // En esta grabación el CLI la llamó `Agent`: es exactamente el caso que
    // antes salía como «Usando Agent», sin decir qué se encargó.
    expect(delegation.description, 'Delegando: List files and count lines');
    expect(delegation.parentId, isNull);

    final children = tools
        .where((tool) => tool.parentId == delegation.id)
        .toList();
    expect(children, hasLength(2));
    expect(
      children.every((tool) => tool.description.startsWith('Corriendo')),
      isTrue,
    );

    // Y la delegación se cierra con el resultado de su propia herramienta, que
    // es la señal de que el subagente terminó.
    final finished = events.whereType<ClaudeToolFinished>().map((e) => e.id);
    expect(finished, contains(delegation.id));
    for (final child in children) {
      expect(finished, contains(child.id));
    }
  });
}

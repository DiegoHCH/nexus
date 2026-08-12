import 'package:nexus/features/assistant/data/datasources/conversation_memory_data_source.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';

class ConversationMemoryImpl implements ConversationMemory {
  const ConversationMemoryImpl(this._dataSource);

  /// Cuántas peticiones se guardan por carpeta. Suficientes para el panel y la
  /// hoja de historial; no es un archivo histórico.
  static const _maxPrompts = 30;

  final ConversationMemoryDataSource _dataSource;

  @override
  Future<FolderMemory> read(String folderPath) async {
    final all = await _dataSource.read();
    final entry = all[folderPath];
    if (entry is! Map<String, dynamic>) return const FolderMemory();
    return FolderMemory(
      sessionId: entry['sessionId'] as String?,
      prompts: [
        for (final prompt in entry['prompts'] as List<dynamic>? ?? const [])
          if (prompt is String && prompt.isNotEmpty) prompt,
      ],
    );
  }

  @override
  Future<void> rememberSession(String folderPath, String sessionId) async {
    await _update(
      folderPath,
      (memory) => memory.copyWith(sessionId: sessionId),
    );
  }

  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {
    await _update(folderPath, (memory) {
      final rest = memory.prompts.where((item) => item != prompt);
      return memory.copyWith(
        prompts: [prompt, ...rest].take(_maxPrompts).toList(),
      );
    });
  }

  @override
  Future<void> forget(String folderPath) async {
    await _update(folderPath, (memory) => memory.copyWith(forget: true));
  }

  /// Lee, transforma y escribe de una pieza: dos escrituras a la vez se
  /// pisarían, y aquí llegan seguidas —guardar la petición y guardar la sesión
  /// pasan con milisegundos de diferencia.
  Future<void> _update(
    String folderPath,
    FolderMemory Function(FolderMemory) change,
  ) async {
    final all = await _dataSource.read();
    final current = await read(folderPath);
    final next = change(current);
    all[folderPath] = {'sessionId': next.sessionId, 'prompts': next.prompts};
    await _dataSource.write(all);
  }
}

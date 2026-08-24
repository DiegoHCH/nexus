import 'package:nexus/features/assistant/data/datasources/conversation_memory_data_source.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';

class ConversationMemoryImpl implements ConversationMemory {
  const ConversationMemoryImpl(this._dataSource);

  /// Cuántas peticiones se guardan por carpeta. Suficientes para el panel y la
  /// hoja de historial; no es un archivo histórico.
  static const _maxPrompts = 30;

  final ConversationMemoryDataSource _dataSource;

  /// Con qué nombre se guarda la sesión de cada cuenta dentro de la carpeta.
  ///
  /// La ruta del perfil tal cual, porque es lo que identifica la cuenta de
  /// verdad —el `CLAUDE_CONFIG_DIR`— y no hay dos iguales. Sin perfil elegido
  /// se usa una clave fija: la carpeta corre con la cuenta de fábrica, que
  /// también es una cuenta concreta.
  static String _account(String? claudeProfile) =>
      (claudeProfile == null || claudeProfile.isEmpty)
      ? 'por defecto'
      : claudeProfile;

  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async {
    final all = await _dataSource.read();
    final entry = all[folderPath];
    if (entry is! Map<String, dynamic>) return const FolderMemory();
    return FolderMemory(
      sessionId: _sessionIn(entry, claudeProfile),
      prompts: [
        if (entry['prompts'] case final List<dynamic> stored)
          for (final prompt in stored)
            if (prompt is String && prompt.isNotEmpty) prompt,
      ],
    );
  }

  /// La sesión de esa cuenta, o la que quedara guardada antes de que hubiera
  /// cuentas.
  ///
  /// Comprobado en vez de convertido a la fuerza: esto se lee al abrir la app,
  /// y una preferencia escrita por una versión anterior —o tocada a mano— con
  /// otro tipo aquí dentro tumbaba la lectura entera. Perder la memoria de una
  /// carpeta es molesto; no arrancar, inaceptable.
  ///
  /// El `sessionId` suelto es el formato viejo y **se sigue leyendo**: para la
  /// inmensa mayoría de carpetas —las que solo se han usado con una cuenta— esa
  /// sesión es justamente la de la cuenta que pregunta, y tirarla haría que
  /// todas perdieran el hilo al actualizar. Si resultara ser de otra cuenta, el
  /// reintento sin `--resume` lo absorbe y la carpeta se cura sola (b14). En
  /// cuanto se guarde una sesión nueva, esta carpeta pasa al formato por
  /// cuenta y el suelto desaparece.
  static String? _sessionIn(Map<String, dynamic> entry, String? claudeProfile) {
    if (entry['sessions'] case final Map<String, dynamic> sessions) {
      return switch (sessions[_account(claudeProfile)]) {
        final String id when id.isNotEmpty => id,
        _ => null,
      };
    }
    return switch (entry['sessionId']) {
      final String id when id.isNotEmpty => id,
      _ => null,
    };
  }

  @override
  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  }) async {
    await _update(folderPath, (entry) {
      final sessions = <String, dynamic>{
        if (entry['sessions'] case final Map<String, dynamic> previous)
          ...previous,
        _account(claudeProfile): sessionId,
      };
      // Las demás cuentas conservan la suya: la misma carpeta abierta con dos
      // perfiles son dos hilos, y guardar solo el último obligaría a empezar de
      // cero cada vez que se cambia.
      return {...entry, 'sessions': sessions}..remove('sessionId');
    });
  }

  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {
    await _update(folderPath, (entry) {
      final stored = [
        if (entry['prompts'] case final List<dynamic> previous)
          for (final item in previous)
            if (item is String && item.isNotEmpty) item,
      ];
      final rest = stored.where((item) => item != prompt);
      return {
        ...entry,
        'prompts': [prompt, ...rest].take(_maxPrompts).toList(),
      };
    });
  }

  @override
  Future<void> forget(String folderPath) async {
    // Se van las de **todas** las cuentas: «empezar de cero en esta carpeta» no
    // significa «en esta carpeta con la cuenta que tenga puesta ahora».
    await _update(
      folderPath,
      (entry) =>
          {...entry, 'sessions': <String, dynamic>{}}..remove('sessionId'),
    );
  }

  /// Lee, transforma y escribe de una pieza: dos escrituras a la vez se
  /// pisarían, y aquí llegan seguidas —guardar la petición y guardar la sesión
  /// pasan con milisegundos de diferencia.
  Future<void> _update(
    String folderPath,
    Map<String, dynamic> Function(Map<String, dynamic>) change,
  ) async {
    final all = await _dataSource.read();
    final current = all[folderPath];
    all[folderPath] = change(
      current is Map<String, dynamic> ? current : <String, dynamic>{},
    );
    await _dataSource.write(all);
  }
}

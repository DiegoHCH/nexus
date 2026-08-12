/// Lo que Nexus recuerda de una carpeta entre conversaciones.
///
/// Va por carpeta y no global a propósito: la conversación sobre un repo no
/// tiene nada que ver con la de otro, y mezclarlas produciría un asistente que
/// arrastra contexto ajeno a donde no toca.
class FolderMemory {
  const FolderMemory({this.sessionId, this.prompts = const []});

  /// La sesión de Claude que se puede reanudar. `null` cuando no hay ninguna
  /// o cuando el usuario decidió empezar de cero.
  final String? sessionId;

  /// Lo que se le pidió, de lo más reciente hacia atrás.
  final List<String> prompts;

  FolderMemory copyWith({
    String? sessionId,
    List<String>? prompts,
    bool forget = false,
  }) {
    return FolderMemory(
      sessionId: forget ? null : (sessionId ?? this.sessionId),
      prompts: prompts ?? this.prompts,
    );
  }
}

abstract class ConversationMemory {
  Future<FolderMemory> read(String folderPath);

  Future<void> rememberSession(String folderPath, String sessionId);

  Future<void> rememberPrompt(String folderPath, String prompt);

  /// Olvida la conversación de esa carpeta: la próxima empieza limpia.
  ///
  /// Existe porque una memoria que no se puede tirar es una trampa: cuando el
  /// contexto arrastrado estorba —cambiaste de tarea, o la sesión se enredó—
  /// tiene que haber una salida que no sea borrar preferencias a mano.
  Future<void> forget(String folderPath);
}

/// Lo que Nexus recuerda de una carpeta entre conversaciones.
///
/// Va por carpeta y no global a propósito: la conversación sobre un repo no
/// tiene nada que ver con la de otro, y mezclarlas produciría un asistente que
/// arrastra contexto ajeno a donde no toca.
class FolderMemory {
  const FolderMemory({
    this.sessionId,
    this.prompts = const [],
    this.permissionMode,
  });

  /// La sesión de Claude que se puede reanudar. `null` cuando no hay ninguna
  /// o cuando el usuario decidió empezar de cero.
  final String? sessionId;

  /// Lo que se le pidió, de lo más reciente hacia atrás.
  final List<String> prompts;

  /// El modo de permisos en que quedó esta sesión, o `null` para el de siempre.
  ///
  /// **Es lo que hace que «Permitir todo» dure lo que promete.** Ese botón no
  /// devuelve una lista de permisos: le pide al CLI que cambie el modo de la
  /// sesión, y el modo vive en el proceso `claude -p`, que muere al terminar el
  /// encargo. Sin recordarlo aquí, el encargo siguiente volvía a preguntar lo
  /// mismo —y el mensaje decía «y el resto de la sesión», así que se leía como
  /// un botón que no hace nada—.
  ///
  /// Va al lado del [sessionId] y no en un ajuste porque **tiene su misma
  /// vida**: es un permiso de esta sesión, no una preferencia tuya. Empezar de
  /// cero en la carpeta se lo lleva con la sesión, que es lo correcto: el
  /// permiso se concedió sobre un hilo, y ese hilo ya no está.
  final String? permissionMode;

  FolderMemory copyWith({
    String? sessionId,
    List<String>? prompts,
    String? permissionMode,
    bool forget = false,
  }) {
    return FolderMemory(
      sessionId: forget ? null : (sessionId ?? this.sessionId),
      prompts: prompts ?? this.prompts,
      permissionMode: forget ? null : (permissionMode ?? this.permissionMode),
    );
  }
}

abstract class ConversationMemory {
  /// [claudeProfile] porque **una sesión es de la carpeta y de la cuenta**, no
  /// solo de la carpeta. Las sesiones que guarda Claude Code viven dentro del
  /// `CLAUDE_CONFIG_DIR` de cada cuenta, así que la misma carpeta abierta con
  /// otro perfil no tiene esa sesión — y reanudarla fallaba con «No
  /// conversation found with session ID» (b14). Lo pedido, en cambio, sigue
  /// siendo de la carpeta: es para repetir una petición, y quién la ejecutó da
  /// igual.
  Future<FolderMemory> read(String folderPath, {String? claudeProfile});

  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  });

  Future<void> rememberPrompt(String folderPath, String prompt);

  /// El modo que quedó concedido en esta carpeta y con esta cuenta.
  ///
  /// Por cuenta como la sesión, y por el mismo motivo: el permiso se concedió
  /// sobre un hilo concreto, y el de la otra cuenta es otro hilo. Ver
  /// [FolderMemory.permissionMode].
  Future<void> rememberPermissionMode(
    String folderPath,
    String mode, {
    String? claudeProfile,
  });

  /// Olvida la conversación de esa carpeta: la próxima empieza limpia.
  ///
  /// Existe porque una memoria que no se puede tirar es una trampa: cuando el
  /// contexto arrastrado estorba —cambiaste de tarea, o la sesión se enredó—
  /// tiene que haber una salida que no sea borrar preferencias a mano.
  Future<void> forget(String folderPath);
}

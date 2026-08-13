import 'package:nexus/features/assistant/domain/entities/claude_event.dart';

/// El puente hacia `claude -p` headless. Cada llamada a [ask] es un turno
/// independiente: no mantiene una sesión abierta entre instrucciones (eso es
/// trabajo de la Fase 3, con `--resume`).
abstract class ClaudeBridge {
  /// [workingDirectory] es obligatorio a propósito: sin él el proceso hereda
  /// el directorio de la app —`/` para un bundle lanzado por launchd— y
  /// responde sobre la raíz del disco sin avisar. Que no se pueda llamar sin
  /// decidirlo es la mitad del arreglo.
  Stream<ClaudeEvent> ask(
    String instruction, {
    required String workingDirectory,
    required bool canEdit,
    List<String> extraDirectories,
    String? resumeSessionId,

    /// El `CLAUDE_CONFIG_DIR` con el que trabajar: es lo que decide **con qué
    /// cuenta** corre el encargo.
    String? claudeProfile,

    /// Alias del modelo y nivel de esfuerzo. `null` deja lo que el CLI tenga.
    String? model,
    String? effort,

    /// Lo que no se puede ejecutar aquí, en la sintaxis del CLI.
    List<String> disallowedTools,
  });
}

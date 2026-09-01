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

    /// Dónde dejar lo que genere para mirar. `null` si el usuario no ha
    /// elegido carpeta, y entonces no se le dice nada.
    String? artifactsFolder,

    /// Dónde van las pruebas de este proyecto, si lo declaró. `null` cuando vale la
    /// convención de Maestro, y entonces tampoco se le dice nada: `.maestro/` la sabe.
    String? carpetaDePruebas,

    /// Lo que no se puede ejecutar aquí, en la sintaxis del CLI.
    List<String> disallowedTools,

    /// Lo que **sí** se puede ejecutar sin que nadie apruebe, en la sintaxis del
    /// CLI. Llega vacía cuando la carpeta es de solo lectura: ese modo garantiza
    /// el disco, y un comando permitido escribiría igual.
    List<String> comandosPermitidos,

    /// Lo que Claude tiene que saber antes de empezar sobre lo que puede y no
    /// puede correr aquí. Sin esto tropieza a media tarea y se calla.
    String? constraintsNotice,

    /// En qué idioma contestar si el encargo no pide otra cosa.
    ///
    /// **Va por aquí y no pegada al encargo**, y la diferencia no es de estilo. Lo que
    /// escribe la persona puede ser un comando de otra herramienta —el plugin del marco
    /// de trabajo lee el prompt y `flow start <título>` toma como título todo lo que va
    /// detrás—, así que añadirle una frase convertía la preferencia de idioma en el
    /// título de la tarea. Medido: un flow abierto llamado «(Si no se te pide otra cosa,
    /// responde en español.)».
    String? language,

    /// Cómo se llama quien contesta y cómo llamar a quien pregunta, ya compuesto
    /// para el prompt del sistema. Ver `LosNombres.paraElPrompt`.
    String? nombres,
  });
}

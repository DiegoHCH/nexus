import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';

/// Lanza `claude -p` headless y entrega cada línea de su `stream-json` ya
/// decodificada. No sabe nada de dominio: eso lo traduce el repositorio.
class ClaudeCliDataSource {
  const ClaudeCliDataSource();

  /// [workingDirectory] es dónde trabaja Claude, y no es opcional de verdad:
  /// sin él el proceso hereda el directorio de la app, que para un bundle
  /// lanzado por launchd es `/`. Cualquier encargo sobre archivos respondía
  /// entonces sobre la raíz del disco, con seguridad y sin avisar.
  ///
  /// [permissionMode] es el `--permission-mode` del CLI. Con `manual` la
  /// escritura se deniega, también la que intente colarse por Bash.
  /// [extraDirectories] son las demás carpetas emparejadas. Sin ellas, Claude
  /// solo alcanza el directorio de trabajo: un repo que guarda sus reglas en
  /// una carpeta hermana —lo normal en un monorepo de contexto compartido—
  /// carga las instrucciones y luego no puede leer lo que estas le mandan.
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
    final process = await Process.start(
      'claude',
      [
        '-p',
        instruction,
        '--output-format',
        'stream-json',
        '--include-partial-messages',
        '--verbose',
        '--permission-mode',
        permissionMode,
        // Con esto Claude recuerda lo de antes; sin esto, cada encargo empieza
        // de cero y no sabe ni lo que hizo hace un minuto.
        if (resumeSessionId != null) ...['--resume', resumeSessionId],
        // Las reglas del árbol y el contexto del repo, repetidos aquí a
        // propósito. Claude ya carga los CLAUDE.md por su cuenta, pero los
        // aplica todos al mismo nivel: sin esto, el protocolo de la carpeta de
        // arriba diluye las reglas del proyecto.
        if (appendSystemPrompt != null && appendSystemPrompt.isNotEmpty) ...[
          '--append-system-prompt',
          appendSystemPrompt,
        ],
        // Al final y de una sola vez: el flag es variádico, así que cualquier
        // argumento que fuera detrás se lo tragaría como si fuera una carpeta.
        if (extraDirectories.isNotEmpty) ...['--add-dir', ...extraDirectories],
      ],
      workingDirectory: workingDirectory,
      environment: ClaudeEnvironment.forProfile(configDir),
      includeParentEnvironment: false,
    );
    // Sin esto, claude espera ~3s por si le llega algo por stdin antes de
    // arrancar — nadie le va a escribir nada, así que se lo avisamos ya.
    unawaited(process.stdin.close());

    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();

    try {
      final lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) yield decoded;
      }

      await stderrDone;
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw ClaudeProcessException(exitCode, stderrBuffer.toString().trim());
      }
    } finally {
      // Si quien escuchaba se fue antes de que el proceso terminara —la
      // conversación se cerró, el encargo se canceló— hay que matarlo. Un
      // `claude -p` abandonado no se entera: sigue trabajando, gastando
      // contexto y tiempo para una respuesta que nadie va a leer. Este
      // `finally` también corre al cancelar la suscripción, que es justo el
      // caso que importa. Si el proceso ya salió, `kill` no hace nada.
      process.kill();
    }
  }

  /// Una app de GUI no hereda el PATH del shell de login ni puede confiar en
  /// que `CLAUDE_CONFIG_DIR` venga seteado igual en cada lanzamiento: se
  /// parte del entorno completo del proceso (HOME, USER, etc.) y se fuerza
  /// lo que el bridge necesita, en vez de dejarlo a lo que herede.
}

class ClaudeProcessException implements Exception {
  const ClaudeProcessException(this.exitCode, this.stderr);

  final int exitCode;
  final String stderr;

  @override
  String toString() => 'claude terminó con código $exitCode: $stderr';
}

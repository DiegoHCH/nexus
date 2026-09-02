import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Lanza `claude -p` headless y entrega cada línea de su `stream-json` ya
/// decodificada. No sabe nada de dominio: eso lo traduce el repositorio.
class ClaudeCliDataSource {
  const ClaudeCliDataSource();

  /// Un evento del flujo, o `null` si esa línea no lo es.
  ///
  /// Público **para poder probar la tolerancia sin lanzar un proceso**, que es
  /// justo la parte que falló: antes esto era un `jsonDecode` a pelo, y una
  /// línea de texto plano —las que el CLI escribe cuando algo va mal antes de
  /// arrancar el flujo— se llevaba por delante el encargo entero con una
  /// `FormatException`.
  static Map<String, dynamic>? comoJson(String line) {
    try {
      final decoded = jsonDecode(line);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

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
    List<String> disallowedTools = const [],

    /// Los servidores MCP que este encargo puede usar, ya con el prefijo `mcp__`.
    /// Vacío significa **ninguno**, que es lo que había antes sin querer.
    List<String> herramientasMcp = const [],

    /// A quién preguntarle cuando Claude quiera usar una herramienta que no
    /// tiene concedida. `null` —lo de siempre— deja el encargo headless puro:
    /// no hay canal de vuelta y el modo de permisos decide solo.
    ///
    /// **No es un adorno opcional: cambia cómo se lanza el proceso.** Con esto
    /// puesto la instrucción deja de ir en la línea de comandos y entra por
    /// stdin como `stream-json`, porque el canal de las preguntas es el mismo
    /// que el de la entrada y solo existe si esa entrada está abierta.
    Future<RespuestaDePermiso> Function(PeticionDePermiso peticion)?
    alPedirPermiso,
  }) async* {
    // Con alguien a quien preguntar, el CLI habla por un canal distinto: manda
    // `control_request` por stdout y espera el `control_response` por stdin.
    // Lo enciende `--permission-prompt-tool stdio` —el valor es literal, lo
    // dice el binario: «permission prompts reach the host over stdio»— y sin
    // `--input-format stream-json` no hay por dónde contestarle.
    final preguntando = alPedirPermiso != null;
    final process = await Process.start(
      await HerramientaExterna.rutaDeClaude(),
      [
        '-p',
        // Preguntando, la instrucción viaja por stdin: pasarla además aquí la
        // mandaría dos veces.
        if (!preguntando) instruction,
        if (preguntando) ...[
          '--input-format',
          'stream-json',
          '--permission-prompt-tool',
          'stdio',
        ],
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
        // **El modelo y el esfuerzo de la carpeta.** Se calculaban, se pasaban por
        // tres capas y se tiraban aquí: llegaban a este método y nunca a la línea de
        // comandos, así que la elección por carpeta no hacía nada.
        if (model != null && model.isNotEmpty) ...['--model', model],
        if (effort != null && effort.isNotEmpty) ...['--effort', effort],
        // **Las herramientas MCP, permitidas por servidor.**
        //
        // En headless nadie aprueba nada, así que sin esto toda llamada a un servidor
        // MCP se deniega sola: se preguntaba «¿qué reuniones tengo hoy?» y contestaba
        // que no podía consultar el calendario, con el conector conectado y sano. Y no
        // lo arregla el modo de permisos — con `acceptEdits` falla igual.
        //
        // Por servidor y no por herramienta porque enumerar las de lectura de cada
        // conector sería una lista que caduca con cada versión suya. Lo que no vale es
        // el comodín: `mcp__*` no autoriza nada, probado contra el CLI real.
        if (herramientasMcp.isNotEmpty) ...[
          '--allowedTools',
          ...herramientasMcp,
        ],
        // **Lo que no puede tocar.** Aquí van los comandos bloqueados de la carpeta y,
        // cuando es de solo lectura, las herramientas MCP que actúan fuera de la
        // máquina. La denegación gana al permiso, medido, así que permitir el servidor
        // entero y negar estas es seguro.
        if (disallowedTools.isNotEmpty) ...[
          '--disallowedTools',
          ...disallowedTools,
        ],
        // Al final y de una sola vez: el flag es variádico, así que cualquier
        // argumento que fuera detrás se lo tragaría como si fuera una carpeta.
        if (extraDirectories.isNotEmpty) ...['--add-dir', ...extraDirectories],
      ],
      workingDirectory: workingDirectory,
      environment: ClaudeEnvironment.forProfile(configDir),
      includeParentEnvironment: false,
    );
    // **Qué manos lleva este encargo, dicho una vez.**
    //
    // Se anota porque su ausencia costó una tarde: «no puedo consultar tu calendario»
    // con el conector conectado y sano no se parece a un problema de permisos, y desde
    // fuera no había forma de ver que el CLI arrancaba sin autorizar ninguna
    // herramienta. Una línea por encargo, no por herramienta: es una decisión y no un
    // caudal.
    debugPrint(
      'claude · perfil ${configDir ?? 'el de siempre'} · '
      // **Si hay alguien a quien preguntar, dicho en la misma línea.**
      //
      // Se anota por lo mismo que las herramientas de aquí al lado, y con un
      // caso propio ya vivido: se probó un encargo esperando el diálogo, no
      // salió, y desde fuera no había forma de distinguir «el canal no se
      // armó» de «el CLI no preguntó nada». Resolverlo costó media hora y
      // acabó siendo que el binario ni siquiera llevaba el cambio. Una línea
      // por encargo lo contesta antes de empezar a buscar.
      '${preguntando ? 'preguntando lo que no tenga concedido' : 'sin nadie a quien preguntar'} · '
      'modo $permissionMode · '
      '${herramientasMcp.length} servidores MCP permitidos'
      '${disallowedTools.isEmpty ? '' : ' · ${disallowedTools.length} herramientas negadas'}'
      '${model == null ? '' : ' · $model'}'
      '${effort == null ? '' : ' · esfuerzo $effort'}',
    );

    if (preguntando) {
      // La instrucción, ahora como mensaje del protocolo. **Y el stdin se queda
      // abierto**, al revés que en el camino de siempre: por ahí van las
      // respuestas a los permisos, y cerrarlo deja al CLI preguntando a una
      // puerta tapiada. Lo mismo hace `CorridaViva` con `flutter run --machine`.
      process.stdin.writeln(
        jsonEncode({
          'type': 'user',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': instruction},
            ],
          },
        }),
      );
    } else {
      // Sin esto, claude espera ~3s por si le llega algo por stdin antes de
      // arrancar — nadie le va a escribir nada, así que se lo avisamos ya.
      unawaited(process.stdin.close());
    }

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
        final decoded = ClaudeCliDataSource.comoJson(line);
        // **Una línea que no es JSON no es el final del encargo.** Antes
        // `jsonDecode` reventaba con ella y se llevaba por delante la petición
        // entera —y encima disparaba el reintento sin memoria, que volvía a
        // chocar con lo mismo—. El CLI escribe texto plano cuando algo va mal
        // antes de arrancar el flujo; ahí es justo cuando hace falta leerlo.
        //
        // Va al mismo sitio que stderr porque acaba en el mismo mensaje: es lo
        // que el proceso tenía que decir antes de morir.
        if (decoded == null) {
          stderrBuffer.writeln(line);
          continue;
        }
        // Las preguntas de permiso no son eventos del encargo: no las ve el
        // dominio, se contestan aquí y el turno sigue como si nada.
        if (alPedirPermiso != null) {
          if (peticionDe(decoded) case final peticion?) {
            // **Sin `await`, y esto es lo importante.** Esperar aquí la
            // respuesta pararía de leer stdout mientras la persona mira el
            // diálogo, y por ahí siguen llegando los deltas del texto. La
            // pregunta se lanza y el bucle sigue; quien conteste escribe por
            // stdin cuando toque.
            unawaited(_contestar(process, peticion, alPedirPermiso));
            continue;
          }
        }
        yield decoded;
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
      //
      // Y el stdin que dejamos abierto se cierra aquí: es nuestro, y un
      // descriptor suelto por encargo se acumula.
      if (preguntando) unawaited(process.stdin.close().catchError((_) {}));
      process.kill();
    }
  }

  /// La petición de permiso que trae esta línea, o `null` si no es una.
  ///
  /// El CLI manda por el mismo canal otros `control_request` que no son
  /// preguntas para nadie —`request_user_dialog`, por ejemplo—, así que no
  /// vale con mirar el tipo: hay que mirar el `subtype`.
  ///
  /// Pública por el mismo motivo que [comoJson]: **para poder probarla sin
  /// lanzar un proceso**. Es la única forma de fijar contra qué JSON se
  /// programó, y aquí eso pesa más que de costumbre — el protocolo de control
  /// no está documentado, así que lo que hay es lo medido contra el binario y
  /// conviene que quede escrito en algún sitio que se ejecute.
  static PeticionDePermiso? peticionDe(Map<String, dynamic> json) {
    if (json['type'] != 'control_request') return null;
    final request = json['request'];
    if (request is! Map<String, dynamic>) return null;
    if (request['subtype'] != 'can_use_tool') return null;

    final id = json['request_id'];
    final herramienta = request['tool_name'];
    if (id is! String || herramienta is! String) return null;

    final entrada = request['input'];
    final nombreVisible = request['display_name'];
    final descripcion = request['description'];
    final toolUseId = request['tool_use_id'];
    final sugerencias = request['permission_suggestions'];
    return PeticionDePermiso(
      id: id,
      herramienta: herramienta,
      nombreVisible: nombreVisible is String && nombreVisible.isNotEmpty
          ? nombreVisible
          : herramienta,
      entrada: entrada is Map<String, dynamic> ? entrada : const {},
      descripcion: descripcion is String ? descripcion : null,
      toolUseId: toolUseId is String ? toolUseId : null,
      sugerencias: sugerencias is List
          ? [
              for (final una in sugerencias)
                if (una is Map<String, dynamic>) una,
            ]
          : const [],
    );
  }

  /// Pregunta y escribe la respuesta por stdin.
  ///
  /// **Un fallo aquí se convierte en una negación, nunca en silencio.** Si el
  /// diálogo revienta o quien tenía que contestar ya no está, el CLI se queda
  /// esperando para siempre una respuesta que no va a llegar y el turno cuelga
  /// sin decir por qué. Denegar al menos deja al modelo seguir y contarlo.
  static Future<void> _contestar(
    Process process,
    PeticionDePermiso peticion,
    Future<RespuestaDePermiso> Function(PeticionDePermiso) preguntar,
  ) async {
    RespuestaDePermiso respuesta;
    try {
      respuesta = await preguntar(peticion);
    } on Object catch (error) {
      debugPrint(
        'claude · el permiso de ${peticion.herramienta} falló: $error',
      );
      respuesta = const PermisoDenegado('Nexus no pudo preguntar.');
    }

    final cuerpo = switch (respuesta) {
      PermisoConcedido(:final entrada, :final permisosNuevos) => {
        'behavior': 'allow',
        'updatedInput': entrada,
        // Solo cuando hay algo que cambiar: mandar la lista vacía sería pedirle
        // al CLI que toque los permisos para no tocar ninguno.
        if (permisosNuevos.isNotEmpty) 'updatedPermissions': permisosNuevos,
      },
      PermisoDenegado(:final motivo) => {'behavior': 'deny', 'message': motivo},
    };
    try {
      process.stdin.writeln(
        jsonEncode({
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': peticion.id,
            'response': cuerpo,
          },
        }),
      );
    } on Object catch (error) {
      // El proceso ya no está: el encargo se canceló mientras el diálogo
      // estaba abierto. No hay nada que arreglar y nadie a quien avisar.
      debugPrint('claude · no se pudo contestar el permiso: $error');
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

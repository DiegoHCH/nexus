import 'dart:io';

/// El entorno con el que se lanza cualquier cosa de Claude Code.
///
/// Vive aparte porque ya lo necesitan dos sitios —los encargos y la gestión de
/// superpoderes— y las tres reglas de aquí no son cosméticas: equivocarse en la
/// cuenta hace el trabajo con el perfil que no es, y equivocarse en el `PATH`
/// hace que no arranque nada.
abstract final class ClaudeEnvironment {
  /// Donde suele estar el binario cuando el `PATH` de una app de escritorio no
  /// trae lo que trae una shell de verdad.
  static const _extraPathDirs = ['/opt/homebrew/bin', '/usr/local/bin'];

  /// El entorno para lanzar **cualquier** binario, sin nada de Claude dentro.
  ///
  /// Existe aparte porque la trampa del PATH no es de `claude`, es de lanzar
  /// procesos desde una app de GUI: lo mismo le pasa a `git`. Y a `git` un
  /// `CLAUDE_CONFIG_DIR` no le dice nada, así que meterlo sería ruido con
  /// aspecto de intención.
  ///
  /// `security` y demás binarios de `/usr/bin` no lo necesitan —ese directorio
  /// sí está en el PATH por defecto de una app— pero tampoco les estorba.
  static Map<String, String> forTools() {
    final env = Map<String, String>.from(Platform.environment);
    final home = env['HOME'] ?? '';

    final extraPaths = [
      ..._extraPathDirs,
      if (home.isNotEmpty) '$home/.local/bin',
      // **Maestro, y por qué necesita línea propia.** Su instalador deja el
      // binario en `~/.maestro/bin` y añade ese directorio **editando el perfil
      // de la shell**, que es justo lo que una app de escritorio no lee. O sea
      // que en una terminal `maestro` está y aquí no, y el servidor MCP que lo
      // llama se registraría bien para fallar al arrancarlo.
      //
      // Va detrás de Homebrew a propósito: quien lo instaló por el tap tiene el
      // binario en `/opt/homebrew/bin`, y ahí el que gana debe ser el que puso a
      // propósito, igual que con `claude` y `git`.
      if (home.isNotEmpty) '$home/.maestro/bin',
    ];
    final currentPath = env['PATH'] ?? '';
    env['PATH'] = [
      ...extraPaths,
      currentPath,
    ].where((path) => path.isNotEmpty).join(':');

    return env;
  }

  static Map<String, String> forProfile(String? configDir) {
    final env = forTools();

    // Fuera del entorno: claude factura por la suscripción, no por API key.
    env.remove('ANTHROPIC_API_KEY');
    env.remove('ANTHROPIC_AUTH_TOKEN');

    // El perfil es de la carpeta: los repos del trabajo con la cuenta del
    // trabajo, los personales con la personal.
    //
    // 🔴 **Y sin perfil no se pone nada.** Aquí había un
    // `env['CLAUDE_CONFIG_DIR'] ??= '$home/.claude'` «en último caso, el de
    // fábrica», y era exactamente lo contrario de lo que pretendía: nombrar el
    // directorio por defecto **cambia de dónde lee las credenciales**.
    //
    // Claude Code guarda el token en el llavero, y el nombre de la entrada
    // depende de si la variable está puesta —lo dice el comentario de
    // `ClaudeProfilesDataSource.keychainService`: «el del directorio por defecto
    // no lleva sufijo»—. Medido en esta máquina:
    //
    //     sin la variable   → «Claude Code-credentials»
    //     con la variable   → «Claude Code-credentials-<sha256(ruta)[:8]>»
    //
    // Son dos almacenes distintos **aunque la ruta sea la misma**. Así que poner
    // la variable convertía «usa la cuenta de siempre» en «usa un perfil con
    // nombre que resulta apuntar al mismo sitio», y ese perfil no tiene la
    // sesión que la persona inició en su terminal.
    //
    // Le pasó a la primera persona ajena que instaló Nexus: la app le decía
    // «ninguna cuenta tiene sesión abierta» mientras `claude auth status --json`
    // contestaba `loggedIn: true` en su terminal. Y aquí no se vio porque esta
    // shell **exporta** `CLAUDE_CONFIG_DIR`, así que el `??=` nunca aplicaba el
    // valor por defecto: el bug solo existía para quien no la exporta, o sea
    // para todos menos para quien lo escribió.
    //
    // Lo que sigue en pie: si el entorno trae la variable, se respeta —lanzar
    // desde una shell con el alias exportado sigue funcionando—. Lo que se quita
    // es **inventarla** cuando nadie la ha puesto.
    if (configDir != null && configDir.isNotEmpty) {
      env['CLAUDE_CONFIG_DIR'] = configDir;
    }

    return env;
  }
}

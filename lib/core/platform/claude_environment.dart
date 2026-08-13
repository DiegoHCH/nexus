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

  static Map<String, String> forProfile(String? configDir) {
    final env = Map<String, String>.from(Platform.environment);

    // Fuera del entorno: claude factura por la suscripción, no por API key.
    env.remove('ANTHROPIC_API_KEY');
    env.remove('ANTHROPIC_AUTH_TOKEN');

    final home = env['HOME'] ?? '';
    // El perfil es de la carpeta: los repos del trabajo con la cuenta del
    // trabajo, los personales con la personal. Si no se dice nada se respeta lo
    // que traiga el entorno —lanzar desde una shell con el alias exportado
    // sigue funcionando— y en último caso, el de fábrica.
    if (configDir != null && configDir.isNotEmpty) {
      env['CLAUDE_CONFIG_DIR'] = configDir;
    } else {
      env['CLAUDE_CONFIG_DIR'] ??= '$home/.claude';
    }

    final extraPaths = [
      ..._extraPathDirs,
      if (home.isNotEmpty) '$home/.local/bin',
    ];
    final currentPath = env['PATH'] ?? '';
    env['PATH'] = [
      ...extraPaths,
      currentPath,
    ].where((path) => path.isNotEmpty).join(':');

    return env;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Una cuenta de Claude Code en esta máquina.
///
/// Claude Code guarda su configuración —y su sesión— en un directorio, y
/// apuntando `CLAUDE_CONFIG_DIR` a otro se trabaja con otra cuenta. Es el
/// mecanismo que ya usa quien tiene el trabajo y lo personal separados:
/// `~/.claude-work` y `~/.claude-private`.
class ClaudeProfile {
  const ClaudeProfile({
    required this.path,
    required this.name,
    required this.signedIn,
  });

  final String path;

  /// Lo que se lee en la interfaz: `.claude-work` → «work», y el de siempre
  /// como «por defecto».
  final String name;

  /// Si esa cuenta tiene sesión iniciada. Sin esto, elegir un perfil sin
  /// sesión deja el encargo fallando con un error del CLI que no dice qué
  /// hacer; enseñarlo aquí convierte un fallo en una elección informada.
  final bool signedIn;
}

/// Encuentra las cuentas de Claude que hay en el Mac.
class ClaudeProfilesDataSource {
  const ClaudeProfilesDataSource();

  /// Claude Code guarda el token de cada perfil en el llavero, con el servicio
  /// `Claude Code-credentials-<sha256(directorio)[:8]>`. Comprobar que esa
  /// entrada existe es la única forma de saber si el perfil tiene sesión sin
  /// arrancar el binario — y el del directorio por defecto no lleva sufijo.
  static String keychainService(String configDir) {
    final hash = sha256.convert(utf8.encode(configDir)).toString();
    return 'Claude Code-credentials-${hash.substring(0, 8)}';
  }

  Future<List<ClaudeProfile>> list() async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return const [];

    final profiles = <ClaudeProfile>[];
    await for (final entity in Directory(home).list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      // Solo `.claude-*`: en el home hay muchas carpetas ocultas y ninguna
      // otra es una cuenta de Claude.
      //
      // `.claude` a secas **no se lista**, y no por descuido: es justo lo que
      // significa «cuenta por defecto», la opción que ya está arriba. Cuando
      // salía también aquí, la misma cuenta aparecía dos veces con dos nombres
      // distintos y no había forma de saber en qué se diferenciaban.
      if (!name.startsWith('.claude-')) continue;
      profiles.add(
        ClaudeProfile(
          path: entity.path,
          name: name.substring(8),
          signedIn: await _hasSession(entity.path),
        ),
      );
    }

    profiles.sort((a, b) => a.name.compareTo(b.name));
    return profiles;
  }

  Future<bool> _hasSession(String configDir) async {
    final result = await Process.run('security', [
      'find-generic-password',
      '-s',
      keychainService(configDir),
    ]);
    return result.exitCode == 0;
  }
}

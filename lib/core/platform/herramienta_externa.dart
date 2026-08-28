import 'dart:io';

import 'package:nexus/core/platform/binario_en_el_path.dart';
import 'package:nexus/core/platform/claude_environment.dart';

/// Encontrar un binario del sistema que la app necesita lanzar.
///
/// **Existe porque el PATH de una app de escritorio no es el de tu terminal**, y
/// esto ya se pagó una vez con Maestro: su instalador añade `~/.maestro/bin`
/// editando el `.zshrc`, que una app lanzada por launchd no lee. Con `flutter`
/// pasa lo mismo y peor, porque no hay un sitio canónico: en esta máquina está
/// en `~/development/flutter/bin` —el de la guía oficial—, en otra estará en
/// Homebrew, y en un repo con fvm el bueno es el del proyecto.
///
/// El orden es el que menos sorpresas da:
///
/// 1. **El PATH** que ya monta [ClaudeEnvironment.forTools], porque si está ahí
///    es que alguien lo puso a propósito.
/// 2. **Los sitios de siempre**, que cubren una instalación normal sin preguntar
///    nada a nadie.
/// 3. **El shell de login**, como último recurso. Es lo único que ve un PATH
///    montado a mano en un `.zshrc`, y cuesta un proceso — así que va al final y
///    no al principio.
abstract final class HerramientaExterna {
  /// Donde suele estar Flutter cuando el PATH de la app no lo trae.
  ///
  /// `development/flutter` primero porque es lo que dice la guía oficial de
  /// instalación y es donde acaba la mayoría —incluida esta máquina—. Homebrew
  /// después: quien lo instaló así lo tiene en un PATH que sí heredamos, así que
  /// llegar aquí ya es raro.
  static List<String> candidatosDeFlutter(String home) => [
    if (home.isNotEmpty) ...[
      '$home/development/flutter/bin/flutter',
      '$home/flutter/bin/flutter',
      // fvm sin proyecto: su enlace «default».
      '$home/fvm/default/bin/flutter',
      '$home/.puro/envs/default/flutter/bin/flutter',
    ],
    '/opt/homebrew/bin/flutter',
    '/usr/local/bin/flutter',
  ];

  /// Donde deja `adb` el SDK de Android.
  ///
  /// Hace falta aparte de Flutter y no se puede evitar: `flutter emulators` da el
  /// catálogo pero **no dice cuál está arriba**, y eso solo lo sabe `adb`.
  static List<String> candidatosDeAdb(String home) => [
    if (home.isNotEmpty) ...[
      '$home/Library/Android/sdk/platform-tools/adb',
      '$home/Android/Sdk/platform-tools/adb',
    ],
    '/opt/homebrew/bin/adb',
    '/usr/local/bin/adb',
  ];

  /// Donde deja Maestro su binario.
  ///
  /// Su instalador lo pone en `~/.maestro/bin` y añade ese directorio **editando
  /// el perfil de la shell**, que una app de escritorio no lee — ya está en el
  /// PATH que monta [ClaudeEnvironment.forTools], pero quien lo instaló por el
  /// tap de Homebrew lo tiene en otro sitio.
  /// Donde lo deja Homebrew. No hay instalador propio que edite el perfil, así que
  /// con los dos prefijos de brew está cubierto.
  static List<String> candidatosDeScrcpy(String home) => [
    '/opt/homebrew/bin/scrcpy',
    '/usr/local/bin/scrcpy',
    if (home.isNotEmpty) '$home/.local/bin/scrcpy',
  ];

  static List<String> candidatosDeMaestro(String home) => [
    if (home.isNotEmpty) '$home/.maestro/bin/maestro',
    '/opt/homebrew/bin/maestro',
    '/usr/local/bin/maestro',
  ];

  /// Donde deja Homebrew el CLI de GitHub. No hay instalador propio que edite el
  /// perfil, así que con los dos prefijos de brew está cubierto.
  static List<String> candidatosDeGh() => const [
    '/opt/homebrew/bin/gh',
    '/usr/local/bin/gh',
  ];

  /// git viene con las herramientas de línea de comandos de Xcode y siempre está
  /// en el mismo sitio. Se listan igual por si alguien usa el de Homebrew, que es
  /// más nuevo y va antes en su PATH.
  static List<String> candidatosDeGit() => const [
    '/opt/homebrew/bin/git',
    '/usr/local/bin/git',
    '/usr/bin/git',
  ];

  /// La ruta del binario, o `null` si no está en ningún sitio conocido.
  ///
  /// [existe] y [preguntaAlShell] entran como parámetros para poder probar el
  /// **orden** sin tocar el disco ni lanzar procesos, que es lo único que puede
  /// romperse al editar aquí.
  static Future<String?> donde(
    String nombre, {
    required List<String> candidatos,
    bool Function(String ruta)? existe,
    Future<String?> Function(String nombre)? preguntaAlShell,
    String? path,
  }) async {
    final hay = existe ?? (ruta) => File(ruta).existsSync();

    final enElPath = BinarioEnElPath.resolver(
      nombre,
      path: path ?? ClaudeEnvironment.forTools()['PATH'] ?? '',
      existe: hay,
    );
    if (enElPath != null) return enElPath;

    for (final candidato in candidatos) {
      if (hay(candidato)) return candidato;
    }

    return (preguntaAlShell ?? _alShellDeLogin)(nombre);
  }

  /// `zsh -lc 'command -v flutter'`.
  ///
  /// `-l` es la parte que importa: sin él no se leen los archivos de perfil, que
  /// es justo donde vive el PATH que esta función viene a rescatar. Y se acepta
  /// el `SHELL` del usuario porque quien usa fish o bash tiene su PATH en otro
  /// archivo.
  static Future<String?> _alShellDeLogin(String nombre) async {
    // El nombre lo pone esta clase, no el usuario, pero se comprueba igual: va a
    // una línea de comandos y un día alguien lo llamará con algo de fuera.
    if (!RegExp(r'^[\w.-]{1,40}$').hasMatch(nombre)) return null;

    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    try {
      final resultado = await Process.run(
        shell,
        ['-lc', 'command -v $nombre'],
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      );
      if (resultado.exitCode != 0) return null;
      final ruta = '${resultado.stdout}'.trim().split('\n').first.trim();
      return ruta.isNotEmpty && File(ruta).existsSync() ? ruta : null;
    } on ProcessException {
      return null;
    }
  }
}

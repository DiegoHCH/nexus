import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// Donde vive el CLI de Claude.
  ///
  /// Su instalador lo deja en `~/.local/bin` —ahí está en esta máquina— y añade
  /// ese directorio editando el perfil de la shell, que una app de escritorio no
  /// lee. Los dos prefijos de Homebrew detrás, y el `local/` que usa la
  /// instalación gestionada por el propio Claude Code.
  /// Con qué se invoca al shell del usuario para que declare su entorno.
  ///
  /// 🔴 **La `-i` no es decorativa, y van sueltas y no pegadas.**
  ///
  /// `-l` es login pero no interactivo, y zsh solo lee `.zshrc` en shells
  /// interactivos — que es justo donde se configuran fnm, nvm y volta. Sin la
  /// `-i`, este rescate era ciego para los tres gestores de Node que usa
  /// cualquier dev de front: Claude instalado con npm quedaba invisible y la app
  /// decía «no está instalado» a alguien que lo tenía funcionando en su terminal.
  /// Medido con un ZDOTDIR de prueba.
  ///
  /// Y sueltas porque **aquí no todo el mundo usa zsh**. Combinar cortas en un
  /// `-lic` es una costumbre de bash y zsh, no una garantía: pasarlas una a una
  /// es lo que entienden los tres por igual.
  static const banderasDelShell = ['-l', '-i', '-c'];

  /// Las carpetas que el shell declaró, en el formato que [BinarioEnElPath]
  /// espera.
  ///
  /// 🔴 **fish imprime el PATH separado por espacios**, no por dos puntos: para
  /// él es una lista y no una cadena. Se parte por los dos separadores, que
  /// además no colisionan — una ruta con espacios dentro es lo bastante rara
  /// como para no pagar por ella el no funcionar en fish.
  static String carpetasDelPath(String salida) => [
    for (final trozo in salida.trim().split(RegExp(r'[:\s]+')))
      if (trozo.isNotEmpty) trozo,
  ].join(':');

  static List<String> candidatosDeClaude(String home) => [
    if (home.isNotEmpty) ...[
      '$home/.local/bin/claude',
      '$home/.claude/local/claude',
      // **Volta**, que sí tiene un sitio fijo: sus shims no dependen de la
      // versión de Node activa, así que basta con nombrarlo.
      '$home/.volta/bin/claude',
    ],
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
    // **fnm y nvm** no caben en una lista fija: guardan los binarios *dentro de
    // cada versión de Node*, así que la ruta lleva un número que cambia al
    // actualizar. Se buscan aparte, mirando qué versiones hay. Ver
    // [enLosGestoresDeNode].
  ];

  /// Donde fnm y nvm dejan lo que se instaló con npm.
  ///
  /// 🔴 **Esto existe porque el squad es de front.** Node con un gestor de
  /// versiones no es un caso raro ahí, es lo normal, y `claude` instalado con
  /// npm acaba dentro de la versión que estuviera activa — nunca en un sitio
  /// fijo. La ruta que devuelve fnm en el PATH ni siquiera sirve para guardarla:
  /// `fnm_multishells/<pid>_<hora>/` la crea por cada terminal y desaparece al
  /// cerrarla. Lo estable es la carpeta de la versión, y es la que se busca.
  ///
  /// Se ordenan al revés para que gane la versión más nueva cuando hay varias,
  /// que es la que el usuario tiene activa casi siempre.
  static List<String> enLosGestoresDeNode(String home, String nombre) {
    if (home.isEmpty) return const [];
    final rutas = <String>[];
    for (final raiz in [
      Directory('$home/.local/share/fnm/node-versions'),
      Directory('$home/Library/Application Support/fnm/node-versions'),
      Directory('$home/.nvm/versions/node'),
    ]) {
      if (!raiz.existsSync()) continue;
      final versiones = [
        for (final v in raiz.listSync())
          if (v is Directory) v.path,
      ]..sort();
      for (final version in versiones.reversed) {
        // fnm mete otro nivel —`installation/`— y nvm no.
        rutas
          ..add('$version/installation/bin/$nombre')
          ..add('$version/bin/$nombre');
      }
    }
    return rutas;
  }

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

  /// La ruta absoluta de una herramienta, resuelta **una vez** y recordada.
  ///
  /// Lanzar por nombre —`Process.start('git', …)`— deja que el sistema resuelva
  /// el `PATH` en **cada** arranque, y ese `PATH` antepone `/opt/homebrew/bin` y
  /// `/usr/local/bin`, que en un Mac con Homebrew los escribe el usuario sin
  /// pedir contraseña. Cualquier proceso suyo —incluido un encargo anterior que
  /// salió mal— puede dejar ahí un `git` falso.
  ///
  /// Anteponerlos sigue siendo lo correcto: una app de GUI no hereda el `PATH`
  /// de la shell, y sin eso no arranca nada. Lo que faltaba es que la
  /// **preferencia sea consciente**: se decide una vez, se anota cuál salió, y a
  /// partir de ahí se lanza por ruta absoluta.
  ///
  /// Si no se encuentra en ningún sitio se devuelve el nombre a secas. Es a
  /// propósito: entonces falla exactamente como fallaba antes, con su
  /// `ProcessException`, en vez de estrenar una forma nueva de romperse.
  static Future<String> ruta(
    String nombre, {
    required List<String> candidatos,
    bool Function(String ruta)? existe,
    Future<String?> Function(String nombre)? preguntaAlShell,
    String? path,
  }) async {
    final ya = _resueltas[nombre];
    if (ya != null) return ya;

    final encontrada =
        await donde(
          nombre,
          candidatos: candidatos,
          existe: existe,
          preguntaAlShell: preguntaAlShell,
          path: path,
        ) ??
        nombre;
    _resueltas[nombre] = encontrada;
    // Qué binario se eligió, dicho una vez. Es la mitad de «consciente»: sin
    // esto, saber cuál de los tres `git` de la máquina está corriendo pide
    // reproducir el `PATH` a mano.
    debugPrint('herramienta · $nombre → $encontrada');
    return encontrada;
  }

  static final _resueltas = <String, String>{};

  /// Olvida lo resuelto. Solo para las pruebas: la caché es de por vida y dos
  /// pruebas seguidas se contaminarían.
  @visibleForTesting
  static void olvidar() => _resueltas.clear();

  /// El `claude` de esta máquina, por ruta absoluta.
  static Future<String> rutaDeClaude() {
    final home = Platform.environment['HOME'] ?? '';
    return ruta(
      'claude',
      candidatos: [
        ...candidatosDeClaude(home),
        ...enLosGestoresDeNode(home, 'claude'),
      ],
    );
  }

  /// El `git` de esta máquina, por ruta absoluta.
  static Future<String> rutaDeGit() =>
      ruta('git', candidatos: candidatosDeGit());

  /// `$SHELL -l -i -c 'echo $PATH'`, y luego se resuelve aquí.
  ///
  /// 🔴 **Este comentario decía otra cosa, y la diferencia costó una instalación
  /// fallida.** Decía «`zsh -lc 'command -v flutter'`» y que «`-l` es la parte
  /// que importa». Las dos mitades estaban mal:
  ///
  /// `-l` no basta. Es login pero **no interactivo**, y zsh solo lee `.zshrc` en
  /// shells interactivos — que es donde se configuran fnm, nvm y volta. Sin la
  /// `-i` esto era ciego para los tres gestores de Node.
  ///
  /// Y pedir `command -v` obliga a acertar con el builtin de cada shell. El
  /// comentario ya avisaba de que «quien usa fish o bash tiene su PATH en otro
  /// archivo» — se acordó del `SHELL` y no de que fish tampoco entiende las
  /// mismas opciones. Ahora se le pide **el PATH**, que es de las pocas cosas
  /// que los tres hacen igual, y la ruta la resuelve [BinarioEnElPath].
  ///
  /// Ver [banderasDelShell] y [carpetasDelPath].
  static Future<String?> _alShellDeLogin(String nombre) async {
    // El nombre lo pone esta clase, no el usuario, pero se comprueba igual: va a
    // una línea de comandos y un día alguien lo llamará con algo de fuera.
    if (!RegExp(r'^[\w.-]{1,40}$').hasMatch(nombre)) return null;

    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    try {
      // 🔴 **Se le pide el PATH, no que resuelva él.** Antes se le mandaba un
      // `command -v`, y eso obliga a acertar con el builtin de cada shell: fish
      // no acepta las mismas opciones que zsh en `command`, así que en su
      // máquina la pregunta fallaba sin decir por qué. Imprimir una variable es
      // de las pocas cosas que los tres hacen igual — y resolver la ruta ya lo
      // sabe hacer [BinarioEnElPath], que está probado.
      final resultado = await Process.run(
        shell,
        [...banderasDelShell, 'echo \$PATH'],
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      );
      if (resultado.exitCode != 0) return null;
      return BinarioEnElPath.resolver(
        nombre,
        path: carpetasDelPath('${resultado.stdout}'),
        existe: (ruta) => File(ruta).existsSync(),
      );
    } on ProcessException {
      return null;
    }
  }
}

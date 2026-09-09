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
    this.correo,
    this.organizacion,
  });

  final String path;

  /// Lo que se lee en la interfaz: `.claude-work` → «work», y el de siempre
  /// como «por defecto».
  final String name;

  /// Si esa cuenta tiene sesión iniciada. Sin esto, elegir un perfil sin
  /// sesión deja el encargo fallando con un error del CLI que no dice qué
  /// hacer; enseñarlo aquí convierte un fallo en una elección informada.
  final bool signedIn;

  /// Si es **la cuenta de siempre**, la que no tiene nombre.
  ///
  /// Quien la enseña le pone el nombre que toque en su idioma: aquí no hay
  /// textos de interfaz.
  bool get esLaDeSiempre => nameFromPath(path) == null;

  /// Con qué correo está iniciada la sesión de esa cuenta, si se sabe.
  ///
  /// 🔴 **Preguntado antes de ponerle nombre a nada:** «¿se puede saber con qué
  /// correo está logueada la cuenta?». Sí, y estaba a la vista: Claude Code lo
  /// guarda en el `.claude.json` de cada directorio, en `oauthAccount`. Con eso,
  /// una cuenta no necesita que nadie le invente un nombre — ya tiene el suyo, y
  /// es el que su dueño reconoce.
  ///
  /// Y contesta una pregunta que no se sabía hacer: en este Mac, `.claude` y
  /// `.claude-work` resultaron ser **la misma cuenta** —el mismo correo y la
  /// misma organización— y solo `.claude-private` era otra. Sin el correo, tres
  /// perfiles parecen tres cuentas.
  final String? correo;

  /// La organización de esa cuenta, tal como la escribe Claude Code —«Global66
  /// - Tech», o «alguien@gmail.com's Organization» en una cuenta personal—.
  ///
  /// Cruda a propósito: de aquí sale el nombre que se enseña, y esa derivación
  /// vive en [ElNombreDeLaCuenta] con sus reglas y sus pruebas. Guardar aquí lo
  /// ya masticado dejaría el dato original irrecuperable el día que la regla
  /// cambie.
  final String? organizacion;

  /// El nombre de cuenta que le corresponde a un directorio de configuración, o
  /// `null` si ese directorio no es una cuenta —`.claude` a secas, la de siempre—.
  ///
  /// Existe como función pura porque hay quien necesita el nombre **sin poder
  /// esperar** a que se listen las cuentas del disco: recorrer el home es asíncrono,
  /// y quien arranca un encargo lo hace en el mismo momento en que lo lanza. La
  /// derivación es la misma que usa [ClaudeProfilesDataSource.list], y vive aquí para
  /// que no haya dos.
  /// El directorio de la **cuenta de siempre**, la que no tiene nombre.
  ///
  /// Hace falta porque una carpeta sin perfil elegido trabaja con ella, y quien
  /// quiera mirar lo que esa cuenta tiene configurado —sus servidores MCP, por
  /// ejemplo— necesita un directorio que leer. No se lista en [list] a
  /// propósito: ahí solo van las cuentas con nombre.
  static String elDeSiempre() =>
      '${Platform.environment['HOME'] ?? ''}/.claude';

  static String? nameFromPath(String? configDir) {
    if (configDir == null || configDir.isEmpty) return null;
    final ultimo = configDir.split('/').where((p) => p.isNotEmpty).lastOrNull;
    if (ultimo == null || !ultimo.startsWith('.claude-')) return null;
    final nombre = ultimo.substring(8);
    return nombre.isEmpty ? null : nombre;
  }
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

  /// **Todos** los servicios donde puede estar la credencial de esa cuenta.
  ///
  /// 🔴 **Porque la de siempre puede guardarla sin sufijo.** Su entrada se
  /// llama «Claude Code-credentials» a secas —lo dice el comentario de arriba y
  /// se comprobó en el llavero de este Mac—, así que buscándola solo por el
  /// hash de su ruta la cuenta de siempre salía **sin sesión** aunque la
  /// tuviera. Y con las dos puestas también se cubre el caso al revés, que ya
  /// existe en esta máquina: las dos entradas a la vez.
  ///
  /// Vive aquí y no en cada quien porque **ya son dos** los que la necesitan
  /// —esto y el lector de consumo—, y una copia se separa de la otra en cuanto
  /// alguien toque una.
  static List<String> keychainServices(String configDir) => [
    keychainService(configDir),
    if (ClaudeProfile.nameFromPath(configDir) == null)
      'Claude Code-credentials',
  ];

  /// Lo que ese perfil tiene configurado: modelo y esfuerzo, si los fijó.
  ///
  /// Se lee de su `settings.json` para poder **enseñar el valor de verdad** en
  /// vez de un «el del CLI» que no dice nada: quien mira ese botón quiere saber
  /// con qué modelo va a trabajar, no que la app no ha decidido.
  Future<({String? model, String? effort})> defaults(String configDir) async {
    final file = File('$configDir/settings.json');
    if (!file.existsSync()) return (model: null, effort: null);
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return (model: null, effort: null);
      return (
        model: decoded['model'] as String?,
        effort: decoded['effort'] as String?,
      );
    } on FormatException {
      return (model: null, effort: null);
    }
  }

  /// Quién es esa cuenta: con qué correo entró y a qué organización pertenece.
  ///
  /// Se lee de su `.claude.json` —lo escribe Claude Code al entrar— y no del
  /// llavero: ahí está el token, no quién es. No lanza nunca: un archivo a
  /// medio escribir o de otra versión vale lo mismo que no saberlo.
  Future<({String? correo, String? organizacion})> datosDe(
    String configDir,
  ) async {
    const nada = (correo: null, organizacion: null);
    final file = File('$configDir/.claude.json');
    if (!file.existsSync()) return nada;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return nada;
      final cuenta = decoded['oauthAccount'];
      if (cuenta is! Map<String, dynamic>) return nada;
      final correo = cuenta['emailAddress'];
      final organizacion = cuenta['organizationName'];
      return (
        // Sin arroba no es un correo, y enseñarlo como si lo fuera es peor que
        // no saberlo.
        correo: correo is String && correo.contains('@') ? correo : null,
        organizacion: organizacion is String && organizacion.trim().isNotEmpty
            ? organizacion.trim()
            : null,
      );
    } on Object {
      return nada;
    }
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
      // Una sola lectura del archivo: son dos datos del mismo sitio.
      final quienEs = await datosDe(entity.path);
      profiles.add(
        ClaudeProfile(
          path: entity.path,
          name: ClaudeProfile.nameFromPath(entity.path) ?? name,
          signedIn: await _hasSession(entity.path),
          correo: quienEs.correo,
          organizacion: quienEs.organizacion,
        ),
      );
    }

    profiles.sort((a, b) => a.name.compareTo(b.name));
    return profiles;
  }

  /// Todas las cuentas **incluida la de siempre**, que va primero.
  ///
  /// 🔴 **Existe por un reporte con captura:** en un Mac con una sola cuenta
  /// —la de siempre, que es lo normal si nadie ha creado perfiles— Ajustes →
  /// Superpoderes decía «No hay ninguna cuenta de Claude configurada» y no
  /// dejaba ver ni poner nada, mientras el chat funcionaba perfectamente. Y era
  /// cierto desde su punto de vista: [list] devuelve solo las `.claude-*`,
  /// porque para elegir la cuenta de una carpeta «la de siempre» es la ausencia
  /// de perfil y ya está arriba como opción.
  ///
  /// Pero para **mirar qué tiene instalado una cuenta** eso no vale: la de
  /// siempre tiene sus servidores MCP, sus skills y sus plugins como cualquier
  /// otra, y sin listarla no había forma de verlos. Es el mismo caso que ya
  /// resolvió `cuentasParaLlaves` para las llaves, con el mismo motivo escrito.
  Future<List<ClaudeProfile>> todas() async {
    final siempre = ClaudeProfile.elDeSiempre();
    final quienEs = await datosDe(siempre);
    return [
      ClaudeProfile(
        path: siempre,
        // Sin nombre de directorio: el que se enseña sale de su organización.
        // Ver [ElNombreDeLaCuenta].
        name: '',
        signedIn: await _hasSession(siempre),
        correo: quienEs.correo,
        organizacion: quienEs.organizacion,
      ),
      ...await list(),
    ];
  }

  Future<bool> _hasSession(String configDir) async {
    for (final servicio in keychainServices(configDir)) {
      final result = await Process.run('security', [
        'find-generic-password',
        '-s',
        servicio,
      ]);
      if (result.exitCode == 0) return true;
    }
    return false;
  }
}

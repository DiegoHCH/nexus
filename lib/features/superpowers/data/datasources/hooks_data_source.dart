import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:nexus/features/superpowers/domain/entities/nexus_hook.dart';
import 'package:nexus/features/superpowers/domain/usecases/ajustes_con_ganchos.dart';

/// De dónde sale el script. Inyectable para poder probar la instalación entera sin
/// levantar el bundle de Flutter, que es lo que obligaría a un test de widgets para
/// comprobar cómo queda un archivo de texto.
typedef LeerElGancho = Future<String> Function(NexusHook gancho);

/// Pone y quita los ganchos de Nexus en una cuenta de Claude.
///
/// **Esto existe porque hasta ahora se hacía a mano.** Los dos ganchos que hay puestos
/// los copié yo a `~/.claude-work/nexus-hooks/` y registré yo sus entradas en el
/// `settings.json`: funcionan en una máquina, en un perfil, y nadie más los tiene. Un
/// mecanismo que solo existe donde se escribió no es un mecanismo, es una anécdota.
///
/// Son **dos mitades y las dos hacen falta**: el archivo en el disco y la entrada que lo
/// llama. Instalar las pone juntas; el estado sabe distinguir cuando solo hay una, que es
/// el fallo que no se ve.
class HooksDataSource {
  const HooksDataSource({this.leer});

  /// Nulo en la app: los ganchos salen del bundle. Un test lo sustituye por una función
  /// que devuelve texto y así comprueba la instalación entera sin levantar Flutter.
  final LeerElGancho? leer;

  Future<String> _fuente(NexusHook gancho) =>
      (leer ?? (g) => rootBundle.loadString(g.asset))(gancho);

  File _ajustes(String configDir) => File('$configDir/settings.json');

  /// Cómo está ese gancho en esa cuenta.
  ///
  /// Si algo falla al leer se devuelve [EstadoDelGancho.ausente] en vez de propagar: esto
  /// pinta una fila de una lista, y una excepción aquí tumbaría la pantalla entera por un
  /// archivo que alguien dejó a medias.
  Future<EstadoDelGancho> estado(String configDir, NexusHook gancho) async {
    final archivo = File(gancho.rutaEn(configDir));
    final existe = archivo.existsSync();

    final leidos = await _leerAjustes(configDir);
    final registrado =
        leidos.ajustes != null &&
        AjustesConGanchos.registrado(leidos.ajustes!, gancho);

    if (!existe && !registrado) return EstadoDelGancho.ausente;
    if (!existe || !registrado) return EstadoDelGancho.aMedias;

    try {
      final puesto = await archivo.readAsString();
      final trae = await _fuente(gancho);
      return puesto == trae
          ? EstadoDelGancho.alDia
          : EstadoDelGancho.desactualizado;
    } on FileSystemException {
      return EstadoDelGancho.aMedias;
    }
  }

  /// El mismo gancho en **varias cuentas de una vez**, con la misma regla que las skills:
  /// se devuelven los fallos por cuenta y no el primero, porque poner en dos y fallar en
  /// la tercera es otro resultado que no poner en ninguna.
  Future<Map<String, String>> installEn(
    List<String> configDirs,
    NexusHook gancho, {
    String? statusMessage,
  }) async {
    final fallos = <String, String>{};
    for (final configDir in configDirs) {
      final error = await install(
        configDir,
        gancho,
        statusMessage: statusMessage,
      );
      if (error != null) fallos[configDir] = error;
    }
    return fallos;
  }

  /// Copia el script y registra la entrada. Reinstalar es lo mismo que actualizar.
  ///
  /// **El script primero y el registro después.** Al revés, un fallo al copiar dejaría al
  /// CLI llamando a un archivo que no existe, y eso sí se rompe: un gancho que no se puede
  /// ejecutar es un error en cada turno.
  Future<String?> install(
    String configDir,
    NexusHook gancho, {
    String? statusMessage,
  }) async {
    final String fuente;
    try {
      fuente = await _fuente(gancho);
    } on Object {
      return 'No se pudo leer el gancho «${gancho.id}» de la app';
    }

    final destino = File(gancho.rutaEn(configDir));
    try {
      destino.parent.createSync(recursive: true);
      await destino.writeAsString(fuente);
    } on FileSystemException catch (error) {
      return error.message;
    }

    // El comando es la ruta pelada, así que el bit de ejecución no es un detalle: sin él
    // el CLI dice «permission denied» en cada turno y nadie relaciona eso con esta
    // pantalla. Se pone aquí y no se supone.
    try {
      final chmod = await Process.run('chmod', ['755', destino.path]);
      if (chmod.exitCode != 0) {
        return 'No se pudo hacer ejecutable ${destino.path}';
      }
    } on ProcessException catch (error) {
      return error.message;
    }

    return _escribirAjustes(
      configDir,
      (ajustes) => AjustesConGanchos.con(
        ajustes,
        gancho,
        comando: destino.path,
        statusMessage: statusMessage,
      ),
    );
  }

  /// Quita la entrada y borra el script.
  ///
  /// **La entrada primero**, por lo mismo que al instalar va la última: mientras el
  /// `settings.json` lo llame, el archivo tiene que estar.
  Future<String?> remove(String configDir, NexusHook gancho) async {
    final error = await _escribirAjustes(
      configDir,
      (ajustes) => AjustesConGanchos.sin(ajustes, gancho),
    );
    if (error != null) return error;

    try {
      final archivo = File(gancho.rutaEn(configDir));
      if (archivo.existsSync()) archivo.deleteSync();
      // La carpeta se va con el último: dejarla vacía hace pensar que queda algo puesto.
      final carpeta = archivo.parent;
      if (carpeta.existsSync() && carpeta.listSync().isEmpty) {
        carpeta.deleteSync();
      }
      return null;
    } on FileSystemException catch (error) {
      return error.message;
    }
  }

  Future<({Map<String, Object?>? ajustes, String? error})> _leerAjustes(
    String configDir,
  ) async {
    final archivo = _ajustes(configDir);
    // Sin archivo no hay nada malformado: es una cuenta que todavía no configuró nada.
    if (!archivo.existsSync()) return (ajustes: <String, Object?>{}, error: null);
    try {
      final crudo = await archivo.readAsString();
      if (crudo.trim().isEmpty) {
        return (ajustes: <String, Object?>{}, error: null);
      }
      final decodificado = jsonDecode(crudo);
      if (decodificado is! Map) {
        return (ajustes: null, error: 'El settings.json de esa cuenta no es un objeto');
      }
      return (ajustes: decodificado.cast<String, Object?>(), error: null);
    } on FormatException {
      return (
        ajustes: null,
        error: 'El settings.json de esa cuenta está mal formado y no se tocó',
      );
    } on FileSystemException catch (error) {
      return (ajustes: null, error: error.message);
    }
  }

  /// Lee, transforma y guarda — y **no guarda nada si no se pudo leer**.
  ///
  /// Sobrescribir un `settings.json` que no se entiende es perder el modelo, los permisos
  /// y los ganchos de otras cosas para poner uno nuestro. Se dice y se deja como estaba.
  ///
  /// Se escribe en un temporal y se renombra: `rename` es atómico en el mismo sistema de
  /// archivos, así que un fallo a media escritura deja el archivo anterior entero en vez
  /// de uno truncado — que es lo mismo que borrarlo, pero más difícil de diagnosticar.
  Future<String?> _escribirAjustes(
    String configDir,
    Map<String, Object?> Function(Map<String, Object?>) transformar,
  ) async {
    final leidos = await _leerAjustes(configDir);
    if (leidos.error != null) return leidos.error;

    try {
      // Con sangría porque ese archivo se edita a mano: dejarlo en una línea sería
      // apropiarnos de algo que es de quien usa la cuenta.
      final texto = const JsonEncoder.withIndent(
        '  ',
      ).convert(transformar(leidos.ajustes!));
      final destino = _ajustes(configDir);
      destino.parent.createSync(recursive: true);
      final temporal = File('${destino.path}.nexus-tmp');
      await temporal.writeAsString('$texto\n');
      await temporal.rename(destino.path);
      return null;
    } on FileSystemException catch (error) {
      return error.message;
    }
  }
}

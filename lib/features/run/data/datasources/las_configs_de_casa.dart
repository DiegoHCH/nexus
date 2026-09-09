import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/usecases/la_config_de_casa.dart';
import 'package:nexus/features/run/domain/usecases/lector_de_configs.dart';
import 'package:path_provider/path_provider.dart';

/// Las configuraciones de arranque **tuyas**, guardadas fuera del repositorio.
///
/// 🔴 **Fuera del repo a propósito, y es todo el punto.** Lo que se pidió fue
/// «la de prod con el panel de depuración, sin subirla al repo»: el
/// `launch.json` está versionado y compartido, así que tocarlo deja tu
/// `git status` sucio, viaja en cualquier commit distraído y le cambia el menú
/// del editor al equipo. En un repo del trabajo, además, la regla es no
/// comitear nada.
///
/// **Con la forma de un `launch.json`** —lo escribe [LaConfigDeCasa.comoArchivo]
/// y lo lee el mismo [LectorDeConfigs]—: así el archivo se puede abrir y
/// retocar a mano sin aprender un formato nuevo, y no hay un lector nuevo que
/// mantener.
class LasConfigsDeCasa {
  const LasConfigsDeCasa({this.carpeta});

  /// Dónde viven. Inyectable para poder probarlo en una carpeta temporal en vez
  /// de escribir en el soporte de la app de verdad.
  final Directory? carpeta;

  Future<File> archivoDe(String proyecto) async {
    final donde = carpeta ?? await getApplicationSupportDirectory();
    final dir = Directory('${donde.path}/configuraciones');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/${_slug(proyecto)}.json');
  }

  /// Un archivo por proyecto: una configuración nombra un flavor y un archivo
  /// de defines de **ese** repo, y ofrecerla en otro es ofrecer una compilación
  /// fallida con nombre creíble.
  static String _slug(String proyecto) => proyecto
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<List<ConfigDeArranque>> deProyecto(String proyecto) async {
    try {
      final file = await archivoDe(proyecto);
      if (!file.existsSync()) return const [];
      return LectorDeConfigs.leer(await file.readAsString(), local: true);
    } on Object catch (error) {
      // Un archivo a medio escribir no puede tumbar el menú que lo ofrece: se
      // anota y se sigue con las del repo, que es el caso normal.
      debugPrint('correr · no se pudieron leer tus configuraciones: $error');
      return const [];
    }
  }

  /// Guarda [cual] junto a las que ya tenías. Devuelve `false` si no se pudo.
  Future<bool> anadir(String proyecto, ConfigDeArranque cual) async {
    final ya = await deProyecto(proyecto);
    // Por nombre: dos con el mismo nombre serían la misma en el desplegable, y
    // la segunda no se podría elegir nunca.
    if (ya.any((otra) => otra.nombre == cual.nombre)) return false;
    return _escribir(proyecto, [...ya, cual]);
  }

  Future<bool> quitar(String proyecto, String nombre) async {
    final ya = await deProyecto(proyecto);
    return _escribir(proyecto, [
      for (final config in ya)
        if (config.nombre != nombre) config,
    ]);
  }

  Future<bool> _escribir(
    String proyecto,
    List<ConfigDeArranque> configs,
  ) async {
    try {
      final file = await archivoDe(proyecto);
      await file.writeAsString(LaConfigDeCasa.comoArchivo(configs));
      return true;
    } on Object catch (error) {
      debugPrint('correr · no se pudieron guardar tus configuraciones: $error');
      return false;
    }
  }
}

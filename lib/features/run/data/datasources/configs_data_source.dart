import 'dart:io';

import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/usecases/lector_de_configs.dart';

/// El `launch.json` de un proyecto, leído del disco.
class ConfigsDataSource {
  const ConfigsDataSource();

  /// Las configuraciones que declara [proyecto].
  ///
  /// **Solo del proyecto que se pide, y nunca de otro.** Una configuración
  /// nombra un flavor, un archivo de `--dart-define` y a veces una ruta de ese
  /// repo: fuera de él no significa nada, y ofrecer la de un proyecto para correr
  /// otro es ofrecer una compilación fallida con nombre creíble.
  ///
  /// Lista vacía cuando el proyecto no tiene `launch.json`, que es lo normal en
  /// un repo que no es de Flutter. No es un error: es que no hay nada que
  /// ofrecer.
  Future<List<ConfigDeArranque>> deProyecto(String proyecto) async {
    final archivo = File('$proyecto/.vscode/launch.json');
    if (!archivo.existsSync()) return const [];

    try {
      return LectorDeConfigs.leer(await archivo.readAsString());
    } on FileSystemException {
      // Un archivo que no se puede leer —permisos, un enlace roto— no puede
      // tumbar la pantalla que lo ofrece.
      return const [];
    }
  }
}

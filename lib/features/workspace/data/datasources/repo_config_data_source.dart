import 'dart:io';

import 'package:nexus/features/workspace/domain/entities/config_del_repo.dart';

/// Lee el `.nexus/config.json` de un repositorio.
///
/// **Con caché por fecha y tamaño**, y no por ruta a secas: el archivo se relee
/// después de cada cambio de ajustes y al arrancar, y un `git pull` lo cambia
/// por debajo. Comparar el `stat` es una llamada al inodo; volver a leer y
/// decodificar el JSON en cada repaso, no.
///
/// No es `const` a propósito, como el lector del histórico: una instancia sin
/// estado tiraría la caché en cada reconstrucción del provider y la caché no
/// existiría.
class RepoConfigDataSource {
  RepoConfigDataSource();

  final _leidos = <String, _Leido>{};

  Future<ConfigDelRepo?> leer(String workingDirectory) async {
    final archivo = File('$workingDirectory/${ConfigDelRepo.archivo}');

    final FileStat estado;
    try {
      estado = await archivo.stat();
    } on FileSystemException {
      _leidos.remove(archivo.path);
      return null;
    }
    if (estado.type != FileSystemEntityType.file) {
      _leidos.remove(archivo.path);
      return null;
    }

    final visto = _leidos[archivo.path];
    if (visto != null &&
        visto.modificado == estado.modified &&
        visto.tamano == estado.size) {
      return visto.config;
    }

    ConfigDelRepo? config;
    try {
      config = ConfigDelRepo.deTexto(await archivo.readAsString());
    } on FileSystemException {
      // Ilegible ahora mismo —permisos, o alguien reescribiéndolo— no es «este
      // repo no declara nada»: es «no se sabe». Se deja lo último que se supo.
      return visto?.config;
    }

    _leidos[archivo.path] = _Leido(estado.modified, estado.size, config);
    return config;
  }

  /// Lo que declaran todas las carpetas de una vez, por su ruta de trabajo.
  Future<Map<String, ConfigDelRepo>> leerTodas(
    Map<String, String> porCarpeta,
  ) async {
    final salida = <String, ConfigDelRepo>{};
    for (final entrada in porCarpeta.entries) {
      final config = await leer(entrada.value);
      if (config != null) salida[entrada.key] = config;
    }
    return salida;
  }
}

class _Leido {
  const _Leido(this.modificado, this.tamano, this.config);

  final DateTime modificado;
  final int tamano;
  final ConfigDelRepo? config;
}

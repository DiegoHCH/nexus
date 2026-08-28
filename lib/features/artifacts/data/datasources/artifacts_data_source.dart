import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';

/// La carpeta de documentos generados y su visor.
class ArtifactsDataSource {
  const ArtifactsDataSource();

  static const _channel = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Lo que hay dentro, de lo más reciente a lo más antiguo.
  ///
  /// **La raíz y, un nivel más abajo, las carpetas que son una cuenta.** Nada más.
  /// Seguir bajando metería en la lista el `assets/` que muchos documentos traen al
  /// lado —había dos ahí mismo cuando esto se escribió, `assets-reformas` y
  /// `assets-zonas-comunes`— y por eso no se recorre el árbol entero: se entra solo
  /// donde se sabe qué hay.
  ///
  /// [cuentas] son los nombres de perfil del Mac. Sin ellos se mira solo la raíz, que
  /// es el comportamiento de antes: un Mac con una sola cuenta no gana nada y no
  /// arriesga nada.
  Future<List<Artifact>> list(
    String directory, {
    Set<String> cuentas = const {},
  }) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];

    final artifacts = <Artifact>[
      ..._enUnaCarpeta(dir, null),
      for (final cuenta in cuentas)
        ..._enUnaCarpeta(Directory('$directory/$cuenta'), cuenta),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return artifacts;
  }

  List<Artifact> _enUnaCarpeta(Directory dir, String? cuenta) {
    if (!dir.existsSync()) return const [];
    try {
      return [
        for (final entry in dir.listSync(followLinks: false))
          if (entry is File)
            if (!entry.path.split('/').last.startsWith('.') &&
                Artifact.isListable(entry.path))
              Artifact(
                path: entry.path,
                name: entry.path.split('/').last,
                at: entry.statSync().modified,
                account: cuenta,
              ),
      ];
    } on FileSystemException {
      // Una carpeta que no se puede leer no invalida las otras: se enseña lo que
      // haya. Devolver vacío entero por un permiso suelto esconde todo lo demás.
      return const [];
    }
  }

  /// Abre el documento en su propia ventana. Si ya estaba abierto, la trae al
  /// frente en vez de abrir otra.
  Future<void> open(String path) => _invoke('open', path);

  /// Lo enseña en el Finder, seleccionado. Hace falta porque lo siguiente que
  /// se hace con un mockup terminado es mandárselo a alguien.
  Future<void> reveal(String path) => _invoke('reveal', path);

  /// Los rótulos del interruptor del visor, en el idioma **de la app**.
  ///
  /// Se mandan desde aquí y no se escriben en Swift por el mismo motivo que los
  /// del menú de la barra de estado: el idioma se elige en Ajustes y puede no
  /// ser el del sistema. Una ventana en un idioma y su casilla en otro es de las
  /// cosas que no se ven hasta que le pasa a alguien.
  Future<void> textos({
    required String permitir,
    required String permitirAyuda,
  }) async {
    try {
      await _channel.invokeMethod<bool>('textos', {
        'permitir': permitir,
        'permitirAyuda': permitirAyuda,
      });
    } on PlatformException {
      // Sin rótulos el visor usa los suyos: se ve en otro idioma, no se rompe.
    } on MissingPluginException {
      // En pruebas no hay nadie al otro lado.
    }
  }

  Future<void> _invoke(String method, String path) async {
    try {
      await _channel.invokeMethod<bool>(method, {'path': path});
    } on PlatformException {
      // El visor es un extra: si el sistema dice que no, no hay nada que
      // rescatar aquí y el archivo sigue en su carpeta.
    } on MissingPluginException {
      // En pruebas no hay nadie al otro lado.
    }
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';

/// La carpeta de documentos generados y su visor.
class ArtifactsDataSource {
  const ArtifactsDataSource();

  static const _channel = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Lo que hay dentro, de lo más reciente a lo más antiguo.
  ///
  /// Un nivel y no recursivo: la carpeta de artefactos es un cajón, no un
  /// árbol, y bajar recursivamente metería en la lista el `assets/` que muchos
  /// documentos traen al lado.
  Future<List<Artifact>> list(String directory) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];

    final artifacts = <Artifact>[];
    try {
      for (final entry in dir.listSync(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.path.split('/').last;
        if (name.startsWith('.') || !Artifact.isViewable(entry.path)) continue;
        artifacts.add(
          Artifact(path: entry.path, name: name, at: entry.statSync().modified),
        );
      }
    } on FileSystemException {
      return const [];
    }

    artifacts.sort((a, b) => b.at.compareTo(a.at));
    return artifacts;
  }

  /// Abre el documento en su propia ventana. Si ya estaba abierto, la trae al
  /// frente en vez de abrir otra.
  Future<void> open(String path) => _invoke('open', path);

  /// Lo enseña en el Finder, seleccionado. Hace falta porque lo siguiente que
  /// se hace con un mockup terminado es mandárselo a alguien.
  Future<void> reveal(String path) => _invoke('reveal', path);

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

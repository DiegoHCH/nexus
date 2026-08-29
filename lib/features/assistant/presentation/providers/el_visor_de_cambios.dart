import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/domain/usecases/el_diff_como_html.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Abre los cambios de un encargo en el visor de documentos.
///
/// **Se reutiliza esa ventana** —la de los artefactos— en vez de hacer una
/// nueva: ya está encerrada, sin red y sin JavaScript, y abrir código es
/// exactamente el caso para el que se encerró. El diff se pinta como HTML y se
/// deja en un archivo temporal, porque lo que el visor sabe abrir son rutas.
class ElVisorDeCambios {
  const ElVisorDeCambios(this._ref);

  final Ref _ref;

  Future<void> abrir(GitChanges cambios, String titulo) async {
    // El segundo alcance: todo lo que sigue sin comitear. Se pide aquí y no
    // antes porque solo hace falta si alguien abre la ventana, y es un `git
    // diff` de más en cada encargo.
    final carpeta = _ref
        .read(workspaceControllerProvider)
        .active
        ?.workingDirectory;
    final todo = carpeta == null
        ? null
        : await const GitDataSource().changesSince(carpeta, 'HEAD');

    final html = ElDiffComoHtml.de(
      diff: cambios.diff,
      nuevos: cambios.newFiles,
      titulo: titulo,
      tambien: todo?.diff,
      tituloDeTambien: todo == null ? null : 'Todo lo no comiteado',
    );

    // Con la hora en el nombre: dos encargos abiertos a la vez son dos
    // ventanas, y compartir archivo haría que la primera enseñara la segunda.
    final ruta =
        '${Directory.systemTemp.path}/nexus-cambios-'
        '${DateTime.now().millisecondsSinceEpoch}.html';
    await File(ruta).writeAsString(html);
    await _ref.read(artifactsDataSourceProvider).open(ruta);
  }
}

final elVisorDeCambiosProvider = Provider<ElVisorDeCambios>(
  ElVisorDeCambios.new,
);

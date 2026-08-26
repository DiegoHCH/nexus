import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/workspace/data/datasources/marcas_por_rama.dart';

/// Que se pidió una revisión del diff contra las reglas de su capa, y sobre qué árbol.
///
/// **No lleva resultado, y no es un olvido.** Una revisión no tiene verde: lo que devuelve
/// son hallazgos, y decidir si valen es de quien los lee. Guardar aquí un «pasó» sería
/// inventar un eje que no existe y, peor, uno que después alguien usaría como puerta.
///
/// Lo único que se anota es que corrió y sobre qué código, para poder decir la única cosa
/// útil: si lo revisado sigue siendo lo que hay.
@immutable
class Revision {
  const Revision({required this.cuando, this.huella, this.archivos = 0});

  final DateTime cuando;

  /// El árbol que se revisó. Sin esto, «revisado» valdría para siempre.
  final String? huella;

  /// Cuántos archivos entraron. Para poder decir «se revisaron tres» en vez de un
  /// «revisado» a secas que no dice de qué.
  final int archivos;

  /// Si lo revisado sigue siendo el código que hay ahora.
  bool cubre(String? huellaDeAhora) =>
      huella != null && huellaDeAhora != null && huella == huellaDeAhora;

  Map<String, Object?> toJson() => {
    'cuando': cuando.millisecondsSinceEpoch ~/ 1000,
    if (huella != null) 'huella': huella,
    'archivos': archivos,
  };

  static Revision? fromJson(Object? crudo) {
    if (crudo is! Map) return null;
    final cuando = crudo['cuando'];
    if (cuando is! num) return null;
    return Revision(
      cuando: DateTime.fromMillisecondsSinceEpoch(
        (cuando * 1000).round(),
        isUtc: true,
      ),
      huella: crudo['huella'] as String?,
      archivos: (crudo['archivos'] as num?)?.toInt() ?? 0,
    );
  }
}

/// La última revisión pedida en cada carpeta y rama.
///
/// Archivo aparte del gate y no un campo suyo: el marco las trata como **ejes distintos**
/// —uno mide, la otra lee— y meterlas en la misma marca acabaría con reglas raras del tipo
/// «correr el gate borra la revisión», que no significan nada.
class RevisionDataSource {
  const RevisionDataSource();

  Directory _dir(String configDir) => Directory('$configDir/nexus-revisiones');

  Future<Revision?> leer(
    String configDir,
    String carpeta, {
    String? rama,
  }) async {
    final guardado = await _guardado(configDir, carpeta);
    final ramas = guardado?['ramas'];
    if (ramas is! Map) return null;
    return Revision.fromJson(ramas[MarcasPorRama.clave(rama)]);
  }

  /// Anota que se acaba de pedir una. **La última manda**: no se apilan.
  ///
  /// Al contrario que los cierres, aquí el historial no dice nada — lo que importa es si
  /// la de ahora cubre el código de ahora, y una revisión de hace tres commits no aporta
  /// más que ruido.
  Future<Revision> anotar(
    String configDir,
    String carpeta, {
    String? rama,
    String? huella,
    int archivos = 0,
  }) async {
    final dir = _dir(configDir)..createSync(recursive: true);
    final archivo = File('${dir.path}/${MarcasPorRama.nombre(carpeta)}.json');

    final ramas = <String, Object?>{};
    final guardado = await _guardado(configDir, carpeta);
    if (guardado?['ramas'] is Map) {
      ramas.addAll((guardado!['ramas'] as Map).cast<String, Object?>());
    }

    final revision = Revision(
      cuando: DateTime.now().toUtc(),
      huella: huella,
      archivos: archivos,
    );
    ramas[MarcasPorRama.clave(rama)] = revision.toJson();

    await archivo.writeAsString(
      '${jsonEncode({'carpeta': carpeta, 'ramas': ramas})}\n',
    );
    return revision;
  }

  Future<Set<({String carpeta, String? rama})>> carpetasYRamas(
    String configDir,
  ) => MarcasPorRama.claves(_dir(configDir));

  Future<void> borrar(String configDir, String carpeta, String? rama) =>
      MarcasPorRama.borrar(_dir(configDir), carpeta, rama);

  Future<Map<String, Object?>?> _guardado(
    String configDir,
    String carpeta,
  ) async {
    final archivo = File(
      '${_dir(configDir).path}/${MarcasPorRama.nombre(carpeta)}.json',
    );
    if (!archivo.existsSync()) return null;
    try {
      final leido = jsonDecode(await archivo.readAsString());
      return leido is Map ? leido.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }
}

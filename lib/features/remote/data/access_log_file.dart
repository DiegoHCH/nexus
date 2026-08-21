import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/remote/domain/access_log.dart';
import 'package:path_provider/path_provider.dart';

/// El registro, en un archivo al que solo se añade.
///
/// Se abre en modo **append** y nunca se reescribe: eso es lo que hace que valga como
/// registro. Lo único que lo toca de otra forma es la rotación, y rota **renombrando**
/// —no recortando— porque recortar por dentro sería justamente editarlo.
class AccessLogFile implements AccessLog {
  AccessLogFile({this.carpeta, this.tope = 512 * 1024});

  /// Cuánto puede crecer antes de rotar.
  ///
  /// Medio mega son unas cinco mil líneas: suficiente para ver qué pasó anoche y poco
  /// para el disco. Un registro sin tope crece mientras la app viva, y un canal que
  /// reconecta mucho —un móvil entrando y saliendo de cobertura— escribe bastante.
  final int tope;

  /// Dónde vive. Inyectable para poder probarlo en una carpeta temporal en vez de
  /// escribir en el soporte de la app de verdad.
  final Directory? carpeta;
  File? _archivo;

  /// Las escrituras van en fila.
  ///
  /// Dos anotaciones a la vez sobre el mismo archivo pueden intercalarse a media
  /// línea, y una línea partida en dos es peor que no tenerla: parece dos eventos.
  Future<void> _cola = Future.value();

  Future<File> _abrir() async {
    final ya = _archivo;
    if (ya != null) return ya;
    final donde = carpeta ?? await getApplicationSupportDirectory();
    final archivo = File('${donde.path}/canal.log');
    if (!archivo.parent.existsSync()) {
      archivo.parent.createSync(recursive: true);
    }
    return _archivo = archivo;
  }

  @override
  Future<void> anotar(AccessEntry entrada) {
    // La cola se encadena y **se protege de sí misma**: si una escritura falla, la
    // siguiente tiene que seguir intentándolo, no heredar el error.
    _cola = _cola.then((_) => _escribir(entrada)).catchError((Object _) {});
    return _cola;
  }

  Future<void> _escribir(AccessEntry entrada) async {
    try {
      final archivo = await _abrir();
      if (await archivo.exists() && await archivo.length() > tope) {
        // Rotar renombrando: el anterior queda entero y el nuevo empieza vacío.
        // **No se recorta el archivo por dentro** — eso sería editarlo.
        final anterior = File('${archivo.path}.anterior');
        if (await anterior.exists()) await anterior.delete();
        await archivo.rename(anterior.path);
        _archivo = null;
      }
      await (await _abrir()).writeAsString(
        '${entrada.linea}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (error) {
      // Un fallo al registrar **no puede tumbar el canal**, y menos el registro de un
      // rechazo: sería la forma más tonta de convertir un intento fallido en una
      // caída.
      debugPrint('no se pudo anotar en el registro del canal: $error');
    }
  }

  @override
  Future<List<String>> ultimas({int cuantas = 200}) async {
    try {
      final archivo = await _abrir();
      if (!await archivo.exists()) return const [];
      final lineas = (await archivo.readAsLines())
          .where((l) => l.trim().isNotEmpty)
          .toList();
      // Lo más reciente primero: es el orden en que se lee cuando algo acaba de
      // fallar.
      final ultimas = lineas.reversed.take(cuantas).toList();
      return ultimas;
    } on Object {
      return const [];
    }
  }

  @override
  Future<String?> get ruta async {
    try {
      return (await _abrir()).path;
    } on Object {
      return null;
    }
  }
}

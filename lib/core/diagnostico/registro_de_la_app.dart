import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lo que le pasó a la app, escrito donde se pueda leer después.
///
/// **Existe porque `debugPrint` no llega a ninguna parte en release**, y eso ya
/// estaba medido en este repo: cero líneas en tres horas con el canal
/// encendido. Es el mismo descubrimiento que hizo nacer el registro del canal,
/// pero aquel solo anota lo del canal — y la app se distribuye firmada, se
/// actualiza sola y no tenía ninguna forma de contar que se rompió en el Mac de
/// otro.
///
/// Aquí no hace falta un servicio de terceros ni mandar nada fuera. Basta con
/// que el fallo **esté escrito** cuando alguien pregunte.
///
/// ## Qué acaba aquí dentro
///
/// Todo lo que pase por `debugPrint`, sin tocar los 41 sitios que ya lo
/// llaman: se envuelve la función global al arrancar. Eso es lo que hace que
/// esto valga algo desde el primer día en vez de dentro de seis meses, cuando
/// alguien se hubiera acordado de anotar en los sitios importantes.
///
/// Y con ello **la regla**: lo que se le da a `debugPrint` acaba en un archivo
/// del disco. No es nuevo —el `toString` del token ya enseña solo su huella
/// justo por esto, «el día que alguien escriba un `debugPrint` de buena fe»—
/// pero ahora es literal, y conviene que esté dicho aquí.
///
/// Append-only y rota renombrando, igual que el del canal: recortar por dentro
/// sería editarlo, y entonces deja de ser un registro.
class RegistroDeLaApp {
  RegistroDeLaApp({this.carpeta, this.tope = 512 * 1024});

  /// Cuánto puede crecer antes de rotar. Medio mega son unas cinco mil líneas:
  /// bastante para ver qué pasó anoche y poco para el disco.
  final int tope;

  /// Dónde vive. Inyectable para poder probarlo en una carpeta temporal en vez
  /// de escribir en el soporte de la app de verdad.
  final Directory? carpeta;
  File? _archivo;

  /// Las escrituras van en fila: dos a la vez sobre el mismo archivo pueden
  /// intercalarse a media línea, y una línea partida en dos parece dos cosas.
  Future<void> _cola = Future.value();

  Future<File> _abrir() async {
    final ya = _archivo;
    if (ya != null) return ya;
    final donde = carpeta ?? await getApplicationSupportDirectory();
    final archivo = File('${donde.path}/nexus.log');
    if (!archivo.parent.existsSync()) {
      archivo.parent.createSync(recursive: true);
    }
    return _archivo = archivo;
  }

  /// Escribe una línea, con la hora delante. No lanza nunca.
  Future<void> anotar(String mensaje) {
    final linea = '${DateTime.now().toIso8601String()} · ${mensaje.trim()}';
    // La cola se encadena y **se protege de sí misma**: si una escritura falla,
    // la siguiente tiene que seguir intentándolo, no heredar el error.
    _cola = _cola.then((_) => _escribir(linea)).catchError((Object _) {});
    return _cola;
  }

  Future<void> _escribir(String linea) async {
    try {
      final archivo = await _abrir();
      if (await archivo.exists() && await archivo.length() > tope) {
        // Rotar renombrando: el anterior queda entero y el nuevo empieza vacío.
        final anterior = File('${archivo.path}.anterior');
        if (await anterior.exists()) await anterior.delete();
        await archivo.rename(anterior.path);
        _archivo = null;
      }
      await (await _abrir()).writeAsString(
        '$linea\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // **En silencio, y aquí sí.** En cualquier otro sitio esto llevaría un
      // `debugPrint`, pero es justo lo que se está envolviendo: anotar el fallo
      // de anotar volvería a entrar aquí, y el bucle se come el proceso.
    }
  }

  /// Dónde está, para poder abrirlo. `null` si ni siquiera se pudo resolver la
  /// carpeta — entonces no hay nada que enseñar.
  Future<String?> get ruta async {
    try {
      return (await _abrir()).path;
    } on Object {
      return null;
    }
  }
}

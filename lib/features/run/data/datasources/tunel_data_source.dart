import 'dart:io';

import 'package:nexus/core/platform/herramienta_externa.dart';

/// El túnel al puerto del dispositivo, para poder llamar a la app desde aquí.
///
/// 🔴 **Sin esto la consola de la app no se alcanza.** El servidor de
/// depuración vive **dentro** del teléfono o del emulador, así que
/// `http://localhost:9777` de esta máquina no es el suyo: hace falta que `adb`
/// enchufe un puerto de aquí con el de allí. Es el paso que había que dar a mano
/// en la terminal, y el que hace que traer la consola dentro de Nexus sea útil y
/// no solo bonito.
///
/// **El simulador de iOS no lo necesita** —comparte la red de la máquina— y el
/// iPhone físico pide `iproxy`, que no viene con Xcode y queda fuera. Así que
/// aquí solo está Android, y quien pregunte por lo demás recibe un «no hay nada
/// que abrir» en vez de un fallo.
class TunelDataSource {
  const TunelDataSource({
    this.donde = HerramientaExterna.donde,
    this.correr = Process.run,
  });

  /// Cómo se encuentra el binario y cómo se ejecuta. Inyectables porque lo que
  /// hay que probar es **con qué argumentos sale** y qué pasa cuando `adb` no
  /// está, y eso no se puede provocar en una máquina que sí lo tiene.
  final Future<String?> Function(String, {required List<String> candidatos})
  donde;

  final Future<ProcessResult> Function(String, List<String>) correr;

  /// Enchufa `tcp:<puerto>` de esta máquina con el mismo puerto del dispositivo.
  ///
  /// **El mismo número a los dos lados** a propósito: la URL que se le enseña a
  /// quien mira es la que la app imprimió en su banner, y traducir el puerto
  /// dejaría la de la ventana distinta de la del registro — con la pregunta de
  /// cuál de las dos es la buena.
  ///
  /// Devuelve el motivo si no se pudo, o `null` si quedó abierto.
  Future<String?> abrir({required String deviceId, required int puerto}) async {
    final adb = await _adb();
    if (adb == null) return 'No se encontró adb para abrir el túnel';

    final salida = await correr(adb, [
      '-s',
      deviceId,
      'forward',
      'tcp:$puerto',
      'tcp:$puerto',
    ]);
    if (salida.exitCode == 0) return null;
    return _elMotivo(salida) ?? 'adb forward falló';
  }

  /// Lo quita. **Se llama al terminar la corrida y no se olvida**: un `forward`
  /// huérfano se queda vivo en el daemon de `adb` el resto de la sesión, y el
  /// siguiente arranque encontraría el puerto ocupado por el fantasma del
  /// anterior.
  Future<void> cerrar({required String deviceId, required int puerto}) async {
    final adb = await _adb();
    if (adb == null) return;
    await correr(adb, ['-s', deviceId, 'forward', '--remove', 'tcp:$puerto']);
  }

  Future<String?> _adb() => donde(
    'adb',
    candidatos: HerramientaExterna.candidatosDeAdb(
      Platform.environment['HOME'] ?? '',
    ),
  );

  /// `adb` escribe sus fallos por stderr, y cuando no dice nada por ahí lo dice
  /// por stdout. Se prefiere el primero y se cae al segundo.
  static String? _elMotivo(ProcessResult salida) {
    for (final donde in [salida.stderr, salida.stdout]) {
      final texto = '$donde'.trim();
      if (texto.isNotEmpty) return texto.split('\n').first;
    }
    return null;
  }
}

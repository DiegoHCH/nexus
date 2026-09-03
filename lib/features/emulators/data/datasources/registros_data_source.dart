import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';
import 'package:nexus/features/emulators/domain/usecases/los_registros_del_dispositivo.dart';

/// El registro del sistema de un dispositivo, línea a línea.
///
/// **Se lee mientras corre y no al final**, que es lo que lo separa de todo lo
/// demás que Nexus lanza: un `logcat` no termina, y lo que se quiere de él es
/// justo lo que está pasando ahora. Por eso entrega un `Stream` y no un
/// resultado, como `CorridaViva`.
class RegistrosDataSource {
  const RegistrosDataSource({
    this.donde = HerramientaExterna.donde,
    this.lanzar = Process.start,
  });

  /// Cómo se encuentra el binario. Inyectable porque la mitad de lo que hay que
  /// probar aquí es **qué pasa cuando no está**, y eso no se puede provocar en
  /// una máquina que sí lo tiene.
  final Future<String?> Function(String, {required List<String> candidatos})
  donde;

  /// Y cómo se lanza, por lo mismo: lo que importa es con qué argumentos sale y
  /// cómo se lee lo que escupe, no que exista un `adb` de verdad.
  final Future<Process> Function(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool includeParentEnvironment,
    bool runInShell,
    String? workingDirectory,
    ProcessStartMode mode,
  })
  lanzar;

  /// Si esta máquina puede leer el registro de esa plataforma.
  ///
  /// 🔴 **No es lo mismo en las dos, y por eso se pregunta.** `adb` lo tiene
  /// cualquiera que compile Android; `idevicesyslog` viene de
  /// `libimobiledevice` y **es opcional** — ofrecer el botón sin comprobarlo es
  /// ofrecer uno que falla al tocarlo.
  Future<bool> hay(PlataformaEmulador plataforma) async =>
      await _ruta(plataforma) != null;

  Future<String?> _ruta(PlataformaEmulador plataforma) => switch (plataforma) {
    PlataformaEmulador.android => donde(
      LosRegistrosDelDispositivo.binarioAndroid,
      candidatos: HerramientaExterna.candidatosDeAdb(
        Platform.environment['HOME'] ?? '',
      ),
    ),
    PlataformaEmulador.ios => donde(
      LosRegistrosDelDispositivo.binarioIos,
      candidatos: const [],
    ),
  };

  /// Las líneas que va escribiendo el dispositivo.
  ///
  /// El stream se cierra cuando el proceso termina, y **cancelarlo lo mata**:
  /// un `logcat` que sobreviva a la ventana que lo enseñaba es un proceso
  /// huérfano escribiendo a nadie. Es el mismo cuidado que se le puso al espejo
  /// —ver `EmuladoresDataSource.verLaPantalla`— por el motivo contrario: aquel
  /// se suelta a propósito porque tiene ventana propia, y este no tiene ninguna.
  Stream<LineaDeRegistro> escuchar({
    required PlataformaEmulador plataforma,
    required String deviceId,
    bool desdeAhora = true,
  }) {
    late StreamController<LineaDeRegistro> control;
    Process? proceso;
    var cerrado = false;

    Future<void> arrancar() async {
      final ruta = await _ruta(plataforma);
      if (ruta == null) {
        control.addError(
          _NoEstaLaHerramienta(
            LosRegistrosDelDispositivo.binarioPara(plataforma),
          ),
        );
        await control.close();
        return;
      }
      try {
        proceso = await lanzar(
          ruta,
          LosRegistrosDelDispositivo.argumentos(
            plataforma: plataforma,
            deviceId: deviceId,
            desdeAhora: desdeAhora,
          ),
          environment: ClaudeEnvironment.forTools(),
          includeParentEnvironment: false,
        );
      } on ProcessException catch (error) {
        control.addError(error);
        await control.close();
        return;
      }
      if (cerrado) {
        proceso!.kill();
        return;
      }

      proceso!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((linea) {
            final leida = LosRegistrosDelDispositivo.leer(linea);
            if (leida != null) control.add(leida);
          }, onDone: () => cerrado ? null : control.close());

      // 🔴 **`stderr` se drena y no se enseña.** `adb` escribe ahí cosas que no
      // son del dispositivo —«waiting for device», el aviso del daemon— y
      // mezclarlas con el registro las haría pasar por líneas del teléfono. Lo
      // que no se puede es dejarlo sin leer: la tubería se llena y el proceso se
      // bloquea, que es exactamente lo que se arregló en el PR de los procesos
      // colgados.
      proceso!.stderr.listen((bytes) {
        debugPrint(
          'registro · ${utf8.decode(bytes, allowMalformed: true).trim()}',
        );
      });
    }

    control = StreamController<LineaDeRegistro>(
      onListen: () => unawaited(arrancar()),
      onCancel: () async {
        cerrado = true;
        proceso?.kill();
      },
    );
    return control.stream;
  }
}

/// La herramienta no está en esta máquina.
class _NoEstaLaHerramienta implements Exception {
  const _NoEstaLaHerramienta(this.binario);
  final String binario;

  @override
  String toString() => 'No se encontró $binario';
}

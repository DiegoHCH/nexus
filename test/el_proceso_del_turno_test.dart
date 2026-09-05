import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';

// Que un encargo terminado no deje su proceso vivo.
//
// Medido en una máquina de un día normal antes de esto: **49 `claude` vivos
// colgando de Nexus y 3,92 GB de RSS**, uno por encargo. No salían solos porque
// con `--input-format stream-json` el CLI se queda leyendo el stdin que le
// dejamos abierto para los permisos, y nadie se lo cerraba.
//
// Con procesos de verdad y no con dobles, porque lo que hay que probar es
// justamente el trato con el sistema operativo. `cat` sirve de sustituto exacto
// del CLI en lo que importa: vive mientras su entrada siga abierta.
//
// Y `sh` con la señal atrapada imita la otra mitad de lo medido: **el CLI ignora
// `SIGTERM`** —51 de 52 lo aguantaron—, así que rematar con el `kill()` de
// fábrica de Dart, que manda `SIGTERM`, no habría servido.

void main() {
  test('al acabar el turno se le cierra la entrada y sale solo', () async {
    final proceso = await Process.start('/bin/cat', []);
    final vivo = ElProcesoDelTurno()..tomar(proceso, preguntando: true);

    vivo.elTurnoAcabo();

    expect(
      await proceso.exitCode.timeout(const Duration(seconds: 5)),
      0,
      reason: 'sale por las buenas, que es como recoge a sus propios hijos',
    );
  });

  test('decirlo dos veces no rompe nada', () async {
    final proceso = await Process.start('/bin/cat', []);
    final vivo = ElProcesoDelTurno()..tomar(proceso, preguntando: true);

    vivo.elTurnoAcabo();
    vivo.elTurnoAcabo();

    expect(await proceso.exitCode.timeout(const Duration(seconds: 5)), 0);
  });

  // 🔴 El caso del botón Detener: aquí no hay salida limpia que esperar.
  test('soltar remata a uno que ignora SIGTERM', () async {
    final proceso = await Process.start('/bin/sh', [
      '-c',
      'trap "" TERM; while true; do sleep 0.2; done',
    ]);
    final vivo = ElProcesoDelTurno()..tomar(proceso, preguntando: false);

    await vivo.soltar();

    expect(
      await proceso.exitCode.timeout(const Duration(seconds: 5)),
      isNot(0),
      reason: 'con SIGTERM seguiría corriendo; hace falta SIGKILL',
    );
  });

  test('soltar sobre uno que ya salió no revienta', () async {
    final proceso = await Process.start('/bin/cat', []);
    final vivo = ElProcesoDelTurno()..tomar(proceso, preguntando: true);

    vivo.elTurnoAcabo();
    await proceso.exitCode.timeout(const Duration(seconds: 5));

    await expectLater(vivo.soltar(), completes);
  });

  test('olvidado, ya no hay nada que rematar', () async {
    final proceso = await Process.start('/bin/cat', []);
    final vivo = ElProcesoDelTurno()..tomar(proceso, preguntando: true);

    vivo.olvida();
    await vivo.soltar();

    // Sigue vivo: olvidarlo es soltar la referencia, no matarlo. Lo mata el
    // `finally` del generador, que para eso ya está.
    expect(proceso.kill(), isTrue, reason: 'seguía vivo, como debe');
    proceso.kill(ProcessSignal.sigkill);
  });
}

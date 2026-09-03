import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/data/datasources/registros_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';

/// El registro del dispositivo, leído mientras corre.
///
/// Es lo único de Nexus que **se lee mientras pasa y no al final**: un `logcat`
/// no termina, y lo que se quiere de él es justo lo que está ocurriendo. Por eso
/// entrega un `Stream`, y por eso lo que hay que probar es el ciclo entero —
/// arrancar, entregar, y morirse con quien lo escuchaba—.
void main() {
  late Directory cajon;

  setUp(() => cajon = Directory.systemTemp.createTempSync('nexus_registro'));
  tearDown(() => cajon.deleteSync(recursive: true));

  Future<String> guionDe(String cuerpo) async {
    final script = File('${cajon.path}/adb-de-mentira.sh');
    script.writeAsStringSync('#!/bin/sh\n$cuerpo\n');
    await Process.run('chmod', ['+x', script.path]);
    return script.path;
  }

  RegistrosDataSource conUn(String? ruta) => RegistrosDataSource(
    donde: (nombre, {required candidatos}) async => ruta,
    lanzar: Process.start,
  );

  test('sin la herramienta se dice, en vez de quedarse callado', () async {
    final fuente = conUn(null);

    expect(
      fuente.escuchar(plataforma: PlataformaEmulador.ios, deviceId: 'x'),
      emitsError(isA<Exception>()),
      reason:
          'idevicesyslog es opcional: ofrecer el botón sin comprobarlo es '
          'ofrecer uno que falla al tocarlo',
    );
  });

  test('entrega las líneas que se pueden leer, y descarta el resto', () async {
    final fuente = conUn(
      await guionDe(r'''
echo "--------- beginning of main"
echo "09-03 10:00:00.123  1234  1256 I ActivityManager: arrancó"
echo "una línea que no es nada"
echo "09-03 10:00:01.000  9876  9876 F libc: Fatal signal 11 (SIGSEGV)"
'''),
    );

    final leidas = await fuente
        .escuchar(plataforma: PlataformaEmulador.android, deviceId: 'x')
        .toList();

    expect(leidas.map((l) => l.texto), [
      'arrancó',
      'Fatal signal 11 (SIGSEGV)',
    ]);
    expect(leidas.last.nivel, NivelDeRegistro.fatal);
  });

  // 🔴 `adb` escribe por `stderr` cosas que no son del dispositivo —«waiting for
  // device», el aviso del daemon—. Mezclarlas las haría pasar por líneas del
  // teléfono; no leerlas llena la tubería y bloquea el proceso, que es lo que se
  // arregló en el PR de los procesos colgados.
  test('lo de stderr no se cuela, y tampoco atasca', () async {
    final fuente = conUn(
      await guionDe(r'''
i=0
while [ $i -lt 3000 ]; do
  echo "* daemon not running; starting now at tcp:5037" >&2
  i=$((i+1))
done
echo "09-03 10:00:00.123  1  2 I Tag: la única de verdad"
'''),
    );

    final leidas = await fuente
        .escuchar(plataforma: PlataformaEmulador.android, deviceId: 'x')
        .toList()
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => fail('se atascó: stderr no se está drenando'),
        );

    expect(leidas.map((l) => l.texto), ['la única de verdad']);
  });

  // Un `logcat` que sobreviva a la ventana que lo enseñaba es un proceso
  // huérfano escribiendo a nadie.
  test('dejar de escuchar mata el proceso', () async {
    final marca = File('${cajon.path}/sigue-vivo');
    final fuente = conUn(
      await guionDe('''
trap 'exit 0' TERM
echo "09-03 10:00:00.123  1  2 I Tag: primera"
i=0
while [ \$i -lt 200 ]; do
  echo "vivo" >> ${marca.path}
  sleep 0.05
  i=\$((i+1))
done
'''),
    );

    final suscripcion = fuente
        .escuchar(plataforma: PlataformaEmulador.android, deviceId: 'x')
        .listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await suscripcion.cancel();

    final cuandoSeCancelo = marca.existsSync()
        ? marca.readAsLinesSync().length
        : 0;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final despues = marca.existsSync() ? marca.readAsLinesSync().length : 0;

    expect(
      despues,
      cuandoSeCancelo,
      reason: 'siguió escribiendo después de que nadie lo escuchara',
    );
  });
}

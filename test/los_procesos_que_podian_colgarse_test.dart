import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/usecases/el_espejo_del_iphone.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// Dos procesos que podían quedarse colgados, y ninguno lo hacía por su culpa.
///
/// Los dos son la misma trampa por sus dos lados: una tubería que nadie lee. Si
/// el hijo escribe más de lo que cabe en el búfer del sistema —64 KB— se
/// **bloquea escribiendo**, y quien lo espera espera para siempre.
void main() {
  late Directory cajon;

  setUp(() => cajon = Directory.systemTemp.createTempSync('nexus_procesos'));
  tearDown(() => cajon.deleteSync(recursive: true));

  /// Un «git» de mentira: un script que hace lo que le digamos.
  Future<String> guionDe(String cuerpo) async {
    final script = File('${cajon.path}/git-de-mentira.sh');
    script.writeAsStringSync('#!/bin/sh\n$cuerpo\n');
    await Process.run('chmod', ['+x', script.path]);
    return script.path;
  }

  group('un git que escribe por stderr', () {
    // 🔴 El fallo. `hash-object --stdin-paths` recibe todos los archivos sin
    // seguir de golpe —en un repo con `build/` sin ignorar, miles— y git escribe
    // una línea de error por cada ruta que no puede leer. Aquí se reproduce con
    // 200 KB, más de tres veces el búfer.
    test('no se cuelga aunque desborde el búfer de la tubería', () async {
      final git = GitDataSource(
        git: () async => guionDe(r'''
cat > /dev/null
i=0
while [ $i -lt 4000 ]; do
  echo "fatal: no se pudo leer la ruta numero $i, y esta linea es larga a proposito" >&2
  i=$((i+1))
done
echo "el-hash-que-si-importa"
'''),
      );

      final dicho = await git
          .conEntrada(cajon.path, const ['hash-object'], 'una\ndos\n')
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                fail('se colgó: la tubería de stderr no se está drenando'),
          );

      expect(
        dicho,
        'el-hash-que-si-importa',
        reason: 'y lo de stdout tiene que llegar entero, no a medias',
      );
    });

    test('lo que sale por stderr no se cuela en la respuesta', () async {
      final git = GitDataSource(
        git: () async => guionDe('echo "ruido" >&2\necho "la respuesta"'),
      );

      expect(await git.conEntrada(cajon.path, const [], ''), 'la respuesta');
    });

    test('un código distinto de cero sigue siendo null', () async {
      final git = GitDataSource(git: () async => guionDe('echo algo\nexit 1'));

      expect(await git.conEntrada(cajon.path, const [], ''), isNull);
    });
  });

  // Drenar arregla el búfer lleno, no un git que se quede pensando. `correr()`
  // ya tenía plazo y esto no.
  test('un git que no termina nunca se corta por el plazo', () async {
    final git = GitDataSource(git: () async => guionDe('sleep 60'));

    final dicho = await git
        .conEntrada(
          cajon.path,
          const [],
          '',
          limite: const Duration(milliseconds: 300),
        )
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('el plazo no cortó nada'),
        );

    expect(dicho, isNull);
  });

  // La otra cara de la misma trampa. `verLaPantalla` (scrcpy) y [verElIphone]
  // comparten esta costura y la misma llamada; se prueba por el iPhone porque
  // el de scrcpy no llega aquí si el binario no está instalado, y el CI corre
  // en Linux.
  test('lo que se abre y no se vuelve a mirar se abre suelto', () async {
    ProcessStartMode? conQueModo;
    final fuente = EmuladoresDataSource(
      abrirSuelto: (ejecutable, argumentos, {required modo, entorno}) async {
        conQueModo = modo;
      },
    );

    final problema = await fuente.verElIphone(ComoVerElIphone.duplicado);

    expect(problema, isNull);
    expect(
      conQueModo,
      ProcessStartMode.detached,
      reason:
          'con el modo por defecto Dart abre tres tuberías que nadie lee, y '
          'scrcpy —que vive horas y escribe avisos— se bloquea al llenarlas',
    );
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// No se abre un PR sobre un gate que no lo cubre.
///
/// **Hasta aquí el gate era información.** La barra decía verde o rojo y no pasaba nada;
/// esto es lo que lo convierte en una puerta, y por eso se prueba ejecutando el hook de
/// verdad sobre un repositorio de verdad: leer su código no demuestra que deniegue.
///
/// Solo el PR, y esa es la decisión que hay detrás de la mitad de estas pruebas: un push
/// queda en una rama y no le cuesta nada a nadie; un PR entra en la cola de otra persona,
/// que lo va a leer dando por hecho que las pruebas pasaron.
void main() {
  late Directory repo;
  late Directory cuenta;
  const fuente = GateDelRepoDataSource();
  const git = GitDataSource();
  final hook = File('assets/hooks/frenar_publicacion.py').absolute.path;

  Future<String> enElRepo(List<String> args) async {
    final hecho = await Process.run(
      'git',
      ['-C', repo.path, ...args],
      environment: {'GIT_CONFIG_GLOBAL': '/dev/null'},
    );
    expect(hecho.exitCode, 0, reason: '${args.join(' ')}: ${hecho.stderr}');
    return (hecho.stdout as String).trim();
  }

  setUp(() async {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
    await enElRepo(['init', '-b', 'develop']);
    await enElRepo(['config', 'user.email', 'nadie@ejemplo.test']);
    await enElRepo(['config', 'user.name', 'Nadie']);
    File('${repo.path}/algo.txt').writeAsStringSync('uno\n');
    File('${repo.path}/.nexus-pruebas').writeAsStringSync('exit 0\n');
    await enElRepo(['add', '.']);
    await enElRepo(['commit', '-m', 'primero']);
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  /// Lo que el hook contesta a un comando: el motivo de la denegación, el contexto que
  /// inyecta, o nada si lo deja pasar en silencio.
  Future<({String? denegado, String? contexto})> alCorrer(
    String comando, {
    String? desde,
  }) async {
    final cwd = desde ?? repo.path;
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: cwd,
      environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': cwd,
        'tool_name': 'Bash',
        'tool_input': {'command': comando},
      }),
    );
    await proceso.stdin.close();
    final texto = await proceso.stdout.transform(utf8.decoder).join();
    await proceso.exitCode;
    if (texto.trim().isEmpty) return (denegado: null, contexto: null);
    final salida = jsonDecode(texto)['hookSpecificOutput'] as Map;
    return (
      denegado: salida['permissionDecision'] == 'deny'
          ? salida['permissionDecisionReason'] as String?
          : null,
      contexto: salida['additionalContext'] as String?,
    );
  }

  /// Corre el gate en la rama en la que esté el repo, que es la que va a mirar el hook.
  Future<GateDelRepo> correrElGate({String comando = 'exit 0'}) async {
    File('${repo.path}/.nexus-pruebas').writeAsStringSync('$comando\n');
    final rama = (await git.read(repo.path))!.branch;
    return fuente.correr(
      cuenta.path,
      await fuente.leer(cuenta.path, repo.path, rama: rama),
      huella: await git.huellaDelArbol(repo.path),
    );
  }

  group('qué comandos mira', () {
    test('el PR se frena', () async {
      expect((await alCorrer('gh pr create --fill')).denegado, isNotNull);
    });

    test('el push no', () async {
      // La decisión de fondo: un push queda en una rama. Frenarlo sería fricción sin
      // destinatario, y la primera que alguien desactivaría.
      expect((await alCorrer('git push -u origin develop')).denegado, isNull);
    });

    test('ni ningún otro comando', () async {
      expect((await alCorrer('flutter test')).denegado, isNull);
      expect((await alCorrer('gh pr list')).denegado, isNull);
      expect((await alCorrer('gh pr view 12')).denegado, isNull);
    });

    test(
      'se ve dentro de una cadena, que es como las escribe el modelo',
      () async {
        expect(
          (await alCorrer(
            'git push -u origin develop && gh pr create --fill',
          )).denegado,
          isNotNull,
        );
      },
    );

    test('pero nombrarlo en un texto no frena nada', () async {
      // Un mensaje de commit o un `echo` que mencione el comando no puede parar el
      // trabajo: se mira el programa que se ejecuta, no la cadena entera.
      expect(
        (await alCorrer('echo "luego toca gh pr create"')).denegado,
        isNull,
      );
      expect(
        (await alCorrer('git commit -m "prepara el gh pr create"')).denegado,
        isNull,
      );
    });
  });

  test('sin .nexus-pruebas el hook no existe', () async {
    File('${repo.path}/.nexus-pruebas').deleteSync();
    // Vive en la cuenta, así que corre en todas las carpetas: si actuara por defecto,
    // instalarlo dejaría media máquina sin poder abrir un PR.
    expect((await alCorrer('gh pr create --fill')).denegado, isNull);
  });

  group('qué deja pasar', () {
    test('verde y recién corrido: pasa sin decir nada', () async {
      await correrElGate();
      final respuesta = await alCorrer('gh pr create --fill');
      expect(respuesta.denegado, isNull);
      expect(respuesta.contexto, isNull);
    });

    test('sin correr: deniega, y no ofrece salida', () async {
      final motivo = (await alCorrer('gh pr create --fill')).denegado;
      expect(motivo, isNotNull);
      // No hay nada que justificar: hay algo que hacer, y decirlo así ahorra la
      // conversación de intentar escribir un motivo que no se va a aceptar.
      expect(motivo, contains('no se ha corrido'));
    });

    test('rojo: deniega, y un motivo no lo abre', () async {
      await correrElGate(comando: 'exit 1');
      final motivo = (await alCorrer('gh pr create --fill')).denegado;
      expect(motivo, contains('rojo'));

      await fuente.publicarIgual(
        cuenta.path,
        await fuente.leer(cuenta.path, repo.path, rama: 'develop'),
        motivo: 'es que corre prisa',
        huella: await git.huellaDelArbol(repo.path),
      );

      // Un rojo no es una caducidad que se pueda justificar: es una respuesta.
      expect(
        (await alCorrer('gh pr create --fill')).denegado,
        contains('rojo'),
      );
    });

    test(
      'verde sobre un árbol anterior: deniega y dice por dónde salir',
      () async {
        await correrElGate();
        File('${repo.path}/algo.txt').writeAsStringSync('uno\ndos\n');

        final motivo = (await alCorrer('gh pr create --fill')).denegado;
        expect(motivo, contains('árbol anterior'));
        expect(motivo, contains('motivo'));
      },
    );

    test('desde un subdirectorio se decide igual', () async {
      final dentro = Directory('${repo.path}/lib')..createSync();
      await correrElGate();
      expect(
        (await alCorrer('gh pr create --fill', desde: dentro.path)).denegado,
        isNull,
      );
    });

    test('el gate de otra rama no vale para esta', () async {
      await correrElGate();
      await enElRepo(['switch', '-c', 'feat/otra']);
      expect(
        (await alCorrer('gh pr create --fill')).denegado,
        contains('no se ha corrido'),
      );
    });
  });

  group('publicar igual', () {
    Future<void> conElArbolTocado() async {
      await correrElGate();
      File('${repo.path}/algo.txt').writeAsStringSync('uno\ndos\n');
    }

    test('con el motivo escrito pasa, y el motivo viaja al PR', () async {
      await conElArbolTocado();
      await fuente.publicarIgual(
        cuenta.path,
        await fuente.leer(cuenta.path, repo.path, rama: 'develop'),
        motivo: 'lo posterior al gate es un cambio de copy',
        huella: await git.huellaDelArbol(repo.path),
      );

      final respuesta = await alCorrer('gh pr create --fill');
      expect(respuesta.denegado, isNull);
      // El destinatario de esa justificación no es quien la escribe: es quien va a
      // revisar, y tiene que saber que el gate no cubre parte de lo que está leyendo.
      expect(respuesta.contexto, contains('cambio de copy'));
      expect(respuesta.contexto, contains('cuerpo del PR'));
    });

    test('y deja de valer en cuanto se vuelve a tocar el árbol', () async {
      await conElArbolTocado();
      await fuente.publicarIgual(
        cuenta.path,
        await fuente.leer(cuenta.path, repo.path, rama: 'develop'),
        motivo: 'lo posterior al gate es un cambio de copy',
        huella: await git.huellaDelArbol(repo.path),
      );

      File('${repo.path}/otra-cosa.dart').writeAsStringSync('void main() {}\n');

      // Si el permiso no caducara, escribirlo una vez dejaría el freno abierto para el
      // resto de la tarea — y entonces no justifica nada concreto, solo apaga la puerta.
      expect((await alCorrer('gh pr create --fill')).denegado, isNotNull);
    });

    test('un motivo en blanco no se guarda', () async {
      await conElArbolTocado();
      final antes = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
      final despues = await fuente.publicarIgual(
        cuenta.path,
        antes,
        motivo: '   ',
        huella: await git.huellaDelArbol(repo.path),
      );

      expect(despues.aunque, isNull);
      expect((await alCorrer('gh pr create --fill')).denegado, isNotNull);
    });

    test('correr el gate otra vez se lleva el motivo por delante', () async {
      await conElArbolTocado();
      await fuente.publicarIgual(
        cuenta.path,
        await fuente.leer(cuenta.path, repo.path, rama: 'develop'),
        motivo: 'lo posterior al gate es un cambio de copy',
        huella: await git.huellaDelArbol(repo.path),
      );

      await correrElGate();

      // Una medición nueva deja sin sentido la justificación de la anterior.
      final leido = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
      expect(leido.aunque, isNull);
    });
  });

  group('un fallo propio no puede bloquear el trabajo', () {
    test(
      'con basura por la entrada, sale con éxito y sin decir nada',
      () async {
        final proceso = await Process.start('python3', [
          hook,
        ], workingDirectory: repo.path);
        proceso.stdin.write('no es json');
        await proceso.stdin.close();
        final texto = await proceso.stdout.transform(utf8.decoder).join();
        expect(await proceso.exitCode, 0);
        expect(texto.trim(), isEmpty);
      },
    );

    test('con el estado guardado corrupto, se deniega por prudencia', () async {
      await correrElGate();
      Directory('${cuenta.path}/nexus-pruebas')
          .listSync()
          .whereType<File>()
          .single
          .writeAsStringSync('esto no es json');

      // **Aquí sí se deniega**, y es la diferencia con el hook del plan: no poder leer si
      // el gate pasó no se parece a que haya pasado, y lo que está al otro lado es el
      // tiempo de quien revisa. Abrir el PR es lo irreversible.
      expect((await alCorrer('gh pr create --fill')).denegado, isNotNull);
    });
  });

  group('la huella la calculan dos lenguajes y tiene que salir igual', () {
    /// La `_huella` del hook, llamada directamente. Comparar los dos resultados es lo
    /// único que sostiene el contrato: no comparten una línea de código, y si se separan
    /// el freno deniega para siempre sin que nada explique por qué.
    Future<String> laDelHook() async {
      final hecho = await Process.run('python3', [
        '-c',
        "import sys; sys.path.insert(0, 'assets/hooks'); "
            'import frenar_publicacion as f; print(f._huella(sys.argv[1]))',
        repo.path,
      ]);
      expect(hecho.exitCode, 0, reason: hecho.stderr.toString());
      return (hecho.stdout as String).trim();
    }

    Future<void> coinciden(String cuando) async {
      expect(
        await git.huellaDelArbol(repo.path),
        await laDelHook(),
        reason: 'los dos lados calculan distinto $cuando',
      );
    }

    test('con el árbol limpio', () => coinciden('con el árbol limpio'));

    test('y con el árbol sucio da lo mismo dos veces seguidas', () async {
      // **El fallo que esto cierra.** La primera versión usaba `git stash create`, que
      // fabrica un commit — y el hash de un commit lleva la hora dentro. Con el árbol
      // sucio daba un valor distinto cada segundo, así que el verde caducaba solo y los
      // dos lenguajes nunca coincidían. No fallaba siempre: fallaba a veces, que es peor.
      File('${repo.path}/algo.txt').writeAsStringSync('uno\ndos\n');
      File('${repo.path}/nuevo.dart').writeAsStringSync('void main() {}\n');

      final primera = await git.huellaDelArbol(repo.path);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(await git.huellaDelArbol(repo.path), primera);
      expect(await laDelHook(), primera);
    });

    test('con un archivo seguido tocado', () async {
      File('${repo.path}/algo.txt').writeAsStringSync('uno\ndos\n');
      await coinciden('con un cambio sin commitear');
    });

    test('con un archivo nuevo sin añadir', () async {
      File('${repo.path}/nuevo.dart').writeAsStringSync('void main() {}\n');
      await coinciden('con un archivo sin seguir');
    });

    test('y cambia al editar ese archivo sin añadir', () async {
      final nuevo = File('${repo.path}/nuevo.dart')
        ..writeAsStringSync('void main() {}\n');
      final antes = await git.huellaDelArbol(repo.path);

      // Por esto se hashea el contenido y no solo el nombre: si no, escribir un archivo
      // nuevo y luego llenarlo dejaría el verde cubriendo algo que nadie vio.
      nuevo.writeAsStringSync('void main() { print("otra cosa"); }\n');

      expect(await git.huellaDelArbol(repo.path), isNot(antes));
      await coinciden('tras editar un archivo sin seguir');
    });

    test('con varios sin añadir a la vez', () async {
      File('${repo.path}/a.dart').writeAsStringSync('a\n');
      File('${repo.path}/b.dart').writeAsStringSync('b\n');
      File('${repo.path}/lib/c.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('c\n');
      await coinciden('con varios archivos sin seguir');
    });
  });

  test('la rama se resuelve igual que en el hook del plan', () async {
    // Tres implementaciones de la misma regla —la app en Dart y dos ganchos en Python—
    // que no comparten código. Si se separan, uno guarda bajo un nombre y otro busca
    // otro: el freno deniega para siempre y el motivo es invisible.
    await enElRepo(['switch', '-c', 'feat/con/barras']);
    await correrElGate();

    expect((await git.read(repo.path))!.branch, 'feat/con/barras');
    expect((await alCorrer('gh pr create --fill')).denegado, isNull);
  });
}

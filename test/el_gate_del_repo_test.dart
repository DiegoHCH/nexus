import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// El gate del repositorio: lo que declara, cómo corre y cuánto dura su verde.
///
/// **Lo que se prueba aquí es que «verde» signifique algo.** Un gate es útil solo mientras
/// su verde sea difícil de conseguir: si se puede afirmar a mano, si sobrevive a los
/// cambios que vinieron después, o si se pone verde corriendo la mitad de lo declarado,
/// entonces no mide nada y encima da confianza — que es peor que no tenerlo.
void main() {
  late Directory repo;
  late Directory cuenta;
  const fuente = GateDelRepoDataSource();
  const git = GitDataSource();

  setUp(() {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  void declarar(String contenido) =>
      File('${repo.path}/.nexus-pruebas').writeAsStringSync(contenido);

  Future<GateDelRepo> gate({String? rama}) =>
      fuente.leer(cuenta.path, repo.path, rama: rama);

  Future<GateDelRepo> correr({String? rama, String? huella}) async =>
      fuente.correr(cuenta.path, await gate(rama: rama), huella: huella);

  group('lo que el repo declara', () {
    test('sin archivo no hay gate, y no se inventa uno', () async {
      // Igual que las reglas por capa: el mecanismo está siempre y lo enciende el
      // proyecto. Adivinar el comando —«parece Flutter, será flutter test»— convertiría
      // esto en algo que hace cosas en repos que no lo pidieron.
      expect((await gate()).comando, isNull);
    });

    test('se saltan comentarios y líneas en blanco', () async {
      declarar('# lo que corre antes de publicar\n\n  make check  \n');
      expect((await gate()).comando, 'make check');
    });

    test('con varias líneas corre la primera y lo dice', () async {
      // Callarlo sería lo peor: quien escribió tres esperaba tres, y se enteraría por un
      // verde que no cubría dos tercios de lo que creía haber comprobado.
      declarar('flutter analyze\nflutter test\n');
      final leido = await gate();
      expect(leido.comando, 'flutter analyze');
      expect(leido.aviso, isNotNull);
      expect(leido.aviso, contains('&&'));
    });

    test('un archivo con solo comentarios es no declarar nada', () async {
      declarar('# todavía no sabemos cuál es\n');
      expect((await gate()).comando, isNull);
      expect((await gate()).aviso, isNull);
    });
  });

  group('correrlo', () {
    test('sale con 0: verde, y queda guardado', () async {
      declarar('exit 0');
      expect((await correr()).resultado, ResultadoDelGate.verde);
      // Guardado, no en memoria: el gate tiene que seguir ahí en la sesión siguiente.
      expect((await gate()).resultado, ResultadoDelGate.verde);
    });

    test('sale con otra cosa: rojo, con lo que imprimió', () async {
      declarar('echo "3 pruebas fallaron" >&2; exit 1');
      final hecho = await correr();
      expect(hecho.resultado, ResultadoDelGate.rojo);
      expect(hecho.salida, contains('3 pruebas fallaron'));
    });

    test('lo declarado corre como una línea de intérprete, con «&&»', () async {
      // Partir el comando por espacios rompería la mitad de los gates reales, que son
      // dos cosas encadenadas. Y el «&&» tiene que **cortar**: si la primera falla, la
      // segunda no puede convertir el rojo en verde.
      declarar('false && echo no debería llegar aquí');
      expect((await correr()).resultado, ResultadoDelGate.rojo);

      declarar('true && exit 0');
      expect((await correr()).resultado, ResultadoDelGate.verde);
    });

    test('corre dentro del repo, no donde esté la app', () async {
      File('${repo.path}/la-senal').writeAsStringSync('aquí');
      declarar('test -f la-senal');
      expect((await correr()).resultado, ResultadoDelGate.verde);
    });

    test('un comando que no existe queda rojo, no revienta', () async {
      declarar('esto-no-es-un-programa-de-verdad');
      final hecho = await correr();
      expect(hecho.resultado, ResultadoDelGate.rojo);
      expect(hecho.salida, isNotEmpty);
    });

    test(
      'de la salida se guarda la cola, que es donde está el resumen',
      () async {
        declarar('for i in \$(seq 1 4000); do echo "linea \$i"; done; exit 1');
        final hecho = await correr();
        expect(
          hecho.salida!.length,
          lessThanOrEqualTo(GateDelRepoDataSource.topeDeSalida),
        );
        expect(hecho.salida, contains('linea 4000'));
        expect(hecho.salida, isNot(contains('linea 1\n')));
      },
    );
  });

  group('el estado es de la rama', () {
    test('lo corrido en una no pone verde la otra', () async {
      declarar('exit 0');
      await correr(rama: 'develop');

      expect((await gate(rama: 'develop')).resultado, ResultadoDelGate.verde);
      // El gate de `develop` no dice nada de tu `feat/…`: es otra tarea y otro código.
      expect(
        (await gate(rama: 'feat/otra')).resultado,
        ResultadoDelGate.sinCorrer,
      );
    });

    test('correr en una rama no borra lo de las demás', () async {
      declarar('exit 0');
      await correr(rama: 'develop');
      declarar('exit 1');
      await correr(rama: 'feat/otra');

      expect((await gate(rama: 'develop')).resultado, ResultadoDelGate.verde);
      expect((await gate(rama: 'feat/otra')).resultado, ResultadoDelGate.rojo);
    });

    test('«corriendo» no se guarda nunca', () async {
      declarar('exit 0');
      await correr(rama: 'develop');
      await fuente.guardar(
        cuenta.path,
        GateDelRepo(
          carpeta: repo.path,
          rama: 'develop',
          resultado: ResultadoDelGate.corriendo,
        ),
      );

      // Un «corriendo» en disco se queda ahí para siempre si la app se cierra a mitad, y
      // entonces la pantalla habla de algo que nadie está haciendo.
      expect(
        (await gate(rama: 'develop')).resultado,
        ResultadoDelGate.sinCorrer,
      );
      // Se busca el archivo que haya en vez de rehacer su nombre: la ruta se guarda
      // resuelta —en macOS `/var` es `/private/var`— y recalcularlo aquí sería probar
      // otra cosa.
      final crudo = Directory(
        '${cuenta.path}/nexus-pruebas',
      ).listSync().whereType<File>().single;
      expect(jsonDecode(crudo.readAsStringSync())['ramas'], isEmpty);
    });
  });

  group('el verde caduca cuando el árbol cambia', () {
    late Directory conGit;

    Future<String> enElRepo(List<String> args) async {
      final hecho = await Process.run(
        'git',
        ['-C', conGit.path, ...args],
        environment: {'GIT_CONFIG_GLOBAL': '/dev/null'},
      );
      expect(hecho.exitCode, 0, reason: '${args.join(' ')}: ${hecho.stderr}');
      return (hecho.stdout as String).trim();
    }

    setUp(() async {
      conGit = Directory.systemTemp.createTempSync('con-git');
      await enElRepo(['init', '-b', 'develop']);
      await enElRepo(['config', 'user.email', 'nadie@ejemplo.test']);
      await enElRepo(['config', 'user.name', 'Nadie']);
      File('${conGit.path}/algo.txt').writeAsStringSync('uno\n');
      File('${conGit.path}/.nexus-pruebas').writeAsStringSync('exit 0\n');
      await enElRepo(['add', '.']);
      await enElRepo(['commit', '-m', 'primero']);
    });

    tearDown(() => conGit.deleteSync(recursive: true));

    test('recién corrido, el verde cubre lo que hay', () async {
      final huella = await git.huellaDelArbol(conGit.path);
      final hecho = await fuente.correr(
        cuenta.path,
        await fuente.leer(cuenta.path, conGit.path, rama: 'develop'),
        huella: huella,
      );

      expect(hecho.resultado, ResultadoDelGate.verde);
      expect(hecho.cubre(await git.huellaDelArbol(conGit.path)), isTrue);
    });

    test('y deja de cubrir en cuanto se toca un archivo', () async {
      await fuente.correr(
        cuenta.path,
        await fuente.leer(cuenta.path, conGit.path, rama: 'develop'),
        huella: await git.huellaDelArbol(conGit.path),
      );

      File('${conGit.path}/algo.txt').writeAsStringSync('uno\ndos\n');

      // Sigue siendo verde —corrió y pasó— pero ya no dice nada de lo que hay ahora. Sin
      // esto bastaría con seguir escribiendo para que un verde valiera para siempre.
      final leido = await fuente.leer(
        cuenta.path,
        conGit.path,
        rama: 'develop',
      );
      expect(leido.resultado, ResultadoDelGate.verde);
      expect(leido.cubre(await git.huellaDelArbol(conGit.path)), isFalse);
    });

    test('un archivo nuevo sin añadir también lo invalida', () async {
      await fuente.correr(
        cuenta.path,
        await fuente.leer(cuenta.path, conGit.path, rama: 'develop'),
        huella: await git.huellaDelArbol(conGit.path),
      );

      // **El caso que casi se escapa.** `git stash create` no incluye lo que git todavía
      // no sigue, así que con la huella hecha solo con él, un archivo nuevo dejaba el
      // verde intacto — y escribir archivos nuevos es justo lo que hace un asistente.
      // Sin añadir a propósito: añadirlo lo metería en el stash y probaría otra cosa.
      File('${conGit.path}/nuevo.dart').writeAsStringSync('void main() {}\n');

      final leido = await fuente.leer(
        cuenta.path,
        conGit.path,
        rama: 'develop',
      );
      expect(leido.cubre(await git.huellaDelArbol(conGit.path)), isFalse);
    });

    test('sin huella no se afirma que cubre', () async {
      // No saber y saber que no se parecen lo bastante: equivocarse al otro lado sería
      // enseñar como comprobado algo que nadie comprobó.
      await fuente.correr(
        cuenta.path,
        await fuente.leer(cuenta.path, conGit.path, rama: 'develop'),
      );
      final leido = await fuente.leer(
        cuenta.path,
        conGit.path,
        rama: 'develop',
      );
      expect(leido.resultado, ResultadoDelGate.verde);
      expect(leido.cubre(await git.huellaDelArbol(conGit.path)), isFalse);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/revision_data_source.dart';
import 'package:nexus/features/workspace/domain/usecases/el_encargo_de_revisar.dart';
import 'package:nexus/features/workspace/domain/usecases/reglas_declaradas.dart';

/// Leer `.nexus-reglas` en Dart, y el encargo de revisar el diff contra la regla de cada
/// capa.
///
/// **Lo que más importa aquí es el emparejado.** La app y el gancho eligen reglas para el
/// mismo archivo y no comparten código: el gancho usa `fnmatch` de Python y esto lo imita.
/// Si se separan, cada uno carga una regla distinta y nada falla — el trabajo sale con
/// media ley del sitio y no hay error que lo diga. Por eso hay una prueba que corre los
/// dos sobre los mismos patrones.
void main() {
  group('leer el archivo', () {
    test('una línea sin flecha es una regla de siempre', () {
      final reglas = ReglasDeclaradas.leer('~/contexto/rules/INDEX.md\n');
      expect(reglas.single.siempre, isTrue);
      expect(reglas.single.ruta, '~/contexto/rules/INDEX.md');
    });

    test('una con flecha es de capa, y no se confunde con una ruta', () {
      // **El fallo que esto cierra.** La app cargaba la línea entera como si fuera una
      // ruta, así que un repo con reglas por capa metía «**/domain/** -> …» en cada
      // encargo con un aviso de que esa regla no existía.
      final reglas = ReglasDeclaradas.leer(
        '**/domain/** -> ~/contexto/rules/dominio.md\n',
      );
      expect(reglas.single.siempre, isFalse);
      expect(reglas.single.patron, '**/domain/**');
      expect(reglas.single.ruta, '~/contexto/rules/dominio.md');
    });

    test('comentarios y líneas en blanco no son reglas', () {
      expect(ReglasDeclaradas.leer('# lo de siempre\n\n   \n'), isEmpty);
    });

    test('media línea no es una regla', () {
      // Sin patrón no se sabe cuándo aplica; sin ruta no hay nada que cargar.
      expect(ReglasDeclaradas.leer('-> ~/algo.md\n'), isEmpty);
      expect(ReglasDeclaradas.leer('**/domain/** ->\n'), isEmpty);
    });

    test('las dos formas conviven en el mismo archivo', () {
      final reglas = ReglasDeclaradas.leer('''
# las de este repo
~/contexto/rules/INDEX.md

**/domain/**        -> ~/contexto/rules/dominio.md
**/presentation/**  -> ~/contexto/rules/presentacion.md
''');
      expect(reglas, hasLength(3));
      expect(reglas.where((r) => r.siempre), hasLength(1));
    });
  });

  group('el emparejado imita a fnmatch, no a git', () {
    // En `fnmatch` un `*` **atraviesa las barras**. Copiar la semántica de `.gitignore`
    // aquí habría hecho que la app y el gancho eligieran reglas distintas para el mismo
    // archivo, en silencio.
    const casos = <(String, String, bool)>[
      ('**/domain/**', 'lib/features/auth/domain/user.dart', true),
      ('**/domain/**', 'lib/features/auth/presentation/page.dart', false),
      ('*/domain/*', 'lib/features/auth/domain/user.dart', true),
      ('lib/*.dart', 'lib/main.dart', true),
      ('lib/*.dart', 'lib/core/main.dart', true),
      ('*.dart', 'lib/main.dart', true),
      ('*.md', 'README.md', true),
      ('*.md', 'README.txt', false),
      ('lib/?ain.dart', 'lib/main.dart', true),
      ('lib/[mn]ain.dart', 'lib/main.dart', true),
      ('lib/[!m]ain.dart', 'lib/main.dart', false),
      ('**/test/**', 'test/algo_test.dart', false),
      ('**/*_test.dart', 'test/algo_test.dart', true),
    ];

    for (final (patron, ruta, esperado) in casos) {
      test('«$patron» ${esperado ? 'encaja' : 'no encaja'} con «$ruta»', () {
        expect(ReglasDeclaradas.encaja(patron, ruta), esperado);
      });
    }

    test('y dice lo mismo que el fnmatch de Python', () async {
      // La prueba que sostiene el contrato: los dos lados sobre los mismos casos.
      final entrada = casos.map((caso) => '${caso.$1}\t${caso.$2}').join('\n');
      final proceso = await Process.start('python3', [
        '-c',
        'import sys, fnmatch\n'
            'for linea in sys.stdin.read().splitlines():\n'
            '    patron, ruta = linea.split("\\t")\n'
            '    print("1" if fnmatch.fnmatch(ruta, patron) else "0")\n',
      ]);
      proceso.stdin.write(entrada);
      await proceso.stdin.close();
      final salida = await proceso.stdout.transform(utf8.decoder).join();
      expect(await proceso.exitCode, 0);

      final dePython = salida.trim().split('\n');
      for (var i = 0; i < casos.length; i++) {
        expect(
          ReglasDeclaradas.encaja(casos[i].$1, casos[i].$2) ? '1' : '0',
          dePython[i],
          reason:
              'Dart y Python no coinciden en «${casos[i].$1}» contra '
              '«${casos[i].$2}»',
        );
      }
    });
  });

  group('qué reglas aplican', () {
    final reglas = ReglasDeclaradas.leer('''
~/siempre.md
**/domain/**        -> ~/dominio.md
**/presentation/**  -> ~/presentacion.md
''');

    test('solo las de las capas que se tocan', () {
      expect(
        ReglasDeclaradas.paraArchivos(reglas, [
          'lib/features/auth/domain/user.dart',
        ]),
        ['~/dominio.md'],
      );
    });

    test('las de siempre no entran: esas ya viajan por su cuenta', () {
      // Repetirlas aquí sería mandarlas dos veces en el mismo encargo.
      expect(
        ReglasDeclaradas.paraArchivos(reglas, ['cualquier/cosa.dart']),
        isEmpty,
      );
    });

    test('una regla no se repite por tocar dos archivos suyos', () {
      expect(
        ReglasDeclaradas.paraArchivos(reglas, [
          'lib/a/domain/uno.dart',
          'lib/b/domain/dos.dart',
        ]),
        ['~/dominio.md'],
      );
    });
  });

  group('el encargo', () {
    final reglas = ReglasDeclaradas.leer(
      '**/domain/** -> ~/dominio.md\n**/presentation/** -> ~/presentacion.md\n',
    );

    test('sin archivos tocados no hay nada que pedir', () {
      expect(
        ElEncargoDeRevisar.texto(archivos: const [], reglas: reglas),
        isNull,
      );
    });

    test('sin reglas de capa que encajen, tampoco', () {
      // Sin regla que leer, esto no añade nada a lo que ya hace el gate — y mandar el
      // encargo sería gastar un turno para que conteste que no había nada.
      expect(
        ElEncargoDeRevisar.texto(archivos: const ['README.md'], reglas: reglas),
        isNull,
      );
    });

    test('lleva los archivos, las reglas y por qué cada una', () {
      final texto = ElEncargoDeRevisar.texto(
        archivos: const [
          'lib/features/auth/domain/user.dart',
          'lib/features/auth/presentation/login_page.dart',
        ],
        reglas: reglas,
        rama: 'feat/login',
      )!;

      expect(texto, contains('feat/login'));
      expect(texto, contains('lib/features/auth/domain/user.dart'));
      expect(texto, contains('~/dominio.md'));
      expect(texto, contains('~/presentacion.md'));
      // El «por qué» de cada regla: sin él, quien lea el encargo no sabe qué archivo la
      // trajo y tiene que deducirlo.
      expect(texto, contains('por: lib/features/auth/domain/user.dart'));
    });

    test('no pide un veredicto ni deja correr nada', () {
      final texto = ElEncargoDeRevisar.texto(
        archivos: const ['lib/a/domain/x.dart'],
        reglas: reglas,
      )!;
      // El gate mide y esto lee. Un «pasa / no pasa» de un modelo acabaría leyéndose como
      // un segundo gate, y no lo es.
      expect(texto, contains('No corras las pruebas'));
      expect(texto, contains('ni cambies nada'));
    });

    test('con muchos archivos recorta y lo dice', () {
      final muchos = [
        for (var i = 0; i < 60; i++) 'lib/f$i/domain/algo$i.dart',
      ];
      final texto = ElEncargoDeRevisar.texto(archivos: muchos, reglas: reglas)!;

      expect(texto, contains('(60)'));
      // Listar treinta de sesenta sin avisar se lee como «esto es todo lo que hay».
      expect(texto, contains('y 20 más'));
    });
  });

  group('la marca de la revisión', () {
    late Directory cuenta;
    late Directory repo;
    const fuente = RevisionDataSource();

    setUp(() {
      cuenta = Directory.systemTemp.createTempSync('cuenta');
      repo = Directory.systemTemp.createTempSync('proyecto');
    });

    tearDown(() {
      cuenta.deleteSync(recursive: true);
      repo.deleteSync(recursive: true);
    });

    test('se anota con su huella y su cuenta de archivos', () async {
      await fuente.anotar(
        cuenta.path,
        repo.path,
        rama: 'develop',
        huella: 'abc',
        archivos: 3,
      );

      final leida = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
      expect(leida!.archivos, 3);
      expect(leida.cubre('abc'), isTrue);
      expect(leida.cubre('otra'), isFalse);
    });

    test('la última manda: no se apilan', () async {
      // Al contrario que los cierres, aquí el historial no dice nada — lo que importa es
      // si la de ahora cubre el código de ahora.
      await fuente.anotar(cuenta.path, repo.path, rama: 'develop', huella: 'a');
      await fuente.anotar(cuenta.path, repo.path, rama: 'develop', huella: 'b');

      final leida = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
      expect(leida!.cubre('b'), isTrue);
    });

    test('cada rama la suya', () async {
      await fuente.anotar(cuenta.path, repo.path, rama: 'develop', huella: 'a');
      expect(
        await fuente.leer(cuenta.path, repo.path, rama: 'feat/otra'),
        isNull,
      );
    });
  });

  group('los archivos tocados', () {
    late Directory repo;
    const git = GitDataSource();

    Future<void> enElRepo(List<String> args) async {
      final hecho = await Process.run(
        'git',
        ['-C', repo.path, ...args],
        environment: {'GIT_CONFIG_GLOBAL': '/dev/null'},
      );
      expect(hecho.exitCode, 0, reason: '${args.join(' ')}: ${hecho.stderr}');
    }

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('proyecto');
      await enElRepo(['init', '-b', 'develop']);
      await enElRepo(['config', 'user.email', 'nadie@ejemplo.test']);
      await enElRepo(['config', 'user.name', 'Nadie']);
      File('${repo.path}/algo.txt').writeAsStringSync('uno\n');
      await enElRepo(['add', '.']);
      await enElRepo(['commit', '-m', 'primero']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('con el árbol limpio, ninguno', () async {
      expect(await git.archivosTocados(repo.path), isEmpty);
    });

    test('lo cambiado y lo nuevo sin añadir, en rutas relativas', () async {
      File('${repo.path}/algo.txt').writeAsStringSync('uno\ndos\n');
      File('${repo.path}/lib/nuevo.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}\n');

      // Relativas porque es lo que se compara con los patrones: quien escribe
      // `**/domain/**` no sabe dónde está clonado el proyecto. Y el archivo nuevo entra,
      // que es justo el que suele haber que revisar.
      expect(await git.archivosTocados(repo.path), [
        'algo.txt',
        'lib/nuevo.dart',
      ]);
    });
  });
}

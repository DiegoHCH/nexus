import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/data/datasources/repo_de_pruebas_data_source.dart';

/// **El clon del repo de pruebas, sin clonar nada.**
///
/// 🔴 Punto 3 del repaso: este archivo estaba al **15,8 % de cobertura** de 114
/// líneas, y no por descuido — corría `git` y `gh` de verdad, así que probarlo
/// pedía red, credenciales y un repo del trabajo. Lo que quedaba fuera es **la
/// secuencia de publicar**: rama, escribir, `add`, commit, push, PR y la vuelta
/// a la base. Ahí un comando en el orden equivocado no falla, hace otra cosa —
/// y «otra cosa» aquí es commitear en `main` de un repo de otro equipo.
///
/// Escribiéndolas salió un fallo real, el de «commits sin publicar»: está
/// abajo, con su historia.

/// Un `git` de mentira: se apunta cada comando **con la carpeta en la que se
/// corrió**, porque un `checkout` en el sitio equivocado cambia de rama en otro
/// repositorio.
class _Git {
  _Git({
    this.binarios = const {'git': '/usr/bin/git', 'gh': '/opt/homebrew/bin/gh'},
    this.respuestas = const {},
  });

  final Map<String, String?> binarios;

  /// De un trozo de los argumentos a lo que contesta. Gana el trozo más largo.
  final Map<String, ProcessResult> respuestas;

  final pedidos = <({String binario, String args, String? en})>[];

  Future<String?> buscar(String nombre, List<String> candidatos) async =>
      binarios[nombre];

  Future<ProcessResult> correr(
    String ejecutable,
    List<String> argumentos, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    final args = argumentos.join(' ');
    pedidos.add((
      binario: ejecutable.split('/').last,
      args: args,
      en: workingDirectory,
    ));
    final claves = respuestas.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final clave in claves) {
      if (args.contains(clave)) return respuestas[clave]!;
    }
    return ProcessResult(0, 0, '', '');
  }

  /// Los comandos tal como se pidieron, en orden.
  List<String> get orden => [for (final p in pedidos) '${p.binario} ${p.args}'];

  bool sePidio(String trozo) => orden.any((o) => o.contains(trozo));

  String? dondeSeCorrio(String trozo) =>
      pedidos.firstWhere((p) => p.args.contains(trozo)).en;
}

ProcessResult _falla(String error) => ProcessResult(0, 1, '', error);

void main() {
  late Directory soporte;
  late String clon;

  setUp(() {
    soporte = Directory.systemTemp.createTempSync('repo-de-pruebas');
    clon = '${soporte.path}/repos/global66--automated-test';
  });
  tearDown(() => soporte.deleteSync(recursive: true));

  RepoDePruebasDataSource conEl(_Git git) =>
      RepoDePruebasDataSource(correr: git.correr, buscar: git.buscar);

  /// Deja la carpeta con cara de repo, que es lo que mira `asegurar`.
  void yaEsUnRepo() => Directory('$clon/.git').createSync(recursive: true);

  group('dejar el clon listo', () {
    test('sin git no se intenta nada', () async {
      final git = _Git(binarios: const {'git': null});

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.fallo);
      expect(r.sirve, isFalse);
      expect(git.pedidos, isEmpty);
    });

    test('si no está, se clona la rama pedida en su carpeta', () async {
      final git = _Git();

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.clonado);
      expect(r.clon, clon);
      expect(
        git.orden.single,
        'git clone --branch main '
        'https://github.com/global66/automated-test.git $clon',
      );
      // 🔴 **El clone se corre en la carpeta padre**, que es la única que existe
      // todavía: lanzarlo dentro del destino que aún no está es un
      // `ProcessException` y no un fallo de git.
      expect(git.dondeSeCorrio('clone'), '${soporte.path}/repos');
    });

    // Una carpeta que existe y no es un repo es basura de un clonado a medias:
    // reintentar sobre ella deja a git quejándose de un destino no vacío.
    test('una carpeta a medias se borra antes de reintentar', () async {
      final aMedias = File('$clon/a-medias.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('basura');
      final git = _Git();

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(aMedias.existsSync(), isFalse);
      expect(r.como, ComoFueLaSync.clonado);
    });

    test('si el clone falla, se dice la última línea de git', () async {
      final git = _Git(
        respuestas: {
          'clone': _falla(
            'Cloning into ...\nfatal: could not read Username for '
            "'https://github.com': terminal prompts disabled\n",
          ),
        },
      );

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.fallo);
      expect(r.detalle, contains('terminal prompts disabled'));
      expect(r.sirve, isFalse);
    });

    test('si ya está y está limpio, se pone al día con el remoto', () async {
      yaEsUnRepo();
      final git = _Git();

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.aldia);
      expect(r.detalle, 'Al día con origin/main.');
      expect(git.orden, [
        'git status --porcelain',
        'git log --branches --not --remotes --format=%H -1',
        'git fetch origin main',
        'git checkout main',
        'git reset --hard origin/main',
      ]);
      // Todo dentro del clon: el `reset --hard` en otra carpeta borra trabajo
      // de verdad.
      expect(git.pedidos.every((p) => p.en == clon), isTrue);
    });

    test('con cambios sin commitear, no se toca', () async {
      yaEsUnRepo();
      final git = _Git(
        respuestas: {
          'status': ProcessResult(0, 0, ' M flows/15-login.yaml', ''),
        },
      );

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.sucio);
      expect(r.sirve, isTrue, reason: 'el clon se puede usar igual');
      expect(
        git.sePidio('reset --hard'),
        isFalse,
        reason: 'lo que no se puede hacer es tirar lo que hay',
      );
    });

    // 🔴 **El fallo que salió escribiendo esto.** La cabecera de la clase promete
    // que «un push que falló y dejó cosas sin publicar se detecta y se respeta»,
    // y era falso: `publicar` commitea antes de empujar, así que con el push
    // caído el árbol queda **limpio** —`status` no dice nada— y esto contestaba
    // «Al día con origin/main» justo antes de un `reset --hard` que se llevaba
    // la rama por delante.
    test('y con un commit sin publicar, tampoco', () async {
      yaEsUnRepo();
      final git = _Git(
        respuestas: {
          'log --branches --not --remotes': ProcessResult(
            0,
            0,
            '9f0c1e4a2b\n',
            '',
          ),
        },
      );

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.sucio);
      expect(r.detalle, contains('commits sin publicar'));
      expect(git.sePidio('reset --hard'), isFalse);
    });

    // Sin red se sigue trabajando con lo que hay: los flows de ayer corren
    // igual, y decir «no se pudo actualizar» es mejor que no dejar correr.
    test('sin red se usa la copia que ya estaba', () async {
      yaEsUnRepo();
      final git = _Git(
        respuestas: {'fetch': _falla('fatal: unable to access ...: timed out')},
      );

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.aldia);
      expect(r.sirve, isTrue);
      expect(r.detalle, contains('la copia que ya estaba'));
      expect(git.sePidio('reset --hard'), isFalse);
    });

    test('si el reset falla, es un fallo y se dice por qué', () async {
      yaEsUnRepo();
      final git = _Git(
        respuestas: {'reset': _falla('error: Your local changes ...\n')},
      );

      final r = await conEl(git).asegurar(soporte: soporte.path);

      expect(r.como, ComoFueLaSync.fallo);
      expect(r.detalle, contains('Your local changes'));
    });

    test('el slug manda en la carpeta y en la URL', () async {
      final git = _Git();

      final r = await conEl(
        git,
      ).asegurar(soporte: soporte.path, slug: 'otra/cosa', rama: 'develop');

      expect(r.clon, '${soporte.path}/repos/otra--cosa');
      expect(git.orden.single, contains('--branch develop'));
      expect(git.orden.single, contains('https://github.com/otra/cosa.git'));
    });
  });

  group('publicar un flow', () {
    final cuando = DateTime(2026, 9, 9, 18, 30);
    const contenido = 'appId: com.global66.app\n---\n- launchApp\n';

    Future<Publicacion> publicando(
      _Git git, {
      String ruta = 'flows/99-nueva.yaml',
    }) => conEl(git).publicar(
      clon: clon,
      ruta: ruta,
      contenido: contenido,
      mensaje: 'test: nueva prueba',
      cuando: cuando,
    );

    test('rama, archivo, commit, push, PR y vuelta a la base', () async {
      final git = _Git(
        respuestas: {
          'pr create': ProcessResult(
            0,
            0,
            'https://github.com/global66/automated-test/pull/42\n',
            '',
          ),
        },
      );

      final r = await publicando(git);

      expect(r.ok, isTrue);
      expect(r.rama, 'test/99-nueva-202609091830');
      expect(r.url, 'https://github.com/global66/automated-test/pull/42');
      expect(git.orden, [
        'git checkout main',
        'git checkout -b test/99-nueva-202609091830',
        // `--` separa la ruta de cualquier cosa que git pudiera leer como
        // opción.
        'git add -- flows/99-nueva.yaml',
        'git commit -m test: nueva prueba',
        'git push -u origin test/99-nueva-202609091830',
        'gh pr create --base main --title test: nueva prueba --body '
            'Prueba escrita desde Nexus.',
        // 🔴 **La vuelta a la base es lo último y no es cosmética**: dejar el
        // clon en una rama de trabajo hace que la siguiente sincronización la
        // vea y no sepa qué hacer con ella.
        'git checkout main',
      ]);
      expect(File('$clon/flows/99-nueva.yaml').readAsStringSync(), contenido);
    });

    test('sin git no se escribe nada', () async {
      final git = _Git(binarios: const {'git': null});

      final r = await publicando(git);

      expect(r.ok, isFalse);
      expect(git.pedidos, isEmpty);
      expect(Directory('$clon/flows').existsSync(), isFalse);
    });

    // El push ya se hizo: el trabajo está a salvo en el remoto. Decir «ok» con
    // la rama y sin URL es un estado útil y no una mentira.
    test('sin gh, se publica igual y el PR lo abres tú', () async {
      final git = _Git(binarios: const {'git': '/usr/bin/git', 'gh': null});

      final r = await publicando(git);

      expect(r.ok, isTrue);
      expect(r.url, isEmpty);
      expect(r.detalle, contains('El PR ábrelo tú'));
      expect(r.rama, 'test/99-nueva-202609091830');
    });

    test('si el gh falla, tampoco se pierde el push', () async {
      final git = _Git(
        respuestas: {'pr create': _falla('pull request already exists')},
      );

      final r = await publicando(git);

      expect(r.ok, isTrue);
      expect(r.url, isEmpty);
    });

    // 🔴 **Sin cambios que commitear no es un fallo del sistema**: es que el
    // archivo ya estaba igual, y decirlo con el stderr de git en la cara no
    // ayuda a nadie.
    test('un archivo que ya estaba igual se dice con palabras', () async {
      final git = _Git(
        respuestas: {
          'commit': ProcessResult(
            0,
            1,
            'nothing to commit, working tree clean',
            '',
          ),
        },
      );

      final r = await publicando(git);

      expect(r.ok, isFalse);
      expect(
        r.detalle,
        'El archivo ya estaba igual: no hay nada que publicar.',
      );
      expect(
        git.orden.last,
        'git checkout main',
        reason: 'se deja como estaba',
      );
    });

    test('si no se puede crear la rama, no se escribe el archivo', () async {
      final git = _Git(
        respuestas: {'checkout -b': _falla('fatal: a branch named ... exists')},
      );

      final r = await publicando(git);

      expect(r.ok, isFalse);
      expect(r.detalle, contains('exists'));
      expect(File('$clon/flows/99-nueva.yaml').existsSync(), isFalse);
    });

    test('si el push falla, se queda la rama para reintentar', () async {
      final git = _Git(
        respuestas: {'push': _falla('fatal: Authentication failed')},
      );

      final r = await publicando(git);

      expect(r.ok, isFalse);
      expect(r.rama, 'test/99-nueva-202609091830');
      expect(r.detalle, contains('Authentication failed'));
      // Y **no** se vuelve a la base: el commit vive en esa rama, y es lo que
      // detecta la sincronización siguiente para no pisarlo.
      expect(git.sePidio('pr create'), isFalse);
      expect(git.orden.last, contains('push'));
    });

    test('si falla lo que dice git y no dice nada, se dice eso', () async {
      final git = _Git(respuestas: {'checkout main': _falla('   \n\n')});

      expect((await publicando(git)).detalle, 'Falló y no dijo por qué.');
    });

    // Un stderr de git son diez líneas y la que importa casi siempre es la
    // última; se prefiere corta y entera a larga y cortada en la UI.
    test('y un motivo kilométrico se recorta con puntos suspensivos', () async {
      final git = _Git(
        respuestas: {'checkout main': _falla('fatal: ${'x' * 400}')},
      );

      final detalle = (await publicando(git)).detalle;

      expect(detalle.length, 201);
      expect(detalle, endsWith('…'));
    });

    // El mismo mensaje puede llegar por stderr, y entonces también es «ya
    // estaba igual» y no un error de git.
    test(
      'lo de «nothing to commit» vale por cualquiera de las dos salidas',
      () async {
        final git = _Git(
          respuestas: {
            'commit': ProcessResult(
              0,
              1,
              '',
              'nothing to commit, working tree',
            ),
          },
        );

        expect(
          (await publicando(git)).detalle,
          'El archivo ya estaba igual: no hay nada que publicar.',
        );
      },
    );

    test('si no se puede escribir, se vuelve a la base y se dice', () async {
      // Una carpeta donde tiene que ir el archivo: escribir ahí es
      // `FileSystemException` y no un fallo de git.
      Directory('$clon/flows/99-nueva.yaml').createSync(recursive: true);
      final git = _Git();

      final r = await publicando(git);

      expect(r.ok, isFalse);
      expect(r.detalle, startsWith('No pude escribir el archivo:'));
      expect(git.orden.last, 'git checkout main');
      expect(git.sePidio('commit'), isFalse);
    });

    // Sin hora, la de ahora: la rama lleva fecha porque dos cambios el mismo
    // día son lo normal y una rama repetida hace fallar el `checkout -b` justo
    // después de escribir el archivo.
    test('sin decirle cuándo, la rama sale con la hora de ahora', () async {
      final git = _Git();

      final r = await conEl(git).publicar(
        clon: clon,
        ruta: 'flows/99-nueva.yaml',
        contenido: contenido,
        mensaje: 'test: nueva prueba',
      );

      expect(r.rama, startsWith('test/99-nueva-'));
      expect(r.rama, matches(RegExp(r'^test/99-nueva-\d{12}$')));
    });

    // 🔴 **Sin git en la máquina, `Process.run` lanza y no devuelve.** Es el
    // único camino en el que el fallo llega como excepción y no como código de
    // salida, y el detalle que se enseña es el mensaje del sistema.
    test('si el binario no está donde se dijo, se cuenta su motivo', () async {
      final r =
          await RepoDePruebasDataSource(
            buscar: _Git().buscar,
            correr:
                (
                  ejecutable,
                  argumentos, {
                  workingDirectory,
                  environment,
                  includeParentEnvironment = true,
                }) => throw const ProcessException('git', [
                  'checkout',
                ], 'No such file or directory'),
          ).publicar(
            clon: clon,
            ruta: 'flows/99-nueva.yaml',
            contenido: contenido,
            mensaje: 'test: nueva prueba',
          );

      expect(r.ok, isFalse);
      expect(r.detalle, 'No such file or directory');
    });
  });

  // Lo que hay que mirar para saber qué variables pedirle a Maestro: en este
  // repo las credenciales viven en subflows, no en el flow que se lanza.
  group('el árbol de un flow', () {
    test('trae el flow y lo que arrastra con runFlow', () async {
      File('$clon/flows/15-login.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'appId: com.global66.app\n---\n'
          '- runFlow: commons/setup-authed.yaml\n',
        );
      File('$clon/flows/commons/setup-authed.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('- inputText: \${MAIL}\n');

      final arbol = await conEl(
        _Git(),
      ).arbolDe(clon: clon, ruta: 'flows/15-login.yaml');

      expect(arbol, contains('runFlow: commons/setup-authed.yaml'));
      expect(
        arbol,
        contains('inputText: \${MAIL}'),
        reason: 'el subflow es donde vive la variable que hay que pasar',
      );
    });

    test('y un flow que no está no revienta', () async {
      final arbol = await conEl(
        _Git(),
      ).arbolDe(clon: clon, ruta: 'flows/no-existe.yaml');

      expect(arbol, isNot(contains('runFlow')));
    });
  });
}

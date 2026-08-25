import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El hook que pone delante la regla de la capa del archivo que se va a editar.
///
/// **Se prueba ejecutándolo de verdad**, no leyendo su código. Está escrito en el
/// `python3` que ya trae macOS —para no añadir dependencias a algo que corre en cada
/// edición— y eso lo deja fuera del alcance de una prueba de Dart normal. Lanzarlo con una
/// entrada real es la única forma de que estas afirmaciones valgan algo.
///
/// Lo que cubre es lo que puede romperse en silencio: que inyecte lo que toca, que no
/// inyecte lo que no, y sobre todo que **no impida editar** cuando algo va mal. Un hook
/// que revienta y bloquea la edición sería peor que no tener hook.
void main() {
  late Directory repo;
  final hook = File('tool/hooks/inyectar_reglas.py').absolute.path;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('proyecto');
    File('${repo.path}/reglas/dominio.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('el dominio no conoce la base de datos');
    File('${repo.path}/reglas/presentacion.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('nada de reglas de negocio en el widget');
  });

  tearDown(() => repo.deleteSync(recursive: true));

  void declarar(String contenido) =>
      File('${repo.path}/.nexus-reglas').writeAsStringSync(contenido);

  /// Lo que el hook le pone delante al modelo, o `null` si no dijo nada.
  Future<String?> conEntrada(Object payload) async {
    final proceso = await Process.start('python3', [
      hook,
    ], workingDirectory: repo.path);
    proceso.stdin.write(jsonEncode(payload));
    await proceso.stdin.close();
    final texto = await proceso.stdout.transform(utf8.decoder).join();
    await proceso.exitCode;
    if (texto.trim().isEmpty) return null;
    return jsonDecode(texto)['hookSpecificOutput']['additionalContext']
        as String?;
  }

  Future<String?> alTocar(String ruta) => conEntrada({
    'cwd': repo.path,
    'tool_input': {'file_path': ruta},
  });

  test('inyecta la regla de la capa que se toca, y solo esa', () async {
    declarar('''
**/domain/**        -> reglas/dominio.md
**/presentation/**  -> reglas/presentacion.md
''');

    final dominio = await alTocar('lib/features/auth/domain/login.dart');
    expect(dominio, contains('el dominio no conoce'));
    expect(
      dominio,
      isNot(contains('en el widget')),
      reason: 'inyectó también la regla de otra capa',
    );

    final vista = await alTocar('lib/features/auth/presentation/pagina.dart');
    expect(vista, contains('en el widget'));
    expect(vista, isNot(contains('el dominio no conoce')));
  });

  test('la ruta absoluta encaja igual que la relativa', () async {
    // Un patrón se escribe pensando en el repo, y quien lo escribe no sabe dónde está
    // clonado: si el patrón dependiera de eso, funcionaría en una máquina y no en otra.
    declarar('**/domain/** -> reglas/dominio.md');

    expect(
      await alTocar('${repo.path}/lib/features/auth/domain/x.dart'),
      contains('el dominio no conoce'),
    );
  });

  test('las reglas de siempre no se repiten aquí', () async {
    // Las líneas sin flecha las carga Nexus antes del encargo. Inyectarlas también en
    // cada edición sería mandar lo mismo dos veces y gastar el presupuesto por partida
    // doble.
    declarar('reglas/dominio.md\n');

    expect(await alTocar('lib/features/auth/domain/x.dart'), isNull);
  });

  test('sin archivo declarado, el hook no hace nada', () async {
    // El mecanismo vive en la cuenta y lo activa el repo: en una carpeta que no lo pide,
    // esto tiene que ser invisible.
    expect(await alTocar('lib/lo/que/sea.dart'), isNull);
  });

  test('una regla declarada que no está se dice', () async {
    // El caso que más importa: un archivo movido o mal escrito produciría trabajo que
    // ignora una regla, y nadie sospecha de un archivo que creía cargado.
    declarar('**/domain/** -> reglas/no-existe.md');

    final texto = await alTocar('lib/features/auth/domain/x.dart');
    expect(texto, contains('no se encontró'));
    expect(texto, contains('no-existe.md'));
  });

  group('no puede impedir editar', () {
    test('con basura por la entrada', () async {
      declarar('**/domain/** -> reglas/dominio.md');
      final proceso = await Process.start('python3', [
        hook,
      ], workingDirectory: repo.path);
      proceso.stdin.write('esto no es json');
      await proceso.stdin.close();
      expect(await proceso.exitCode, 0, reason: 'un hook que falla bloquearía');
    });

    test('sin ruta en la entrada, como un comando de consola', () async {
      declarar('**/domain/** -> reglas/dominio.md');
      expect(
        await conEntrada({
          'cwd': repo.path,
          'tool_input': {'command': 'ls'},
        }),
        isNull,
      );
    });
  });

  test('deja constancia, y fuera del repo', () async {
    // Sin registro esto es magia, y la magia no sirve cuando algo sale mal: «¿por qué
    // ignoró esa regla?» solo se contesta si se puede ver qué se le puso delante.
    //
    // Y **fuera del repo**: la primera versión lo dejaba en la raíz del proyecto, que en
    // un repo del trabajo es un archivo que aparece en `git status` y que alguien acaba
    // commiteando.
    final config = Directory.systemTemp.createTempSync('cuenta');
    addTearDown(() => config.deleteSync(recursive: true));

    declarar('**/domain/** -> reglas/dominio.md');
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: repo.path,
      environment: {'CLAUDE_CONFIG_DIR': config.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': repo.path,
        'tool_input': {'file_path': 'lib/features/auth/domain/x.dart'},
      }),
    );
    await proceso.stdin.close();
    await proceso.exitCode;

    expect(
      File('${repo.path}/nexus-inyecciones.log').existsSync(),
      isFalse,
      reason: 'el registro ensucia el repo',
    );
    final log = File('${config.path}/nexus-inyecciones.log');
    expect(log.existsSync(), isTrue);
    expect(log.readAsStringSync(), contains('reglas/dominio.md'));
  });
}

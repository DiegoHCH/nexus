import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/data/datasources/configs_data_source.dart';
import 'package:nexus/features/run/domain/usecases/lector_de_configs.dart';

/// Leer el `launch.json` de un proyecto.
///
/// **El fixture imita las formas de uno real, no su contenido.** El que se miró
/// para escribir esto es de un repo de trabajo y este repositorio es público, así
/// que aquí va una app inventada con las mismas costuras: comentarios `//`, una
/// configuración por entorno, `flutterMode: profile`, `${workspaceFolder}` de
/// verdad, y una `attach` y una de otro lenguaje para que haya algo que descartar.
void main() {
  const launchJson = r'''
{
  // La versión la pone el editor y no nos dice nada.
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Tienda (dev)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "args": ["--flavor", "dev", "--dart-define-from-file=config/dev.json"]
    },
    // El de perfil, que no es una bandera más.
    {
      "name": "Tienda (dev - profile)",
      "request": "launch",
      "type": "dart",
      "flutterMode": "profile",
      "args": ["--flavor", "dev"]
    },
    {
      "name": "Tienda (dev + panel)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--flavor", "dev",
        "--dart-define", "PROJECT_ROOT=${workspaceFolder}",
        "--dart-define", "ENDPOINT=https://api.ejemplo.test/v1"
      ]
    },
    {
      "name": "Engancharse al que ya corre",
      "request": "attach",
      "type": "dart"
    },
    {
      "name": "El servidor de node",
      "request": "launch",
      "type": "node",
      "program": "server.js"
    }
  ]
}
''';

  group('qué se lee y qué se descarta', () {
    test('solo las de Flutter que lanzan', () {
      final configs = LectorDeConfigs.leer(launchJson);

      // `attach` no arranca nada y la de node no es esta app: ofrecer cualquiera
      // de las dos como forma de correr sería ofrecer un fallo.
      expect(configs.map((c) => c.nombre), [
        'Tienda (dev)',
        'Tienda (dev - profile)',
        'Tienda (dev + panel)',
      ]);
    });

    test('sin `request` se asume que lanza, que es lo que hace el editor', () {
      const sinRequest = '''
{"configurations": [{"name": "Suelta", "type": "dart"}]}''';
      expect(LectorDeConfigs.leer(sinRequest).single.nombre, 'Suelta');
    });

    test(
      'un archivo que no existe o está roto da lista vacía, no una excepción',
      () {
        // Un `launch.json` a medio escribir no puede tumbar la pantalla que ofrece
        // las configuraciones.
        expect(LectorDeConfigs.leer('{ roto'), isEmpty);
        expect(LectorDeConfigs.leer(''), isEmpty);
        expect(LectorDeConfigs.leer('[]'), isEmpty);
      },
    );
  });

  group('los comentarios y las comas', () {
    test('los `//` se van y el JSON queda válido', () {
      // Un `jsonDecode` a pelo lanza en la primera línea de un launch.json real.
      expect(LectorDeConfigs.leer(launchJson).length, 3);
    });

    test('**una barra doble dentro de una cadena se queda**', () {
      // La trampa entera de limpiar JSONC con una expresión regular: borrar todo
      // lo que va detrás de `//` se come la URL y el resto de la línea, y el
      // resultado es una lista vacía sin ninguna explicación.
      final panel = LectorDeConfigs.leer(
        launchJson,
      ).firstWhere((c) => c.nombre == 'Tienda (dev + panel)');

      expect(panel.args, contains('ENDPOINT=https://api.ejemplo.test/v1'));
    });

    test('los comentarios de bloque también', () {
      const conBloque = '''
{ /* esto no es una configuración */ "configurations": [
  {"name": "Una", "type": "dart"} ] }''';
      expect(LectorDeConfigs.leer(conBloque).single.nombre, 'Una');
    });

    test('una coma colgante no rompe nada', () {
      const conColgante = '''
{"configurations": [{"name": "Una", "type": "dart", "args": ["--flavor", "dev",],},]}''';
      final leida = LectorDeConfigs.leer(conColgante).single;
      expect(leida.nombre, 'Una');
      expect(leida.args, ['--flavor', 'dev']);
    });

    test('una comilla escapada no cierra la cadena antes de tiempo', () {
      const conEscape = r'''
{"configurations": [{"name": "Con \" dentro // y esto no es comentario",
  "type": "dart"}]}''';
      expect(
        LectorDeConfigs.leer(conEscape).single.nombre,
        r'Con " dentro // y esto no es comentario',
      );
    });
  });

  group('los argumentos de flutter run', () {
    final configs = LectorDeConfigs.leer(launchJson);

    test('el entry va en `-t` y el resto tal cual', () {
      expect(
        LectorDeConfigs.argumentos(configs.first, proyecto: '/casa/tienda'),
        [
          '-t',
          'lib/main.dart',
          '--flavor',
          'dev',
          '--dart-define-from-file=config/dev.json',
        ],
      );
    });

    test('el modo se traduce, no se pasa', () {
      // `flutterMode: profile` es `--profile`. Pasar «profile» a secas sería
      // inventarse una bandera.
      final perfil = configs.firstWhere((c) => c.modo == 'profile');
      final args = LectorDeConfigs.argumentos(perfil, proyecto: '/casa/tienda');

      expect(args, contains('--profile'));
      expect(args, isNot(contains('profile')));
      // Y en debug no se pasa nada: es lo que hace `flutter run` sin más.
      expect(
        LectorDeConfigs.argumentos(configs.first, proyecto: '/casa'),
        isNot(contains('--debug')),
      );
    });

    test('`\${workspaceFolder}` se sustituye por el proyecto de verdad', () {
      // Sin esto se le pasa a la app el texto literal, y la app se lo cree.
      final panel = configs.firstWhere((c) => c.nombre.contains('panel'));
      final args = LectorDeConfigs.argumentos(panel, proyecto: '/casa/tienda');

      expect(args, contains('PROJECT_ROOT=/casa/tienda'));
      expect(args.join(' '), isNot(contains(r'${workspaceFolder}')));
    });
  });

  group('cada proyecto con las suyas', () {
    late Directory raiz;

    setUp(() => raiz = Directory.systemTemp.createTempSync('proyectos'));
    tearDown(() => raiz.deleteSync(recursive: true));

    String proyectoCon(String nombre, String contenido) {
      final dir = Directory('${raiz.path}/$nombre/.vscode')
        ..createSync(recursive: true);
      File('${dir.path}/launch.json').writeAsStringSync(contenido);
      return '${raiz.path}/$nombre';
    }

    test('las configuraciones no se cruzan entre proyectos', () async {
      // **La razón de que esto sea una familia por carpeta.** Una configuración
      // nombra el flavor y el archivo de defines de *su* repo: ofrecer la de uno
      // para correr otro es ofrecer una compilación fallida con nombre creíble.
      final tienda = proyectoCon('tienda', '''
{"configurations": [{"name": "Tienda (dev)", "type": "dart"}]}''');
      final banco = proyectoCon('banco', '''
{"configurations": [{"name": "Banco (qa)", "type": "dart"}]}''');

      const ds = ConfigsDataSource();

      expect((await ds.deProyecto(tienda)).map((c) => c.nombre), [
        'Tienda (dev)',
      ]);
      expect((await ds.deProyecto(banco)).map((c) => c.nombre), ['Banco (qa)']);
    });

    test('un proyecto sin launch.json no da error, da nada', () async {
      // Lo normal en un repo que no es de Flutter. No hay nada que ofrecer, y
      // eso no es un fallo que haya que contar.
      final pelado = Directory('${raiz.path}/pelado')..createSync();
      expect(await const ConfigsDataSource().deProyecto(pelado.path), isEmpty);
    });
  });
}

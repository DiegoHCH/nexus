import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/data/datasources/las_configs_de_casa.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/usecases/la_config_de_casa.dart';
import 'package:nexus/features/run/domain/usecases/la_consola_de_la_app.dart';
import 'package:nexus/features/run/domain/usecases/lector_de_configs.dart';

/// **Una configuración de arranque tuya, que no vive en el repositorio.**
///
/// 🔴 Pedida con un caso concreto: el repo del trabajo trae
/// «Global66 (ci + Debug Dashboard)» y **no** la misma con `prod`, ni la de
/// `profile`. Añadirla al `launch.json` es tocar un archivo versionado y
/// compartido —aparece en tu `git status`, viaja en cualquier commit distraído,
/// le cambia el menú al equipo— y en un repo del trabajo la regla es no
/// comitear nada.
///
/// Los argumentos de aquí son **los de verdad**, copiados de ese `launch.json`:
/// es lo que hace que esta prueba diga algo sobre el caso que la pidió.
const _prod = ConfigDeArranque(
  nombre: 'Global66 (prod)',
  args: [
    '--flavor',
    'prod',
    '--dart-define-from-file=config/prod.json',
    '--dart-define',
    'PROD_ENV=prod',
  ],
);

const _prodProfile = ConfigDeArranque(
  nombre: 'Global66 (prod - profile)',
  modo: 'profile',
  args: [
    '--flavor',
    'prod',
    '--dart-define-from-file=config/prod.json',
    '--dart-define',
    'PROD_ENV=prod',
  ],
);

const _ciConPanel = ConfigDeArranque(
  nombre: 'Global66 (ci + Debug Dashboard)',
  args: [
    '--flavor',
    'ci',
    '--dart-define-from-file=config/ci.json',
    '--dart-define',
    'ENABLE_DEBUG_SERVER=true',
    '--dart-define',
    r'PROJECT_ROOT=${workspaceFolder}',
  ],
);

void main() {
  group('la copia con la consola encendida', () {
    test('sale del repo lo que hace falta, y no se inventa nada', () {
      final copia = LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel);

      expect(copia.nombre, 'Global66 (prod) + consola');
      expect(copia.local, isTrue);
      expect(
        LaConsolaDeLaApp.laEnciende(copia.args),
        isTrue,
        reason: 'para eso se copia',
      );
      // 🔴 **Los dos defines, no solo el del flag.** La configuración del repo
      // que enciende el panel pasa también `PROJECT_ROOT`, que es con lo que el
      // panel encuentra los documentos del repo: adivinar solo el primero daba
      // media consola con aspecto de estar bien.
      expect(
        copia.args,
        containsAllInOrder([
          '--dart-define',
          r'PROJECT_ROOT=${workspaceFolder}',
        ]),
      );
    });

    // 🔴 **Y lo que NO se copia.** `--dart-define-from-file` apunta al archivo
    // de un entorno: llevarse el de `ci` a `prod` sería arrancar prod con la
    // configuración de ci. Es el fallo que este atajo tiene que evitar.
    test('el archivo de defines del otro entorno se queda donde estaba', () {
      final copia = LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel);

      expect(
        copia.args,
        isNot(contains('--dart-define-from-file=config/ci.json')),
      );
      expect(copia.args, contains('--dart-define-from-file=config/prod.json'));
      expect(copia.args, containsAllInOrder(['--flavor', 'prod']));
      expect(
        copia.args.where((a) => a == '--flavor'),
        hasLength(1),
        reason: 'dos flavors serían una compilación rota con nombre creíble',
      );
    });

    test('lo suyo no se le pisa: PROD_ENV sigue siendo el de prod', () {
      final copia = LaConfigDeCasa.conLaConsola(
        _prod,
        modelo: const ConfigDeArranque(
          nombre: 'la del panel',
          args: [
            '--dart-define',
            'ENABLE_DEBUG_SERVER=true',
            '--dart-define',
            'PROD_ENV=ci',
          ],
        ),
      );

      expect(copia.args, contains('PROD_ENV=prod'));
      expect(copia.args, isNot(contains('PROD_ENV=ci')));
    });

    // «O de profile», que es la otra mitad de lo que se pidió: el modo se
    // conserva, y el panel de ese repo no depende de `kDebugMode`.
    test('la de profile se copia como profile', () {
      final copia = LaConfigDeCasa.conLaConsola(
        _prodProfile,
        modelo: _ciConPanel,
      );

      expect(copia.modo, 'profile');
      expect(LaConsolaDeLaApp.laEnciende(copia.args), isTrue);
    });

    test('sin ninguna del repo que la encienda, se pone lo mínimo', () {
      final copia = LaConfigDeCasa.conLaConsola(_prod);

      expect(LaConsolaDeLaApp.laEnciende(copia.args), isTrue);
      expect(
        copia.args,
        isNot(contains(r'PROJECT_ROOT=${workspaceFolder}')),
        reason: 'eso es de aquel repo, no de Nexus',
      );
    });

    test('la que ya la trae no se ofrece duplicar, ni la que ya es tuya', () {
      expect(LaConfigDeCasa.sePuedeDuplicar(_prod), isTrue);
      expect(LaConfigDeCasa.sePuedeDuplicar(_ciConPanel), isFalse);
      expect(
        LaConfigDeCasa.sePuedeDuplicar(
          LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel),
        ),
        isFalse,
      );
    });

    test('y se sabe cuál del repo es la que la enciende', () {
      expect(
        LaConfigDeCasa.laQueEnciendeLaConsola([
          _prod,
          _prodProfile,
          _ciConPanel,
        ])?.nombre,
        _ciConPanel.nombre,
      );
      expect(LaConfigDeCasa.laQueEnciendeLaConsola([_prod]), isNull);
    });
  });

  group('las dos listas, en un solo menú', () {
    test('las tuyas van detrás de las del repo', () {
      final juntas = LaConfigDeCasa.junta(
        delRepo: [_prod, _ciConPanel],
        propias: [LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel)],
      );

      expect(juntas.map((c) => c.nombre), [
        'Global66 (prod)',
        'Global66 (ci + Debug Dashboard)',
        'Global66 (prod) + consola',
      ]);
    });

    // Si mañana alguien añade al `launch.json` una que se llama igual, la del
    // repo manda: es la compartida, y tapar una con otra en silencio dejaría
    // corriendo un entorno que no es el que dice el nombre.
    test('y una tuya no tapa a una del repo con el mismo nombre', () {
      final juntas = LaConfigDeCasa.junta(
        delRepo: [_prod],
        propias: [
          const ConfigDeArranque(nombre: 'Global66 (prod)', local: true),
        ],
      );

      expect(juntas, hasLength(1));
      expect(juntas.single.local, isFalse);
    });
  });

  group('el archivo, que tiene forma de launch.json', () {
    test('lo que se escribe se vuelve a leer igual, y marcado como tuyo', () {
      final copia = LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel);

      final leidas = LectorDeConfigs.leer(
        LaConfigDeCasa.comoArchivo([copia]),
        local: true,
      );

      expect(leidas, hasLength(1));
      expect(leidas.single.nombre, copia.nombre);
      expect(leidas.single.args, copia.args);
      expect(leidas.single.modo, copia.modo);
      expect(
        leidas.single.local,
        isTrue,
        reason: 'sin esto, la copia se ofrecería como si fuera del repo',
      );
    });

    test('y se puede leer con cualquier editor: es JSON con sangría', () {
      final texto = LaConfigDeCasa.comoArchivo([_prod]);

      expect(texto, contains('"configurations"'));
      expect(texto, contains('\n  '));
      expect(texto, endsWith('\n'));
    });
  });

  group('guardadas en el soporte de Nexus, no en el repo', () {
    late Directory carpeta;
    late LasConfigsDeCasa propias;
    const proyecto = '/Users/alguien/Workspace/front-mobile-b2c';

    setUp(() {
      carpeta = Directory.systemTemp.createTempSync('configs_de_casa');
      propias = LasConfigsDeCasa(carpeta: carpeta);
    });
    tearDown(() => carpeta.deleteSync(recursive: true));

    test('sin nada guardado, ninguna', () async {
      expect(await propias.deProyecto(proyecto), isEmpty);
    });

    test('la guardada vuelve, y el repo no se toca', () async {
      final copia = LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel);

      expect(await propias.anadir(proyecto, copia), isTrue);

      final leidas = await propias.deProyecto(proyecto);
      expect(leidas.single.nombre, copia.nombre);
      expect(leidas.single.local, isTrue);
      // Lo único que se escribió está bajo la carpeta de Nexus.
      expect(
        (await propias.archivoDe(proyecto)).path,
        startsWith(carpeta.path),
      );
    });

    test('dos veces la misma no se guarda dos veces', () async {
      final copia = LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel);
      await propias.anadir(proyecto, copia);

      expect(
        await propias.anadir(proyecto, copia),
        isFalse,
        reason: 'dos con el mismo nombre serían una sola en el desplegable',
      );
      expect(await propias.deProyecto(proyecto), hasLength(1));
    });

    test('quitarla la quita, y deja las demás', () async {
      await propias.anadir(
        proyecto,
        LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel),
      );
      await propias.anadir(
        proyecto,
        LaConfigDeCasa.conLaConsola(_prodProfile, modelo: _ciConPanel),
      );

      await propias.quitar(proyecto, 'Global66 (prod) + consola');

      expect((await propias.deProyecto(proyecto)).map((c) => c.nombre), [
        'Global66 (prod - profile) + consola',
      ]);
    });

    // Un proyecto no puede ver las del otro: una configuración nombra el flavor
    // y el archivo de defines de **ese** repo.
    test('cada proyecto tiene las suyas', () async {
      await propias.anadir(
        proyecto,
        LaConfigDeCasa.conLaConsola(_prod, modelo: _ciConPanel),
      );

      expect(
        await propias.deProyecto('/Users/alguien/personal/nexus'),
        isEmpty,
      );
    });

    test('un archivo roto no tumba el menú', () async {
      final file = await propias.archivoDe(proyecto);
      file.writeAsStringSync('{esto no es json');

      expect(await propias.deProyecto(proyecto), isEmpty);
    });
  });
}

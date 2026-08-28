import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Dónde busca Nexus las pruebas de un proyecto.
///
/// **El punto de todo esto es que las de dos proyectos no se puedan mezclar.** Y la forma
/// de conseguirlo no es un filtro —un filtro se equivoca— sino que cada proyecto apunte a
/// su carpeta: Nexus lista esa y las demás no existen para él.
void main() {
  const home = '/Users/quien';

  PairedFolder carpeta({String? pruebas, String? repo}) => PairedFolder(
    path: '/Users/quien/Workspace/proyecto',
    modality: FolderModality.textOnly,
    activeRepo: repo,
    carpetaDePruebas: pruebas,
  );

  group('dónde mira', () {
    test('sin declarar nada, la convención de Maestro', () {
      // Nada de lo que ya funcionaba puede cambiar por añadir un ajuste nuevo.
      expect(
        carpeta().pruebasEn(home),
        '/Users/quien/Workspace/proyecto/.maestro',
      );
    });

    test('una ruta absoluta se respeta tal cual', () {
      expect(
        carpeta(
          pruebas: '/Users/quien/Escritorio/e2e/global66',
        ).pruebasEn(home),
        '/Users/quien/Escritorio/e2e/global66',
      );
    });

    test('con «~» se resuelve contra el home', () {
      expect(
        carpeta(pruebas: '~/Escritorio/e2e/global66').pruebasEn(home),
        '/Users/quien/Escritorio/e2e/global66',
      );
    });

    test('una relativa cuelga del proyecto', () {
      expect(
        carpeta(pruebas: 'flows').pruebasEn(home),
        '/Users/quien/Workspace/proyecto/flows',
      );
    });

    test('y con varios repos dentro, del repo elegido', () {
      // Es el caso que confunde: la carpeta emparejada es la raíz, pero las pruebas son
      // del repo sobre el que se trabaja.
      expect(
        carpeta(
          pruebas: 'flows',
          repo: '/Users/quien/Workspace/proyecto/uno',
        ).pruebasEn(home),
        '/Users/quien/Workspace/proyecto/uno/flows',
      );
    });

    test('en blanco es como no declarar nada', () {
      expect(
        carpeta(pruebas: '   ').pruebasEn(home),
        '/Users/quien/Workspace/proyecto/.maestro',
      );
    });
  });

  group('lo que se guarda', () {
    test('sobrevive a la ida y vuelta por JSON', () {
      final leida = PairedFolder.fromJson(
        carpeta(pruebas: '~/Escritorio/e2e/global66').toJson(),
      );
      expect(leida!.carpetaDePruebas, '~/Escritorio/e2e/global66');
    });

    test('sin declarar, no ensucia el archivo', () {
      expect(carpeta().toJson().containsKey('carpetaDePruebas'), isFalse);
    });
  });

  group('listar la carpeta', () {
    late Directory raiz;
    const fuente = E2eDataSource();

    setUp(() => raiz = Directory.systemTemp.createTempSync('e2e'));
    tearDown(() => raiz.deleteSync(recursive: true));

    File escribir(String ruta) => File('${raiz.path}/$ruta')
      ..createSync(recursive: true)
      ..writeAsStringSync('appId: algo\n---\n- launchApp\n');

    test('lista los .yaml de esa carpeta y nada más', () async {
      escribir('global66/login.yaml');
      escribir('global66/pago.yml');
      escribir('otro-proyecto/algo.yaml');

      final pruebas = await fuente.pruebasDe('${raiz.path}/global66');
      expect(pruebas.map((p) => p.nombre).toList()..sort(), ['login', 'pago']);
    });

    test('las de otro proyecto no se cuelan', () async {
      // La separación que se buscaba, y no depende de ningún filtro: son otra carpeta.
      escribir('global66/login.yaml');
      escribir('otro-proyecto/algo.yaml');

      final pruebas = await fuente.pruebasDe('${raiz.path}/otro-proyecto');
      expect(pruebas.map((p) => p.nombre), ['algo']);
    });

    test('lo de las subcarpetas queda fuera', () async {
      // Los auxiliares que otros flows llaman con `runFlow` no son pruebas que se lancen.
      // Medido en un repo de verdad: de 57 YAML, 38 son pruebas y 19 son piezas.
      escribir('global66/login.yaml');
      escribir('global66/commons/setup.yaml');
      escribir('global66/auth/pin.yaml');

      final pruebas = await fuente.pruebasDe('${raiz.path}/global66');
      expect(pruebas.map((p) => p.nombre), ['login']);
    });

    test('una carpeta que no existe no revienta', () async {
      expect(await fuente.pruebasDe('${raiz.path}/no-existe'), isEmpty);
    });
  });

  group('las credenciales', () {
    late Directory proyecto;
    late Directory pruebas;
    const fuente = E2eDataSource();

    setUp(() {
      proyecto = Directory.systemTemp.createTempSync('proyecto');
      pruebas = Directory.systemTemp.createTempSync('pruebas');
    });

    tearDown(() {
      proyecto.deleteSync(recursive: true);
      pruebas.deleteSync(recursive: true);
    });

    test('se buscan primero junto a las pruebas', () async {
      // Cuando las pruebas viven fuera del repo —que es medio motivo para sacarlas— sus
      // credenciales viven con ellas. Obligar a dejar un `.env.local` dentro del repo del
      // trabajo sería devolver justo lo que se quería quitar de ahí.
      File(
        '${proyecto.path}/.env.local',
      ).writeAsStringSync('QUIEN=el-proyecto\n');
      File(
        '${pruebas.path}/.env.local',
      ).writeAsStringSync('QUIEN=las-pruebas\n');

      expect(
        fuente.variablesDe(
          proyecto.path,
          carpetaDePruebas: pruebas.path,
        )['QUIEN'],
        'las-pruebas',
      );
    });

    test('y si allí no hay, en el proyecto', () async {
      File(
        '${proyecto.path}/.env.local',
      ).writeAsStringSync('QUIEN=el-proyecto\n');

      expect(
        fuente.variablesDe(
          proyecto.path,
          carpetaDePruebas: pruebas.path,
        )['QUIEN'],
        'el-proyecto',
      );
    });

    test('sin ninguno de los dos, vacío y sin quejarse', () {
      expect(
        fuente.variablesDe(proyecto.path, carpetaDePruebas: pruebas.path),
        isEmpty,
      );
    });
  });

  group('lo que se le dice a Claude', () {
    test('con la carpeta declarada, se le dice dónde escribirlas', () {
      // Sin esto el ajuste queda a medias: Nexus buscaría en una carpeta y Claude
      // escribiría en otra. La prueba existiría, la lista saldría vacía, y no hay forma
      // de diagnosticar eso mirando.
      final texto = ProjectContextPrompt.compose(
        rules: const [],
        carpetaDePruebas: '/Users/quien/Escritorio/e2e/global66',
      );

      expect(texto, contains('/Users/quien/Escritorio/e2e/global66'));
      expect(texto, contains('no dentro del repositorio'));
      // Y que los auxiliares van en un subdirectorio, porque lo suelto se ofrece como
      // prueba que se lanza sola.
      expect(texto, contains('runFlow'));
    });

    test('sin declararla, no se dice nada', () {
      // `.maestro/` es la convención de Maestro y Claude ya la conoce. Repetirla en cada
      // encargo de cada proyecto sería ruido para los que no tienen pruebas.
      expect(ProjectContextPrompt.compose(rules: const []), isNull);
    });
  });

  group('la raíz común', () {
    test('le pone el nombre del proyecto detrás', () {
      // Es lo que pedía el caso: una carpeta para todo y una subcarpeta por proyecto,
      // así están juntas y no se mezclan.
      expect(
        carpeta().pruebasEn(home, raiz: '~/pruebas'),
        '/Users/quien/pruebas/proyecto',
      );
    });

    test('y una absoluta vale igual', () {
      expect(
        carpeta().pruebasEn(home, raiz: '/Volumes/disco/pruebas'),
        '/Volumes/disco/pruebas/proyecto',
      );
    });

    test('lo que declara la carpeta gana a la raíz', () {
      // La raíz es una preferencia tuya; la declaración es un hecho del repo. Un repo
      // que ya tiene sus pruebas en «flows» no se puede mover desde un ajuste global.
      expect(
        carpeta(pruebas: 'flows').pruebasEn(home, raiz: '~/pruebas'),
        '/Users/quien/Workspace/proyecto/flows',
      );
    });

    test('sin raíz y sin declarar, la convención de Maestro', () {
      expect(
        carpeta().pruebasEn(home, raiz: '   '),
        '/Users/quien/Workspace/proyecto/.maestro',
      );
    });

    test('la subcarpeta es la del repo, no la de la carpeta emparejada', () {
      // **El caso real que lo destapó**: `~/Workspace` emparejada con tres repos
      // dentro. Con el nombre de la carpeta, las pruebas de los tres caerían en
      // `~/pruebas/Workspace` — mezcladas, que es lo que la raíz existe para evitar.
      expect(
        carpeta(
          repo: '/Users/quien/Workspace/proyecto/front-mobile-b2c',
        ).pruebasEn(home, raiz: '~/pruebas'),
        '/Users/quien/pruebas/front-mobile-b2c',
      );
    });

    test('dos proyectos caen en subcarpetas distintas', () {
      const otro = PairedFolder(
        path: '/Users/quien/Workspace/nexus',
        modality: FolderModality.textOnly,
      );
      expect(
        carpeta().pruebasEn(home, raiz: '~/pruebas'),
        isNot(otro.pruebasEn(home, raiz: '~/pruebas')),
      );
      expect(otro.pruebasEn(home, raiz: '~/pruebas'), endsWith('/nexus'));
    });
  });
}

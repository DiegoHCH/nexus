import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/data/datasources/skills_data_source.dart';

/// Lo que las skills escriben y borran en la cuenta, probado con carpetas de
/// verdad y sin lanzar un proceso.
///
/// 🔴 **Aquí se borra recursivamente dentro del `.claude/` de alguien.** Lo
/// único que separa `remove(cuenta, 'revisar-pr')` de `remove(cuenta, '..')` es
/// el guardia de `validId`, y eso no tenía prueba: la fuente estaba al 21,6 %.
void main() {
  const fuente = SkillsDataSource();
  late Directory cuenta;

  setUp(() => cuenta = Directory.systemTemp.createTempSync('nexus_cuenta'));
  tearDown(() => cuenta.deleteSync(recursive: true));

  Directory carpetaDe(String id) => Directory('${cuenta.path}/skills/$id');

  void skillPuesta(String id, {String descripcion = 'Para lo que sea'}) =>
      File('${carpetaDe(id).path}/SKILL.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nname: $id\ndescription: $descripcion\n---\n');

  group('las que están puestas', () {
    test('sin carpeta de skills no hay ninguna', () async {
      expect(await fuente.installed(cuenta.path), isEmpty);
    });

    test('salen en orden, con la descripción del frontmatter', () async {
      skillPuesta('revisar-pr', descripcion: 'Revisa un PR de GitHub');
      skillPuesta('archify', descripcion: 'Dibuja arquitecturas');

      final puestas = await fuente.installed(cuenta.path);

      expect(puestas.map((s) => s.id), ['archify', 'revisar-pr']);
      expect(puestas.last.description, 'Revisa un PR de GitHub');
    });

    // Una carpeta suelta no es una skill: lo que la hace serlo es el SKILL.md.
    test('una carpeta sin SKILL.md no cuenta', () async {
      skillPuesta('buena');
      carpetaDe('vacia').createSync(recursive: true);
      File('${cuenta.path}/skills/suelto.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('nada');

      expect((await fuente.installed(cuenta.path)).map((s) => s.id), ['buena']);
    });
  });

  group('crear una', () {
    test('deja el esqueleto y devuelve dónde', () async {
      final hecho = await fuente.create(
        cuenta.path,
        name: 'Revisar Stocks',
        description: 'Cuándo mirar el módulo de stocks',
      );

      expect(hecho.error, isNull);
      expect(hecho.path, endsWith('/skills/revisar-stocks/SKILL.md'));

      final escrito = File(hecho.path!).readAsStringSync();
      expect(escrito, contains('name: revisar-stocks'));
      expect(
        escrito,
        contains('Cuándo mirar el módulo de stocks'),
        reason:
            'la descripción es lo único que el agente lee para decidir si la '
            'activa: si no llega al archivo, la skill no se activa nunca',
      );
    });

    // Sin descripción se escribe una que **dice qué hay que escribir**, en vez
    // de dejar el campo vacío — que es una skill que nunca se activa.
    test('sin descripción no se deja el campo vacío', () async {
      final hecho = await fuente.create(
        cuenta.path,
        name: 'algo',
        description: '   ',
      );

      final escrito = File(hecho.path!).readAsStringSync();
      expect(escrito, isNot(contains('description:\n')));
      expect(escrito, contains('CUÁNDO'));
    });

    test('un nombre del que no sale identificador se rechaza', () async {
      for (final nombre in ['', '   ', '///', '- -']) {
        final hecho = await fuente.create(
          cuenta.path,
          name: nombre,
          description: 'x',
        );

        expect(hecho.path, isNull, reason: '«$nombre»');
        expect(hecho.error, isNotNull, reason: '«$nombre»');
      }
    });

    // Pisar una skill que ya existe sería borrar el trabajo de alguien sin
    // preguntar.
    test('no pisa una que ya existe', () async {
      skillPuesta('revisar-pr', descripcion: 'la de siempre');

      final hecho = await fuente.create(
        cuenta.path,
        name: 'revisar-pr',
        description: 'otra cosa',
      );

      expect(hecho.path, isNull);
      expect(hecho.error, contains('revisar-pr'));
      expect(
        File('${carpetaDe('revisar-pr').path}/SKILL.md').readAsStringSync(),
        contains('la de siempre'),
      );
    });
  });

  group('borrar una', () {
    test('la borra entera', () async {
      skillPuesta('revisar-pr');
      File('${carpetaDe('revisar-pr').path}/referencias/notas.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');

      expect(await fuente.remove(cuenta.path, 'revisar-pr'), isNull);
      expect(carpetaDe('revisar-pr').existsSync(), isFalse);
    });

    test('borrar una que no está no es un error', () async {
      expect(await fuente.remove(cuenta.path, 'no-existe'), isNull);
    });

    // 🔴 El guardia que importa. Sin él, esto borra recursivamente lo que le
    // digan dentro —y fuera— del `.claude/` de alguien.
    test('un identificador que no lo es no borra nada', () async {
      skillPuesta('revisar-pr');
      final vecina = Directory('${cuenta.path}/skills-de-al-lado')
        ..createSync(recursive: true);

      for (final id in ['..', '../..', 'skills/../..', '/', '.', 'CON-MAYUS']) {
        expect(
          await fuente.remove(cuenta.path, id),
          isNotNull,
          reason: '«$id» tiene que rechazarse, no ejecutarse',
        );
      }

      expect(carpetaDe('revisar-pr').existsSync(), isTrue);
      expect(vecina.existsSync(), isTrue);
      expect(cuenta.existsSync(), isTrue);
    });
  });

  // Instalar en varias cuentas: lo que se comprueba sin red es que **cada
  // cuenta reporta su propio fallo**, que es lo que permite decir en cuál no
  // entró. Con un identificador inválido se rechaza antes de tocar git.
  test('instalar en varias cuentas reporta el fallo de cada una', () async {
    final fallos = await fuente.installEn(
      ['/cuenta/una', '/cuenta/otra'],
      repoRaw: 'alguien/skills',
      id: 'NO VALE',
    );

    expect(fallos.keys, ['/cuenta/una', '/cuenta/otra']);
    expect(fallos.values.every((f) => f.isNotEmpty), isTrue);
  });
}

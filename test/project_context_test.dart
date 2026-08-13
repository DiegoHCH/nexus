import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/project_context_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';

void main() {
  group('cómo se arma el texto', () {
    // Lo que hace que funcione: el del proyecto va el último, porque lo último
    // leído es lo que pesa. Medido contra el binario — sin esto la respuesta
    // salía «LORO TUCAN», intentando contentar a los dos.
    test('las reglas del proyecto van al final', () {
      final texto = ProjectContextPrompt.compose(
        rules: const [
          (path: '/w/CLAUDE.md', content: 'empieza por LORO'),
          (path: '/w/proyecto/CLAUDE.md', content: 'empieza por TUCAN'),
        ],
      )!;

      expect(texto.indexOf('LORO'), lessThan(texto.indexOf('TUCAN')));
      expect(texto, contains('gana la que aparece más abajo'));
    });

    test('sin nada que decir no se manda nada', () {
      expect(ProjectContextPrompt.compose(rules: const []), isNull);
      // Un archivo vacío tampoco cuenta como contexto.
      expect(
        ProjectContextPrompt.compose(
          rules: const [(path: '/w/CLAUDE.md', content: '   ')],
        ),
        isNotNull,
      );
    });

    test('el contexto compartido dice que no son las reglas completas', () {
      final texto = ProjectContextPrompt.compose(
        rules: const [],
        sharedContext: (path: '/w/ai-context/x/CONTEXT.md', content: 'mapa'),
      )!;

      expect(texto, contains('mapa'));
      // Tener el mapa cargado no es tener las reglas: son cientos de miles de
      // caracteres y no caben, así que se dice con todas las letras.
      expect(texto, contains('no sus reglas completas'));
    });

    group('cuando no cabe', () {
      test('se sacrifica lo de arriba, y se avisa de qué se cayó', () {
        final grande = 'x' * (ProjectContextPrompt.maxRulesChars ~/ 2 + 100);
        final texto = ProjectContextPrompt.compose(
          rules: [
            (path: '/w/CLAUDE.md', content: grande),
            (path: '/w/otro/CLAUDE.md', content: grande),
            (path: '/w/otro/proyecto/CLAUDE.md', content: 'las del proyecto'),
          ],
        )!;

        expect(texto, contains('las del proyecto'));
        expect(texto, contains('se han omitido'));
        expect(texto, contains('/w/CLAUDE.md'));
      });

      test(
        'si el del proyecto ya no cabe, se recorta él antes que perderlo',
        () {
          final enorme = 'y' * (ProjectContextPrompt.maxRulesChars + 500);
          final texto = ProjectContextPrompt.compose(
            rules: [(path: '/w/proyecto/CLAUDE.md', content: enorme)],
          )!;

          expect(texto, contains('recortado'));
          expect(
            texto.length,
            lessThan(ProjectContextPrompt.maxRulesChars + 900),
          );
        },
      );
    });
  });

  group('qué se encuentra en el disco', () {
    late Directory raiz;

    setUp(() => raiz = Directory.systemTemp.createTempSync('nexus_contexto'));
    tearDown(() => raiz.deleteSync(recursive: true));

    Directory carpeta(String ruta) =>
        Directory('${raiz.path}/$ruta')..createSync(recursive: true);

    void escribe(String ruta, String contenido) =>
        File('${raiz.path}/$ruta').writeAsStringSync(contenido);

    test(
      'recoge los CLAUDE.md del árbol, del más lejano al más cercano',
      () async {
        carpeta('workspace/proyecto');
        escribe('workspace/CLAUDE.md', 'reglas del workspace');
        escribe('workspace/proyecto/CLAUDE.md', 'reglas del proyecto');

        final leido = await const ProjectContextDataSource().read(
          '${raiz.path}/workspace/proyecto',
        );

        expect(leido.rules.map((f) => f.content), [
          'reglas del workspace',
          'reglas del proyecto',
        ]);
      },
    );

    test('una carpeta sin reglas no inventa ninguna', () async {
      carpeta('sola');
      final leido = await const ProjectContextDataSource().read(
        '${raiz.path}/sola',
      );

      expect(leido.rules, isEmpty);
      expect(leido.sharedContext, isNull);
    });

    void mapa(Map<String, String> repos) {
      carpeta('workspace/ai-context/repo-map');
      escribe(
        'workspace/ai-context/repo-map/registry.json',
        jsonEncode({
          'repositories': {
            for (final entry in repos.entries) entry.key: {'repo': entry.value},
          },
        }),
      );
      for (final id in repos.keys) {
        carpeta('workspace/ai-context/repositories/$id');
        escribe(
          'workspace/ai-context/repositories/$id/CONTEXT.md',
          'contexto de $id',
        );
      }
    }

    // El nombre de la carpeta no es el id: en el mapa real, la carpeta
    // `front-mobile-b2c` es el id `fe-b2c`.
    test('el CONTEXT.md sale del id, no del nombre de la carpeta', () async {
      mapa({'fe-b2c': 'front-mobile-b2c'});
      carpeta('workspace/front-mobile-b2c');

      final leido = await const ProjectContextDataSource().read(
        '${raiz.path}/workspace/front-mobile-b2c',
      );

      expect(leido.sharedContext?.content, 'contexto de fe-b2c');
    });

    test(
      'trabajando sobre el workspace, si dentro hay uno solo, se resuelve',
      () async {
        mapa({'fe-b2c': 'front-mobile-b2c'});
        carpeta('workspace/front-mobile-b2c');

        final leido = await const ProjectContextDataSource().read(
          '${raiz.path}/workspace',
        );

        expect(leido.sharedContext?.content, 'contexto de fe-b2c');
      },
    );

    // Cargar las reglas del repo equivocado es peor que no cargar ninguna: el
    // agente trabajaría convencido de tener el contexto bueno.
    test('con dos candidatos dentro, no adivina', () async {
      mapa({'fe-b2c': 'front-mobile-b2c', 'otro': 'otro-repo'});
      carpeta('workspace/front-mobile-b2c');
      carpeta('workspace/otro-repo');

      final leido = await const ProjectContextDataSource().read(
        '${raiz.path}/workspace',
      );

      expect(leido.sharedContext, isNull);
    });

    test('una carpeta ai-context sin mapa no cuenta', () async {
      carpeta('workspace/ai-context');
      carpeta('workspace/proyecto');

      final leido = await const ProjectContextDataSource().read(
        '${raiz.path}/workspace/proyecto',
      );

      expect(leido.sharedContext, isNull);
    });

    test('un mapa ilegible no rompe el encargo', () async {
      carpeta('workspace/ai-context/repo-map');
      escribe('workspace/ai-context/repo-map/registry.json', 'esto no es JSON');
      carpeta('workspace/proyecto');

      final leido = await const ProjectContextDataSource().read(
        '${raiz.path}/workspace/proyecto',
      );

      expect(leido.sharedContext, isNull);
    });
  });
}

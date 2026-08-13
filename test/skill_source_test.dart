import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/domain/usecases/skill_source.dart';

void main() {
  group('de dónde viene', () {
    // Pegar la URL de la barra de direcciones es lo que uno hace de verdad, y
    // rechazarla por no ser «usuario/repo» sería pedantería.
    test('la URL del navegador vale igual que «usuario/repo»', () {
      for (final entrada in [
        'anthropics/skills',
        'https://github.com/anthropics/skills',
        'https://github.com/anthropics/skills.git',
        'github.com/anthropics/skills/',
        '  anthropics/skills  ',
      ]) {
        expect(
          SkillSource.normalizeRepo(entrada),
          'anthropics/skills',
          reason: entrada,
        );
      }
    });

    test('lo que no es un repo se rechaza', () {
      expect(SkillSource.normalizeRepo('anthropics'), isNull);
      expect(SkillSource.normalizeRepo(''), isNull);
      expect(SkillSource.normalizeRepo('a/b/c/d'), isNull);
    });
  });

  group('el identificador', () {
    // Se usa para construir rutas y para borrar recursivamente, así que solo
    // puede ser un nombre de carpeta y nada más.
    test('lo que no vale como carpeta no vale como id', () {
      expect(SkillSource.validId('frontend-design'), isTrue);
      expect(SkillSource.validId('../../etc'), isFalse);
      expect(SkillSource.validId('con espacios'), isFalse);
      expect(SkillSource.validId(''), isFalse);
    });

    test('lo escrito por una persona se normaliza', () {
      expect(SkillSource.idFrom('Revisar Stocks'), 'revisar-stocks');
      expect(SkillSource.idFrom('  pre_PR  '), 'pre-pr');
      expect(SkillSource.idFrom('¡¿?!'), isNull);
    });
  });

  group('la descripción del frontmatter', () {
    test('se saca sin parser de YAML', () {
      const skill = '''
---
name: pdf
description: Use this skill whenever the user wants to do anything with PDFs.
license: Proprietary
---

# pdf
''';

      expect(
        SkillSource.descriptionOf(skill),
        'Use this skill whenever the user wants to do anything with PDFs.',
      );
    });

    test('las comillas no se cuelan', () {
      expect(SkillSource.descriptionOf('description: "algo"'), 'algo');
    });

    test('sin descripción, cadena vacía y no una excepción', () {
      expect(SkillSource.descriptionOf('---\nname: x\n---'), '');
    });
  });

  // El error de bulto al escribir la primera skill es describir **qué hace**:
  // el agente nunca la activa, porque lo que lee para decidir es cuándo usarla.
  test('el esqueleto insiste en el «cuándo»', () {
    final skeleton = SkillSource.skeleton('mi-skill', '');

    expect(skeleton, startsWith('---\nname: mi-skill\n'));
    expect(skeleton, contains('CUÁNDO'));
  });

  test('con descripción dada, se respeta la del usuario', () {
    expect(
      SkillSource.skeleton('x', 'Úsala al preparar un PR'),
      contains('description: Úsala al preparar un PR'),
    );
  });
}

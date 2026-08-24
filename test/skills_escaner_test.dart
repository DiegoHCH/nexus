import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/data/datasources/skills_data_source.dart';

/// Que el escáner encuentre las skills **donde los repos las ponen de verdad**.
///
/// Las tres formas de aquí salen de tres repos reales, comprobados contra
/// GitHub, no de suposiciones:
///
/// - `github/spec-kit` tiene su única skill en `.github/skills/…`. Saltando toda
///   carpeta que empieza por punto, ese repo parecía vacío.
/// - `davila7/claude-code-templates` las anida en
///   `cli-tool/components/skills/<familia>/<skill>/`, que son cinco niveles, y
///   además publica otras en `.claude-plugin/skills/`.
/// - `ai-dashboad/flutter-skill` las tiene a dos niveles, y esa ya funcionaba.
void main() {
  late Directory raiz;

  setUp(() => raiz = Directory.systemTemp.createTempSync('nexus_skills'));
  tearDown(() => raiz.deleteSync(recursive: true));

  void crearSkill(String ruta, {String descripcion = 'para algo'}) {
    final dir = Directory('${raiz.path}/$ruta')..createSync(recursive: true);
    File('${dir.path}/SKILL.md').writeAsStringSync(
      '---\nname: ${ruta.split('/').last}\ndescription: $descripcion\n---\n',
    );
  }

  /// El escáner trabaja sobre un clon, así que se le da uno hecho a mano: un
  /// directorio con la forma del repo y un `.git` dentro para que no intente
  /// clonar nada.
  Future<List<String>> escanear() async {
    Directory('${raiz.path}/.git').createSync();
    // `scan` clona; lo que se prueba aquí es el recorrido, que es lo que
    // fallaba. Se llama al recorrido a través de la caché ya poblada.
    final encontradas = await const SkillsDataSource().skillsIn(raiz);
    return encontradas.map((skill) => skill.id).toList()..sort();
  }

  test('una skill dentro de .github aparece (github/spec-kit)', () async {
    crearSkill('.github/skills/add-community-extension');
    expect(await escanear(), ['add-community-extension']);
  });

  test('y dentro de .claude-plugin también', () async {
    crearSkill('.claude-plugin/skills/owasp-security');
    expect(await escanear(), ['owasp-security']);
  });

  test('a cinco niveles de fondo, que ya funcionaba', () async {
    // Está aquí para que siga funcionando, no porque estuviera roto:
    // comprobado, con el límite viejo —`depth > 4`— a cinco niveles se entra
    // con `depth == 4` y la guarda no salta. Es la ruta de
    // `davila7/claude-code-templates`.
    crearSkill('cli-tool/components/skills/creative-design/mobile-design');
    expect(await escanear(), ['mobile-design']);
  });

  test('y a seis, que es lo que el límite viejo sí cortaba', () async {
    crearSkill('cli-tool/components/skills/familia/subfamilia/la-skill');
    expect(await escanear(), ['la-skill']);
  });

  test('a dos niveles, como siempre (ai-dashboad/flutter-skill)', () async {
    crearSkill('skills/e2e-testing');
    crearSkill('skills-submission/flutter-skill');
    expect(await escanear(), ['e2e-testing', 'flutter-skill']);
  });

  test('en .git no se busca, ni si alguien deja un SKILL.md ahí', () async {
    Directory('${raiz.path}/.git/skills/fantasma').createSync(recursive: true);
    File(
      '${raiz.path}/.git/skills/fantasma/SKILL.md',
    ).writeAsStringSync('---\n');
    crearSkill('skills/de-verdad');
    expect(await escanear(), ['de-verdad']);
  });

  test('node_modules tampoco', () async {
    crearSkill('node_modules/paquete/skills/ajena');
    crearSkill('skills/propia');
    expect(await escanear(), ['propia']);
  });

  test('cientos repartidas en familias, y no se pierde ninguna', () async {
    // Así es como duele el tope de verdad, y no como parecía: se comprueba al
    // **entrar** en cada carpeta, no al añadir. Con todas las skills en un solo
    // directorio el tope no se notaba; repartidas en familias —como las reparte
    // `davila7/claude-code-templates`— dejaba de entrar en las familias nuevas
    // en cuanto llevaba cien, y las de la M en adelante no existían.
    for (var familia = 0; familia < 12; familia++) {
      for (var i = 0; i < 15; i++) {
        crearSkill('skills/familia-$familia/skill-$i');
      }
    }
    expect((await escanear()).length, 180);
  });
}

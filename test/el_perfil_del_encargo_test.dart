import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/el_perfil_del_encargo.dart';

void main() {
  late Directory perfil;

  setUp(() => perfil = Directory.systemTemp.createTempSync('perfil'));
  tearDown(() => perfil.deleteSync(recursive: true));

  void inventario(String json) {
    final file = File('${perfil.path}/plugins/installed_plugins.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(json);
  }

  group('lo que se le dice al modelo', () {
    // El fallo que esto viene a arreglar: la sesión no sabía con qué perfil
    // corría y daba por hecho el de fábrica, así que buscaba el plugin en
    // `~/.claude/plugins` con el plugin puesto en otro sitio.
    test('la carpeta del perfil se nombra, no se deja adivinar', () async {
      inventario('{"version":2,"plugins":{}}');

      expect(
        await ElPerfilDelEncargo.describir(perfil.path),
        contains(perfil.path),
      );
    });

    test('los plugins puestos salen con su versión', () async {
      inventario('''
{"version":2,"plugins":{
  "flash-flutter@flash-g66":[{"scope":"user","version":"0.2.179"}]}}
''');

      final dicho = await ElPerfilDelEncargo.describir(perfil.path);

      expect(dicho, contains('flash-flutter@flash-g66 0.2.179'));
    });

    // «No tiene ninguno» también es información: sin decirlo, el modelo vuelve
    // a suponer.
    test('sin plugins se dice que no hay, no se calla', () async {
      inventario('{"version":2,"plugins":{}}');

      expect(
        await ElPerfilDelEncargo.describir(perfil.path),
        contains('No tiene ningún plugin puesto'),
      );
    });

    // El alcance solo cuando hay más de uno del mismo plugin: decirlo siempre
    // es ruido en un texto que viaja en cada encargo.
    test('el alcance se dice solo cuando hay dos del mismo', () async {
      inventario('''
{"version":2,"plugins":{
  "uno@x":[{"scope":"user","version":"1.0.0"}],
  "dos@x":[{"scope":"user","version":"2.0.0"},
           {"scope":"project","version":"1.9.0"}]}}
''');

      final dicho = await ElPerfilDelEncargo.describir(perfil.path);

      expect(dicho, contains('uno@x 1.0.0'));
      expect(dicho, contains('dos@x 2.0.0 (user)'));
      expect(dicho, contains('dos@x 1.9.0 (project)'));
    });

    // El inventario es un extra del prompt, no el encargo: un archivo roto o
    // ausente no puede costar la respuesta.
    test('un inventario roto o ausente no tumba el encargo', () async {
      expect(
        await ElPerfilDelEncargo.describir(perfil.path),
        contains('No tiene ningún plugin puesto'),
      );

      inventario('no es json');
      expect(
        await ElPerfilDelEncargo.describir(perfil.path),
        contains('No tiene ningún plugin puesto'),
      );
    });
  });

  group('qué carpeta es', () {
    test('con perfil elegido, el elegido', () {
      expect(ElPerfilDelEncargo.carpeta('/x/.claude-work'), '/x/.claude-work');
    });

    // Misma regla que `ClaudeEnvironment.forProfile`: sin perfil no se inventa
    // la variable, así que manda la del entorno y en último caso el directorio
    // de fábrica. Decir aquí otra cosa nombraría en el prompt una carpeta
    // distinta de la que se va a usar.
    test('sin perfil, lo que vaya a usar el CLI de verdad', () {
      final env = Platform.environment;
      final esperado = env['CLAUDE_CONFIG_DIR']?.isNotEmpty == true
          ? env['CLAUDE_CONFIG_DIR']
          : '${env['HOME']}/.claude';

      expect(ElPerfilDelEncargo.carpeta(null), esperado);
      expect(ElPerfilDelEncargo.carpeta(''), esperado);
    });
  });
}

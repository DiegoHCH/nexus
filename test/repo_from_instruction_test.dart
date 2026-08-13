import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/domain/usecases/repo_from_instruction.dart';

void main() {
  const repos = [
    '/Users/alguien/Workspace/front-mobile-b2c',
    '/Users/alguien/Workspace/backend-core',
  ];

  test('nombrar un repo coloca a Claude dentro', () {
    expect(
      RepoFromInstruction.resolve(
        'arregla el login de front-mobile-b2c',
        repos,
      ),
      '/Users/alguien/Workspace/front-mobile-b2c',
    );
  });

  // Por voz la transcripción nunca trae los guiones, y quien escribe tampoco
  // los pone siempre: las dos formas tienen que encontrar el mismo repo.
  test('da igual cómo se escriba el nombre', () {
    for (final frase in [
      'mira el front mobile b2c',
      'MIRA EL FRONT-MOBILE-B2C',
      'revisa front_mobile_b2c y dime',
    ]) {
      expect(
        RepoFromInstruction.resolve(frase, repos),
        '/Users/alguien/Workspace/front-mobile-b2c',
        reason: frase,
      );
    }
  });

  test('sin nombrar ninguno, no se mueve', () {
    expect(RepoFromInstruction.resolve('¿qué cambios tengo?', repos), isNull);
  });

  // Colocarse en el repo equivocado es peor que quedarse en la raíz: desde la
  // raíz se ve todo, y desde el repo que no era, nada de lo que importa.
  test('con dos nombrados no se elige ninguno', () {
    expect(
      RepoFromInstruction.resolve(
        'compara front-mobile-b2c con backend-core',
        repos,
      ),
      isNull,
    );
  });

  test('un nombre corto no se busca dentro de otras palabras', () {
    // `ui` aparecería en «cuidado», «construir», «Luis»…
    expect(
      RepoFromInstruction.resolve('ten cuidado con eso', [
        '/Users/alguien/Workspace/ui',
      ]),
      isNull,
    );
  });

  test('sin repos dentro no hay nada que resolver', () {
    expect(RepoFromInstruction.resolve('lo que sea', const []), isNull);
  });
}

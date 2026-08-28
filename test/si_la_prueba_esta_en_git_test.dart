import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';

/// Si un flow está en git, que es lo que decide si borrarlo se puede deshacer.
///
/// El aviso del panel prometía «se recupera con git» siempre. Con un flow recién
/// escrito y sin commitear eso es falso justo cuando más importa, así que ahora se
/// pregunta. Y no saber tiene que ser su propia respuesta: decir «no está en git»
/// porque no hay repositorio sería inventarse una.
void main() {
  const ds = E2eDataSource();

  late Directory casa;
  setUp(() => casa = Directory.systemTemp.createTempSync('engit'));
  tearDown(() => casa.deleteSync(recursive: true));

  Future<void> git(List<String> argumentos) =>
      Process.run('git', ['-C', casa.path, ...argumentos]);

  test('un flow commiteado se puede recuperar', () async {
    await git(['init', '-q']);
    await git(['config', 'user.email', 'nadie@ejemplo.com']);
    await git(['config', 'user.name', 'Nadie']);
    final flow = File('${casa.path}/login.yaml')..writeAsStringSync('appId: x');
    await git(['add', 'login.yaml']);
    await git(['commit', '-qm', 'add flow']);

    expect(await ds.estaEnGit(flow.path), isTrue);
  });

  test('uno sin commitear, no', () async {
    await git(['init', '-q']);
    final flow = File('${casa.path}/login.yaml')..writeAsStringSync('appId: x');

    expect(await ds.estaEnGit(flow.path), isFalse);
  });

  test('fuera de un repositorio no se sabe, y eso no es «no»', () async {
    // Sin repositorio, git sale con 128. Devolver `false` ahí haría que el aviso
    // dijera «esto se pierde» sin tener ni idea.
    final flow = File('${casa.path}/login.yaml')..writeAsStringSync('appId: x');

    expect(await ds.estaEnGit(flow.path), isNull);
  });

  test('una ruta sin carpeta tampoco se puede preguntar', () async {
    expect(await ds.estaEnGit('login.yaml'), isNull);
  });
}

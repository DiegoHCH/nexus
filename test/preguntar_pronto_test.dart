import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/data/datasources/artifacts_data_source.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preguntar en el primer instante.
///
/// El teléfono no es una pantalla: **pide una vez y se queda con la respuesta**. Los
/// dos ajustes que le hacen falta —dónde está el vault de conversaciones y dónde la
/// carpeta de documentos— se leen del disco de forma asíncrona, y sus notifiers
/// devuelven «nada configurado» mientras esa lectura va de camino.
///
/// En el escritorio eso no se nota: su pantalla sigue mirando y se redibuja cuando
/// llegan. Por red, la primera respuesta es la única, y era «no hay nada» — una
/// conversación en vez de treinta y una, cero documentos habiendo uno.
///
/// Estas pruebas piden **sin dar ninguna vuelta de más**, que es la única forma de
/// reproducirlo: con un `pump` de sobra, la carga ya ha terminado y todo parece bien.
void main() {
  // Sin binding, `SharedPreferences` no tiene con quien hablar y la carga falla — y
  // como la carga se traga sus errores a proposito, el sintoma seria identico al del
  // fallo que se esta midiendo. Es la clase de coincidencia que hace pasar una prueba
  // por el motivo equivocado.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporal;
  late Directory soporte;

  setUp(() {
    temporal = Directory.systemTemp.createTempSync('preguntar-pronto');
    // El almacen propio de la app pregunta al sistema donde vive, y en una prueba no
    // hay sistema: sin esto la lectura no falla, se **cuelga**, y el sintoma es un
    // plazo agotado en vez de una lista vacia.
    soporte = Directory.systemTemp.createTempSync('preguntar-pronto-soporte');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => soporte.path,
        );
  });
  tearDown(() {
    temporal.deleteSync(recursive: true);
    soporte.deleteSync(recursive: true);
  });

  test('los artifacts se ven aunque se pregunte al arrancar', () async {
    File('${temporal.path}/informe.md').writeAsStringSync('# algo');
    SharedPreferences.setMockInitialValues({
      'flutter.artifacts.folder': temporal.path,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Lo que hace la superficie remota: esperar la carga y **luego** leer. Sin la
    // espera, esta misma lectura devuelve la lista vacia.
    await container.read(artifactsFolderProvider.notifier).cargada;
    final lista = await container.read(artifactsProvider.future);

    expect(
      lista.map((a) => a.name),
      contains('informe.md'),
      reason:
          'la carpeta estaba configurada; devolver vacio es decir que no hay '
          'documentos cuando lo que pasa es que aun no se habia leido donde estan',
    );
  });

  test('los artifacts se buscan tambien en la carpeta de cada cuenta', () async {
    // La carpeta real esta dividida por perfil, y ademas tiene bolsas de recursos al
    // lado —`assets-*`— que no son documentos. Se baja **solo** a las cuentas: bajar
    // a todo meteria en la lista cada imagen que un mockup arrastra consigo.
    File('${temporal.path}/en-la-raiz.html').writeAsStringSync('<p>a</p>');
    Directory('${temporal.path}/work').createSync();
    File('${temporal.path}/work/de-work.html').writeAsStringSync('<p>b</p>');
    Directory('${temporal.path}/assets-mockup').createSync();
    File('${temporal.path}/assets-mockup/logo.png').writeAsStringSync('x');

    final lista = await const ArtifactsDataSource().list(
      temporal.path,
      cuentas: const {'work', 'private'},
    );
    final nombres = lista.map((a) => a.name).toList();

    expect(nombres, contains('en-la-raiz.html'));
    expect(
      nombres,
      contains('de-work.html'),
      reason:
          'sin bajar a la carpeta de la cuenta, la lista enseña cero habiendo '
          'treinta y seis: es donde estan de verdad',
    );
    expect(
      nombres,
      isNot(contains('logo.png')),
      reason:
          'assets-mockup no es una cuenta; entrar ahi es justo lo que el "un '
          'nivel" queria evitar',
    );
    // Y cada uno sabe de quien es, que es lo que dibuja los botones.
    expect(lista.firstWhere((a) => a.name == 'de-work.html').account, 'work');
    expect(
      lista.firstWhere((a) => a.name == 'en-la-raiz.html').account,
      isNull,
    );

    // Una cuenta que no existe como carpeta no molesta: `private` no esta.
    expect(nombres, hasLength(2));
  });

  test('el archivo suma el vault aunque se pregunte al arrancar', () async {
    // Una conversación en el vault, con la forma que el lector espera:
    // vault/cuenta/proyecto/conversación.md
    final nota = Directory('${temporal.path}/work/api')
      ..createSync(recursive: true);
    // Con el frontmatter que el lector del vault exige —`proyecto` y `fecha`—: sin
    // el, una nota no es una conversacion y se ignora, que es lo correcto (un vault
    // esta lleno de notas que no lo son) y lo que hacia fallar a esta prueba por el
    // motivo equivocado.
    File('${nota.path}/una-de-antes.md').writeAsStringSync(
      '---\n'
      'proyecto: /Users/alguien/api\n'
      'fecha: 2026-08-01T10:00:00.000\n'
      '---\n\n'
      '# Una de antes\n\n## Tu\n\nrevisa el diff\n',
    );
    SharedPreferences.setMockInitialValues({
      'flutter.archive_destination': 'obsidian',
      'flutter.archive_folder': temporal.path,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(archiveControllerProvider.notifier).cargado;
    final todas = await container.read(allSavedConversationsProvider.future);

    expect(
      todas,
      isNotEmpty,
      reason:
          'el vault estaba configurado y tenia una conversacion; devolver solo el '
          'almacen propio es el fallo que hacia que el telefono enseñara una',
    );
  });

  test('la superficie remota espera esas cargas antes de contestar', () {
    // La prueba de arriba mide el mecanismo; esta mide que **se use**. El fallo no
    // fue que el mecanismo no existiera: fue que nadie esperaba nada, y una lista
    // vacia por preguntar pronto se lee exactamente igual que una lista vacia.
    final remoto = File(
      'lib/features/remote/presentation/assistant_surface.dart',
    ).readAsStringSync();

    for (final (metodo, espera) in const [
      ('archive', 'archiveControllerProvider.notifier).cargado'),
      ('resumeConversation', 'archiveControllerProvider.notifier).cargado'),
      ('artifacts', 'artifactsFolderProvider.notifier).cargada'),
      ('artifact', 'artifactsFolderProvider.notifier).cargada'),
    ]) {
      final desde = remoto.indexOf('$metodo(');
      expect(desde, isNot(-1), reason: 'no encontre $metodo');
      final cuerpo = remoto.substring(desde, remoto.indexOf('\n  }\n', desde));
      expect(
        cuerpo,
        contains(espera),
        reason:
            '$metodo contesta sin esperar a que el ajuste este leido: por red '
            'esa respuesta es la unica, y sera vacia si llega pronto',
      );
    }
  });
}

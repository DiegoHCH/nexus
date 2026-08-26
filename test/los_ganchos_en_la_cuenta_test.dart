import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/data/datasources/hooks_data_source.dart';
import 'package:nexus/features/superpowers/domain/entities/nexus_hook.dart';

/// Instalar los ganchos de Nexus en una cuenta, que hasta ahora se hacía a mano.
///
/// Lo que se prueba aquí es **lo que puede romperse callado**, que en este archivo es casi
/// todo: el `settings.json` de una cuenta no es nuestro —lleva el modelo, los permisos y
/// los ganchos que haya puesto otra cosa— y escribirlo mal no da ningún error: deja al CLI
/// arrancando sin nada de eso. Y media instalación —el archivo sin la entrada, o al
/// revés— tampoco falla: simplemente el gancho no corre nunca.
void main() {
  late Directory cuenta;
  late Directory otra;

  /// La fuente de mentira: así la instalación entera se prueba sin levantar el bundle de
  /// Flutter, y además se puede cambiar el contenido para simular una versión nueva.
  var traeLaApp = '#!/usr/bin/env python3\nprint("hola")\n';
  HooksDataSource elInstalador() =>
      HooksDataSource(leer: (_) async => traeLaApp);

  final gancho = NexusHook.porId('exigir_plan')!;
  final otroGancho = NexusHook.porId('inyectar_reglas')!;

  setUp(() {
    traeLaApp = '#!/usr/bin/env python3\nprint("hola")\n';
    cuenta = Directory.systemTemp.createTempSync('cuenta');
    otra = Directory.systemTemp.createTempSync('otra-cuenta');
  });

  tearDown(() {
    cuenta.deleteSync(recursive: true);
    otra.deleteSync(recursive: true);
  });

  Map<String, Object?> ajustesDe(Directory dir) {
    final archivo = File('${dir.path}/settings.json');
    if (!archivo.existsSync()) return const {};
    return (jsonDecode(archivo.readAsStringSync()) as Map).cast();
  }

  void escribirAjustes(Directory dir, Object contenido) =>
      File('${dir.path}/settings.json').writeAsStringSync(
        contenido is String ? contenido : jsonEncode(contenido),
      );

  /// Los comandos que el CLI llamaría para ese evento.
  List<String> comandosDe(Directory dir, String evento) => [
    for (final grupo
        in ((ajustesDe(dir)['hooks'] as Map?)?[evento] as List? ?? const []))
      for (final entrada in (grupo as Map)['hooks'] as List)
        (entrada as Map)['command'] as String,
  ];

  test('instalar deja las dos mitades: el archivo y quien lo llama', () async {
    expect(await elInstalador().install(cuenta.path, gancho), isNull);

    final script = File(gancho.rutaEn(cuenta.path));
    expect(script.existsSync(), isTrue);
    expect(script.readAsStringSync(), traeLaApp);
    expect(comandosDe(cuenta, 'PreToolUse'), [script.path]);
  });

  test('y el archivo queda ejecutable, porque el comando es la ruta pelada', () async {
    await elInstalador().install(cuenta.path, gancho);

    // Sin el bit de ejecución el CLI dice «permission denied» en cada turno, y nadie
    // relaciona eso con la pantalla de Superpoderes.
    final modo = await Process.run('stat', [
      '-f',
      '%Lp',
      gancho.rutaEn(cuenta.path),
    ]);
    expect((modo.stdout as String).trim(), '755');
  });

  test('la entrada lleva el matcher y el timeout del catálogo', () async {
    await elInstalador().install(
      cuenta.path,
      otroGancho,
      statusMessage: 'Cargando las reglas…',
    );

    final grupo =
        (((ajustesDe(cuenta)['hooks'] as Map)['PreToolUse'] as List).single
            as Map);
    expect(grupo['matcher'], otroGancho.matcher);
    final entrada = (grupo['hooks'] as List).single as Map;
    expect(entrada['type'], 'command');
    expect(entrada['timeout'], otroGancho.timeout);
    expect(entrada['statusMessage'], 'Cargando las reglas…');
  });

  test('no se pierde nada de lo que ya había en el settings.json', () async {
    escribirAjustes(cuenta, {
      'model': 'opus',
      'permissions': {
        'deny': ['Bash(rm:*)'],
      },
      'hooks': {
        'UserPromptSubmit': [
          {
            'hooks': [
              {'type': 'command', 'command': 'echo ajeno'},
            ],
          },
        ],
      },
    });

    await elInstalador().install(cuenta.path, gancho);

    final ajustes = ajustesDe(cuenta);
    expect(ajustes['model'], 'opus');
    expect(ajustes['permissions'], isNotNull);
    // El gancho de otra cosa sigue ahí: este archivo no es nuestro.
    expect(comandosDe(cuenta, 'UserPromptSubmit'), ['echo ajeno']);
    expect(comandosDe(cuenta, 'PreToolUse'), hasLength(1));
  });

  test('reinstalar no deja dos entradas llamando al mismo script', () async {
    await elInstalador().install(cuenta.path, gancho);
    await elInstalador().install(cuenta.path, gancho);
    await elInstalador().install(cuenta.path, gancho);

    // Con tres entradas el CLI correría el mismo gancho tres veces por edición, y eso
    // en el que deniega significa tres denegaciones por lo mismo.
    expect(comandosDe(cuenta, 'PreToolUse'), hasLength(1));
  });

  test('los dos ganchos conviven', () async {
    await elInstalador().install(cuenta.path, gancho);
    await elInstalador().install(cuenta.path, otroGancho);

    expect(comandosDe(cuenta, 'PreToolUse'), hasLength(2));
    expect(
      await elInstalador().estado(cuenta.path, gancho),
      EstadoDelGancho.alDia,
    );
    expect(
      await elInstalador().estado(cuenta.path, otroGancho),
      EstadoDelGancho.alDia,
    );
  });

  test('quitar se lleva las dos mitades y no deja el hueco puesto', () async {
    await elInstalador().install(cuenta.path, gancho);

    expect(await elInstalador().remove(cuenta.path, gancho), isNull);
    expect(File(gancho.rutaEn(cuenta.path)).existsSync(), isFalse);
    // Sin `hooks` en absoluto: un `"PreToolUse": []` convierte «no tengo ganchos» en un
    // archivo que parece tenerlos.
    expect(ajustesDe(cuenta).containsKey('hooks'), isFalse);
  });

  test('quitar el nuestro no se lleva el de otro que compartía entrada', () async {
    await elInstalador().install(cuenta.path, gancho);
    final ajustes = ajustesDe(cuenta);
    final grupo =
        ((ajustes['hooks'] as Map)['PreToolUse'] as List).single as Map;
    (grupo['hooks'] as List).add({'type': 'command', 'command': 'echo ajeno'});
    escribirAjustes(cuenta, ajustes);

    await elInstalador().remove(cuenta.path, gancho);

    expect(comandosDe(cuenta, 'PreToolUse'), ['echo ajeno']);
  });

  test('el estado distingue las cuatro formas de estar', () async {
    final instalador = elInstalador();
    expect(
      await instalador.estado(cuenta.path, gancho),
      EstadoDelGancho.ausente,
    );

    await instalador.install(cuenta.path, gancho);
    expect(await instalador.estado(cuenta.path, gancho), EstadoDelGancho.alDia);

    // Una versión nueva de Nexus trae otro script.
    traeLaApp = '#!/usr/bin/env python3\nprint("adios")\n';
    expect(
      await instalador.estado(cuenta.path, gancho),
      EstadoDelGancho.desactualizado,
    );
  });

  test('el archivo sin la entrada es «a medias», que es el fallo invisible', () async {
    await elInstalador().install(cuenta.path, gancho);
    escribirAjustes(cuenta, {'model': 'opus'});

    // Nada falla, nada avisa, y el gancho no corre nunca. Por eso tiene nombre propio.
    expect(
      await elInstalador().estado(cuenta.path, gancho),
      EstadoDelGancho.aMedias,
    );
  });

  test('la entrada sin el archivo también es «a medias»', () async {
    await elInstalador().install(cuenta.path, gancho);
    File(gancho.rutaEn(cuenta.path)).deleteSync();

    expect(
      await elInstalador().estado(cuenta.path, gancho),
      EstadoDelGancho.aMedias,
    );
  });

  test('un settings.json ilegible se dice y no se pisa', () async {
    escribirAjustes(cuenta, '{ esto no es json');

    final error = await elInstalador().install(cuenta.path, gancho);

    expect(error, isNotNull);
    // Lo importante no es el mensaje: es que el archivo de la cuenta siga como estaba.
    // Sobrescribirlo sería perder el modelo y los permisos de alguien por poner un gancho.
    expect(
      File('${cuenta.path}/settings.json').readAsStringSync(),
      '{ esto no es json',
    );
  });

  test('en varias cuentas de una vez, y los fallos se dicen por cuenta', () async {
    final fallos = await elInstalador().installEn([
      cuenta.path,
      otra.path,
    ], gancho);

    expect(fallos, isEmpty);
    expect(comandosDe(cuenta, 'PreToolUse'), hasLength(1));
    expect(comandosDe(otra, 'PreToolUse'), hasLength(1));
  });

  test('instalar en dos y fallar en una no es no instalar en ninguna', () async {
    escribirAjustes(otra, '{ roto');

    final fallos = await elInstalador().installEn([
      cuenta.path,
      otra.path,
    ], gancho);

    expect(fallos.keys, [otra.path]);
    expect(comandosDe(cuenta, 'PreToolUse'), hasLength(1));
  });

  test('y lo que se instala de verdad es el script, no un texto de prueba', () async {
    // El único trozo que las demás pruebas sustituyen por una función de mentira es de
    // dónde sale el archivo. Aquí se usa el de verdad —el bundle— porque el fallo que
    // queda por cubrir es justo ese: una clave de asset mal escrita compila, pasa todo lo
    // anterior, y en la app deja el botón de instalar dando un error que nadie espera.
    TestWidgetsFlutterBinding.ensureInitialized();

    expect(await const HooksDataSource().install(cuenta.path, gancho), isNull);

    final puesto = File(gancho.rutaEn(cuenta.path)).readAsStringSync();
    expect(puesto, startsWith('#!/usr/bin/env python3'));
    expect(puesto, File(gancho.asset).readAsStringSync());
    expect(
      await const HooksDataSource().estado(cuenta.path, gancho),
      EstadoDelGancho.alDia,
    );
  });

  test('cada gancho del catálogo viaja dentro de la app', () async {
    // Añadir uno al catálogo y olvidarse del archivo no falla al compilar: falla al
    // pulsar «Instalar», en la máquina de alguien.
    for (final hook in NexusHook.catalogo) {
      expect(
        File(hook.asset).existsSync(),
        isTrue,
        reason: 'falta ${hook.asset}',
      );
    }
    // Y el bundle tiene que repartirlos: sin esta línea en el pubspec, la app compilada
    // no los lleva y solo se nota fuera del repo.
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/hooks/'));
  });
}

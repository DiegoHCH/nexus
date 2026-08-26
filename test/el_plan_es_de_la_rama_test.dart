import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/plan_firmado_data_source.dart';

/// La firma es de la rama, y los dos lados tienen que llamarla igual.
///
/// **Este archivo cubre el punto donde esto se rompe callado.** La app guarda la firma
/// bajo un nombre de rama y el hook la busca por otro: no falla nada, no avisa nada, el
/// gate deniega para siempre y el motivo es invisible — o peor, coincide por casualidad en
/// la rama principal y falla en la primera `feat/…`.
///
/// No comparten código: la app está en Dart y el hook en Python, y cada uno le pregunta a
/// git por su cuenta. Así que lo único que puede sostener esa regla es esto: montar un
/// repositorio de verdad y hacer que los dos contesten sobre él.
void main() {
  late Directory repo;
  late Directory cuenta;
  const fuente = PlanFirmadoDataSource();
  const git = GitDataSource();
  final hook = File('assets/hooks/exigir_plan.py').absolute.path;

  Future<String> enElRepo(List<String> args) async {
    final hecho = await Process.run('git', [
      '-C',
      repo.path,
      ...args,
    ], environment: {'GIT_CONFIG_GLOBAL': '/dev/null'});
    expect(hecho.exitCode, 0, reason: 'git ${args.join(' ')}: ${hecho.stderr}');
    return (hecho.stdout as String).trim();
  }

  setUp(() async {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
    await enElRepo(['init', '-b', 'develop']);
    await enElRepo(['config', 'user.email', 'nadie@ejemplo.test']);
    await enElRepo(['config', 'user.name', 'Nadie']);
    File('${repo.path}/README.md').writeAsStringSync('hola\n');
    await enElRepo(['add', '.']);
    await enElRepo(['commit', '-m', 'primero']);
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  /// `true` si el hook dejaría escribir **ahora mismo, en la rama que haya**.
  Future<bool> elHookDejaEscribir([String? donde]) async {
    final cwd = donde ?? repo.path;
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: cwd,
      environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': cwd,
        'tool_name': 'Edit',
        'tool_input': {'file_path': 'lib/algo.dart'},
      }),
    );
    await proceso.stdin.close();
    final texto = await proceso.stdout.transform(utf8.decoder).join();
    await proceso.exitCode;
    if (texto.trim().isEmpty) return true;
    return jsonDecode(texto)['hookSpecificOutput']['permissionDecision'] !=
        'deny';
  }

  /// Firma como lo haría la pantalla: con la rama que la app cree que es.
  Future<void> firmarComoLaApp(String frase, {String? enLaRama}) async {
    final rama = enLaRama ?? (await git.read(repo.path))!.branch;
    await fuente.guardar(
      cuenta.path,
      PlanFirmado(
        carpeta: repo.path,
        rama: rama,
        exige: true,
        plan: frase,
        firmado: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> exigirPlan() => fuente.guardar(
    cuenta.path,
    PlanFirmado(carpeta: repo.path, exige: true),
  );

  test('firmada una rama, el hook deja escribir en ella', () async {
    await firmarComoLaApp('mover la validación al dominio');
    expect(await elHookDejaEscribir(), isTrue);
  });

  test('y en otra rama deniega, aunque la carpeta sea la misma', () async {
    await firmarComoLaApp('mover la validación al dominio');
    await enElRepo(['switch', '-c', 'feat/otra-cosa']);

    // Es el punto entero de este cambio: la firma dice qué se va a hacer, y en otra rama
    // se está haciendo otra cosa.
    expect(await elHookDejaEscribir(), isFalse);
  });

  test('volver a la rama recupera su firma: irse no la borra', () async {
    await firmarComoLaApp('mover la validación al dominio');
    await enElRepo(['switch', '-c', 'hotfix/lo-urgente']);
    await firmarComoLaApp('arreglar el crash del login');

    await enElRepo(['switch', 'develop']);

    // Lo que antes se perdía. Con una sola firma por carpeta, atender una urgencia
    // borraba el plan de lo que estabas haciendo y al volver había que firmar otra vez
    // algo que seguía siendo verdad.
    expect(await elHookDejaEscribir(), isTrue);
    final leido = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
    expect(leido!.plan, 'mover la validación al dominio');

    // Y la otra sigue firmada con lo suyo, no con lo de esta.
    final urgente = await fuente.leer(
      cuenta.path,
      repo.path,
      rama: 'hotfix/lo-urgente',
    );
    expect(urgente!.plan, 'arreglar el crash del login');
  });

  test('la app y el hook llaman igual a una rama con barras', () async {
    // `feat/algo` es el nombre normal aquí, y es justo el que rompería un guardado que
    // use el nombre de la rama como parte de una ruta.
    await enElRepo(['switch', '-c', 'feat/las-barras/y-mas']);
    await firmarComoLaApp('lo de las barras');
    expect(await elHookDejaEscribir(), isTrue);
  });

  test('con HEAD suelta los dos usan el commit corto', () async {
    // Un checkout a un commit o a una etiqueta: git contesta literalmente «HEAD», que no
    // distingue un commit de otro. Si un lado guardara bajo «HEAD» y el otro bajo el
    // commit, el gate denegaría sin explicación.
    final commit = await enElRepo(['rev-parse', '--short', 'HEAD']);
    await enElRepo(['switch', '--detach', 'HEAD']);

    expect((await git.read(repo.path))!.branch, commit);
    await firmarComoLaApp('trabajando sobre un commit suelto');
    expect(await elHookDejaEscribir(), isTrue);
  });

  test('desde un subdirectorio se ve la misma rama del repo', () async {
    // El encargo puede arrancar más abajo que la raíz, y ahí la marca de la carpeta de
    // arriba sigue mandando: la rama tiene que salir igual.
    final dentro = Directory('${repo.path}/lib/features')
      ..createSync(recursive: true);
    await firmarComoLaApp('algo de dentro');

    expect(await elHookDejaEscribir(dentro.path), isTrue);
  });

  test('exigir plan sin firmar deniega en todas las ramas', () async {
    await exigirPlan();
    expect(await elHookDejaEscribir(), isFalse);
    await enElRepo(['switch', '-c', 'feat/otra']);
    expect(await elHookDejaEscribir(), isFalse);
  });

  test('encender y apagar la exigencia no se lleva las firmas', () async {
    await firmarComoLaApp('la frase del plan');

    // El interruptor de Ajustes no sabe de ramas —la exigencia es de la carpeta— así que
    // escribe sin rama. Si eso pisara el archivo, apagar y encender borraría el trabajo
    // firmado de todas las ramas sin decir nada.
    await fuente.guardar(
      cuenta.path,
      PlanFirmado(carpeta: repo.path, exige: false),
    );
    await fuente.guardar(
      cuenta.path,
      PlanFirmado(carpeta: repo.path, exige: true),
    );

    expect(await elHookDejaEscribir(), isTrue);
  });

  test('el formato viejo se lee como sin firmar, no como firmado en todas', () async {
    // Una firma suelta en la raíz del archivo es de antes de que esto fuera por rama.
    // Heredarla en todas las ramas sería exactamente el fallo que este cambio arregla,
    // así que se pide firmar una vez más — y `exige` se respeta.
    File('${cuenta.path}/nexus-planes/vieja.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'carpeta': repo.path,
          'exige': true,
          'plan': 'lo de antes del cambio',
          'firmado': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
      );

    expect(await elHookDejaEscribir(), isFalse);
    final leido = await fuente.leer(cuenta.path, repo.path, rama: 'develop');
    expect(leido!.exige, isTrue);
    expect(leido.plan, isNull);
  });

  test('la firma dura la jornada, no la hora', () async {
    await fuente.guardar(
      cuenta.path,
      PlanFirmado(
        carpeta: repo.path,
        rama: 'develop',
        exige: true,
        plan: 'algo de esta mañana',
        firmado: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
      ),
    );

    // Tres horas dentro de una tarea real no son motivo para volver a firmar: con la
    // hora de antes, dos días de trabajo se firmaban dieciséis veces.
    expect(await elHookDejaEscribir(), isTrue);
  });

  test('pero al día siguiente ya no vale', () async {
    await fuente.guardar(
      cuenta.path,
      PlanFirmado(
        carpeta: repo.path,
        rama: 'develop',
        exige: true,
        plan: 'lo de ayer',
        firmado: DateTime.now().toUtc().subtract(const Duration(hours: 9)),
      ),
    );

    expect(await elHookDejaEscribir(), isFalse);
  });
}

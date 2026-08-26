import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/domain/usecases/la_corrida.dart';

/// «Verde» y «declarado» no son lo mismo, y todo lo que los toca tiene que decirlo.
///
/// **Lo que se prueba es que declarar no sea una puerta trasera al verde.** Un botón que
/// pusiera el gate en verde sin más acabaría con el gate en dos días: en cuanto se puede
/// afirmar que pasó, se afirma. Así que declarar exige la salida, caduca igual que una
/// medición, y se lee distinto en el informe y en el freno del PR.
///
/// Y existe porque la alternativa era peor: sin poder declarar, quien corre las pruebas en
/// su terminal se encuentra el PR cerrado con el gate verde delante, y lo que hace es
/// desinstalar el gancho.
void main() {
  late Directory repo;
  late Directory cuenta;
  const fuente = GateDelRepoDataSource();
  const git = GitDataSource();
  const strings = NexusStringsEs();
  final hook = File('assets/hooks/frenar_publicacion.py').absolute.path;

  Future<String> enElRepo(List<String> args) async {
    final hecho = await Process.run(
      'git',
      ['-C', repo.path, ...args],
      environment: {'GIT_CONFIG_GLOBAL': '/dev/null'},
    );
    expect(hecho.exitCode, 0, reason: '${args.join(' ')}: ${hecho.stderr}');
    return (hecho.stdout as String).trim();
  }

  setUp(() async {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
    await enElRepo(['init', '-b', 'develop']);
    await enElRepo(['config', 'user.email', 'nadie@ejemplo.test']);
    await enElRepo(['config', 'user.name', 'Nadie']);
    File('${repo.path}/algo.txt').writeAsStringSync('uno\n');
    File('${repo.path}/.nexus-pruebas').writeAsStringSync('exit 0\n');
    await enElRepo(['add', '.']);
    await enElRepo(['commit', '-m', 'primero']);
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  Future<GateDelRepo> elGate() =>
      fuente.leer(cuenta.path, repo.path, rama: 'develop');

  Future<GateDelRepo> declarar(String salida) async => fuente.declarar(
    cuenta.path,
    await elGate(),
    salida: salida,
    huella: await git.huellaDelArbol(repo.path),
  );

  Future<GateDelRepo> correr() async => fuente.correr(
    cuenta.path,
    await elGate(),
    huella: await git.huellaDelArbol(repo.path),
  );

  group('declarar', () {
    test('sin salida no registra nada', () async {
      // Es lo único que separa esto de un botón que pone el gate en verde.
      final despues = await declarar('   ');
      expect(despues.resultado, ResultadoDelGate.sinCorrer);
      expect((await elGate()).resultado, ResultadoDelGate.sinCorrer);
    });

    test('con la salida queda verde, pero dicho por una persona', () async {
      await declarar('00:12 +940: All tests passed!');

      final leido = await elGate();
      expect(leido.resultado, ResultadoDelGate.verde);
      expect(leido.quien, QuienCorrioElGate.laPersona);
      expect(leido.quien.medido, isFalse);
      // Y no se enseña como verde en ninguna parte: eso lo decide `verdeMedido`.
      expect(leido.verdeMedido, isFalse);
      expect(leido.salida, contains('All tests passed'));
    });

    test('cubre el árbol igual que una medición', () async {
      await declarar('todo en verde');
      expect(
        (await elGate()).cubre(await git.huellaDelArbol(repo.path)),
        isTrue,
      );
    });

    test('y deja de cubrir en cuanto se toca un archivo', () async {
      await declarar('todo en verde');
      File('${repo.path}/algo.txt').writeAsStringSync('uno\ndos\n');

      // Lo que cambia al declarar es **quién lo dice**, no cuánto dura.
      expect(
        (await elGate()).cubre(await git.huellaDelArbol(repo.path)),
        isFalse,
      );
    });

    test('correrlo después lo vuelve a medir', () async {
      await declarar('confía en mí');
      await correr();

      // Una medición gana siempre a una afirmación, y en ese orden.
      final leido = await elGate();
      expect(leido.quien, QuienCorrioElGate.elAgente);
      expect(leido.verdeMedido, isTrue);
    });

    test('una corrida vieja sin la clave sigue siendo una medición', () async {
      // Lo que había antes de que esto existiera se midió de verdad. Leerlo como
      // declarado degradaría el historial entero sin motivo.
      await correr();
      final crudo = Directory(
        '${cuenta.path}/nexus-pruebas',
      ).listSync().whereType<File>().single;
      final guardado = jsonDecode(crudo.readAsStringSync()) as Map;
      ((guardado['ramas'] as Map)['develop'] as Map).remove('quien');
      crudo.writeAsStringSync(jsonEncode(guardado));

      expect((await elGate()).quien, QuienCorrioElGate.elAgente);
    });
  });

  group('el informe los distingue', () {
    String resumenCon({required bool declarado}) => LaCorrida(
      rama: 'develop',
      gateVerde: true,
      gateDeclarado: declarado,
    ).resumen(strings);

    test('un verde medido y uno declarado no dicen lo mismo', () async {
      expect(resumenCon(declarado: false), contains('verde'));
      expect(resumenCon(declarado: true), contains('declarado'));
      expect(resumenCon(declarado: true), isNot(resumenCon(declarado: false)));
    });

    test('y el declarado dice quién lo corrió', () {
      expect(resumenCon(declarado: true), contains('una persona'));
    });
  });

  group('el freno del PR', () {
    Future<({String? denegado, String? contexto})> alAbrirElPr() async {
      final proceso = await Process.start(
        'python3',
        [hook],
        workingDirectory: repo.path,
        environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
      );
      proceso.stdin.write(
        jsonEncode({
          'cwd': repo.path,
          'tool_name': 'Bash',
          'tool_input': {'command': 'gh pr create --fill'},
        }),
      );
      await proceso.stdin.close();
      final texto = await proceso.stdout.transform(utf8.decoder).join();
      await proceso.exitCode;
      if (texto.trim().isEmpty) return (denegado: null, contexto: null);
      final salida = jsonDecode(texto)['hookSpecificOutput'] as Map;
      return (
        denegado: salida['permissionDecision'] == 'deny'
            ? salida['permissionDecisionReason'] as String?
            : null,
        contexto: salida['additionalContext'] as String?,
      );
    }

    test('un gate declarado deja abrir el PR', () async {
      // Sin esto, quien corre las pruebas en su terminal se encuentra la puerta cerrada
      // con el gate verde delante — y desinstala el gancho, que es perderlo todo.
      await declarar('940 pruebas, todas en verde');
      expect((await alAbrirElPr()).denegado, isNull);
    });

    test('pero lo dice, para que llegue al cuerpo del PR', () async {
      await declarar('940 pruebas, todas en verde');

      // Quien revise no puede distinguir un declarado de una corrida real, y tiene
      // derecho a saberlo: es el sitio donde la diferencia más importa.
      final contexto = (await alAbrirElPr()).contexto;
      expect(contexto, contains('declarado'));
      expect(contexto, contains('cuerpo del PR'));
    });

    test('un verde medido pasa callado, como antes', () async {
      await correr();
      final respuesta = await alAbrirElPr();
      expect(respuesta.denegado, isNull);
      expect(respuesta.contexto, isNull);
    });

    test('y declarar no salva un árbol que cambió después', () async {
      await declarar('todo en verde');
      File('${repo.path}/otra-cosa.dart').writeAsStringSync('void main() {}\n');

      expect((await alAbrirElPr()).denegado, isNotNull);
    });
  });
}

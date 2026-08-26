import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/plan_firmado_data_source.dart';

/// Que el hook lea exactamente lo que la app escribe.
///
/// **Es la prueba más importante de esta función**, y la que ninguna de las otras cubre.
/// La app está en Dart y el hook en Python; no comparten código, solo un archivo en disco.
/// Así que el formato **es** el contrato, y si una de las dos partes cambia sin la otra el
/// gate deja de bloquear **en silencio** — que es el peor final posible, porque crees que
/// estás protegido. Ya pasó una vez con el nombre del archivo.
///
/// Cada caso escribe con la app y decide con el hook. Si alguien cambia el nombre de una
/// clave en un lado, esto se cae aquí y no en producción.
void main() {
  late Directory repo;
  late Directory cuenta;
  const fuente = PlanFirmadoDataSource();
  final hook = File('assets/hooks/exigir_plan.py').absolute.path;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  /// `true` si el hook dejaría escribir.
  Future<bool> elHookDejaEscribir() async {
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: repo.path,
      environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': repo.path,
        'tool_name': 'Write',
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

  /// Escribe con la app y pregunta al hook: los dos tienen que decir lo mismo.
  Future<void> coinciden(PlanFirmado plan, {required bool dejaEscribir}) async {
    await fuente.guardar(cuenta.path, plan);
    final ahora = DateTime.now().toUtc();

    expect(
      plan.vigenteEn(ahora),
      dejaEscribir,
      reason: 'la app decide distinto de lo esperado',
    );
    expect(
      await elHookDejaEscribir(),
      dejaEscribir,
      reason: 'el hook decide distinto que la app: el contrato se rompió',
    );
  }

  test(
    'una carpeta que no exige plan deja escribir en los dos lados',
    () async {
      await coinciden(
        PlanFirmado(carpeta: repo.path, exige: false),
        dejaEscribir: true,
      );
    },
  );

  test('exige y sin firmar: los dos deniegan', () async {
    await coinciden(
      PlanFirmado(carpeta: repo.path, exige: true),
      dejaEscribir: false,
    );
  });

  test('firmado ahora: los dos dejan pasar', () async {
    await coinciden(
      PlanFirmado(
        carpeta: repo.path,
        exige: true,
        plan: 'mover la validación al dominio',
        firmado: DateTime.now().toUtc(),
      ),
      dejaEscribir: true,
    );
  });

  test('firmado y caducado: los dos deniegan', () async {
    await coinciden(
      PlanFirmado(
        carpeta: repo.path,
        exige: true,
        plan: 'lo de ayer',
        firmado: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      ),
      dejaEscribir: false,
    );
  });

  test('un plan en blanco no cuenta, en los dos lados', () async {
    // El atajo evidente para saltarse el gate. Tiene que fallar igual en la app —para
    // que la pantalla no diga «firmado»— y en el hook, que es quien manda.
    await coinciden(
      PlanFirmado(
        carpeta: repo.path,
        exige: true,
        plan: '   ',
        firmado: DateTime.now().toUtc(),
      ),
      dejaEscribir: false,
    );
  });

  test('lo escrito se vuelve a leer igual', () async {
    // Ida y vuelta por la app: si `toJson` y `fromJson` no se corresponden, la pantalla
    // enseñaría un estado y el hook aplicaría otro.
    final original = PlanFirmado(
      carpeta: repo.path,
      exige: true,
      plan: 'la frase del plan',
      firmado: DateTime.fromMillisecondsSinceEpoch(1756000000000, isUtc: true),
      vale: const Duration(minutes: 30),
    );
    await fuente.guardar(cuenta.path, original);

    final leido = await fuente.leer(cuenta.path, repo.path);
    expect(leido, isNotNull);
    expect(leido!.exige, isTrue);
    expect(leido.plan, 'la frase del plan');
    expect(leido.firmado, original.firmado);
    expect(leido.vale, const Duration(minutes: 30));
  });

  test('firmar dos veces no acumula archivos', () async {
    // Un archivo por carpeta: si cada firma dejara uno nuevo, el hook leería el primero
    // que encontrara y la última firma no sería la que manda.
    for (var i = 0; i < 3; i++) {
      await fuente.guardar(
        cuenta.path,
        PlanFirmado(
          carpeta: repo.path,
          exige: true,
          plan: 'firma $i',
          firmado: DateTime.now().toUtc(),
        ),
      );
    }

    final archivos = Directory(
      '${cuenta.path}/nexus-planes',
    ).listSync().whereType<File>().toList();
    expect(archivos, hasLength(1));
    expect((await fuente.leer(cuenta.path, repo.path))!.plan, 'firma 2');
  });

  test('la app también encuentra la marca llegando por otro nombre', () async {
    // La misma resolución de rutas que el hook: sin ella, la pantalla diría «sin plan»
    // mientras el hook lo ve firmado, o al revés.
    await fuente.guardar(
      cuenta.path,
      PlanFirmado(carpeta: repo.path, exige: true, plan: 'algo'),
    );
    final atajo = Link('${cuenta.path}/atajo')..createSync(repo.path);
    addTearDown(atajo.deleteSync);

    expect(await fuente.leer(cuenta.path, atajo.path), isNotNull);
  });
}

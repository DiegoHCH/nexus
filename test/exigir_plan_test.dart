import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No se escribe sin un plan firmado.
///
/// Un plan «firmado por una persona antes de escribir código» solo significa algo si algo
/// **se niega** mientras no lo esté. Sin eso es un texto en pantalla: se lee, se ignora, y
/// a la semana nadie lo escribe.
///
/// Se prueba **ejecutando el hook**, como el de las reglas: está en Python y leer su
/// código no demuestra que deniegue.
void main() {
  late Directory repo;
  late Directory cuenta;
  final hook = File('tool/hooks/exigir_plan.py').absolute.path;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('proyecto');
    cuenta = Directory.systemTemp.createTempSync('cuenta');
  });

  tearDown(() {
    repo.deleteSync(recursive: true);
    cuenta.deleteSync(recursive: true);
  });

  /// La marca de esta carpeta. **El nombre del archivo no importa**: la carpeta va
  /// dentro y el hook compara rutas resueltas.
  File marca() =>
      File('${cuenta.path}/nexus-planes/la-de-la-prueba.json')
        ..createSync(recursive: true);

  void marcar(Map<String, Object?> contenido) => marca().writeAsStringSync(
    jsonEncode({'carpeta': repo.path, ...contenido}),
  );

  int ahora() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// El motivo por el que denegó, o `null` si dejó pasar.
  Future<String?> alIntentarEscribir() async {
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: repo.path,
      environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': repo.path,
        'tool_name': 'Edit',
        'tool_input': {'file_path': 'lib/algo.dart'},
      }),
    );
    await proceso.stdin.close();
    final texto = await proceso.stdout.transform(utf8.decoder).join();
    await proceso.exitCode;
    if (texto.trim().isEmpty) return null;
    final salida = jsonDecode(texto)['hookSpecificOutput'] as Map;
    if (salida['permissionDecision'] != 'deny') return null;
    return salida['permissionDecisionReason'] as String?;
  }

  test('sin marca, no se pide nada', () async {
    // **Es la mitad del diseño.** El hook vive en la cuenta, así que corre en todas las
    // carpetas: si actuara por defecto, instalarlo dejaría media máquina sin poder
    // escribir. Lo enciende la carpeta, no la instalación.
    expect(await alIntentarEscribir(), isNull);
  });

  test('con la marca apagada, tampoco', () async {
    marcar({'exige': false});
    expect(await alIntentarEscribir(), isNull);
  });

  test('exige plan y no hay: deniega, y dice qué falta', () async {
    marcar({'exige': true});

    final motivo = await alIntentarEscribir();
    expect(motivo, isNotNull);
    // El motivo tiene que decir qué hacer, no solo que no se puede: un «denegado» a
    // secas manda a buscar la causa al sitio equivocado.
    expect(motivo, contains('plan'));
    expect(motivo, contains('firma'));
  });

  test('firmado y reciente: deja escribir', () async {
    marcar({
      'exige': true,
      'plan': 'mover la validación al dominio',
      'firmado': ahora(),
    });
    expect(await alIntentarEscribir(), isNull);
  });

  test('firmado hace mucho: caduca, y se dice cuánto', () async {
    // Con el mismo criterio que la frase de escritura de Nexus: un permiso que no caduca
    // deja de ser una decisión y pasa a ser un ajuste que alguien puso una vez.
    marcar({
      'exige': true,
      'plan': 'lo de ayer',
      'firmado': ahora() - 7200,
      'vale': 3600,
    });

    final motivo = await alIntentarEscribir();
    expect(motivo, contains('caduc'));
    expect(motivo, contains('120'), reason: 'no dice cuánto hace que se firmó');
  });

  test('un plan en blanco no cuenta como firmado', () async {
    // Poner la clave vacía para saltarse el gate es el atajo evidente, y tiene que
    // fallar: firmar es decir qué vas a hacer, no rellenar un campo.
    marcar({'exige': true, 'plan': '   ', 'firmado': ahora()});
    expect(await alIntentarEscribir(), isNotNull);
  });

  test('una firma sin fecha no vale', () async {
    marcar({'exige': true, 'plan': 'algo'});
    expect(await alIntentarEscribir(), contains('cuándo'));
  });

  group('un fallo propio no puede bloquear la app', () {
    test('con la marca corrupta, se deja pasar', () async {
      // **Aquí no se deniega por un fallo propio.** Un hook roto que bloquea deja la app
      // inservible y el motivo es invisible: nadie sospecha del hook. Se sale, y el
      // trabajo sigue sin la garantía — mal menor y recuperable.
      marca().writeAsStringSync('esto no es json');
      expect(await alIntentarEscribir(), isNull);
    });

    test('con basura por la entrada, sale con éxito', () async {
      marcar({'exige': true});
      final proceso = await Process.start('python3', [
        hook,
      ], workingDirectory: repo.path);
      proceso.stdin.write('no es json');
      await proceso.stdin.close();
      expect(await proceso.exitCode, 0);
    });
  });
  test('la ruta se compara resuelta, no como cadena', () async {
    // **El fallo que esto cierra**, y salió en la primera prueba contra el CLI de verdad:
    // macOS resuelve `/var` a `/private/var`, asi que la marca se guardaba con una forma
    // y el CLI reportaba la otra. El hook no la encontraba y **dejaba escribir sin plan,
    // en silencio** — el peor final posible, porque crees que estas protegido.
    //
    // La primera version codificaba la ruta en el nombre del archivo. Ahora va dentro y
    // se compara resuelta, que elimina la clase de error entera.
    final conEnlace = Link('${cuenta.path}/atajo')..createSync(repo.path);
    addTearDown(() => conEnlace.deleteSync());

    // La marca dice la ruta real y el CLI llega por el enlace: tiene que reconocerla.
    marcar({'exige': true});
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: conEnlace.path,
      environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': conEnlace.path,
        'tool_input': {'file_path': 'lib/algo.dart'},
      }),
    );
    await proceso.stdin.close();
    final texto = await proceso.stdout.transform(utf8.decoder).join();
    await proceso.exitCode;

    expect(
      texto.trim(),
      isNotEmpty,
      reason: 'llegando por otro nombre de la misma carpeta, no la reconoció',
    );
  });
}

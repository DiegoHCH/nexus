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
  final hook = File('assets/hooks/exigir_plan.py').absolute.path;

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

  /// El archivo tal como lo escribe la app: la exigencia arriba y la firma **dentro de
  /// su rama**.
  ///
  /// Las pruebas siguen escribiendo el plan en llano —`{'exige': true, 'plan': …}`— y
  /// esto lo coloca donde vive. Así cada una habla de lo suyo y no del formato, que se
  /// comprueba entero contra la app en `la_app_y_el_hook_se_entienden`.
  ///
  /// Sin rama porque estas carpetas temporales no son repositorios, que es el caso que
  /// el hook resuelve con la clave reservada.
  Map<String, Object?> conFirma(String carpeta, Map<String, Object?> campos) {
    final firma = <String, Object?>{};
    for (final clave in ['plan', 'firmado']) {
      if (campos.containsKey(clave)) firma[clave] = campos[clave];
    }
    return {
      'carpeta': carpeta,
      for (final e in campos.entries)
        if (e.key != 'plan' && e.key != 'firmado') e.key: e.value,
      if (firma.isNotEmpty) 'ramas': {':sin-rama': firma},
    };
  }

  void marcar(Map<String, Object?> contenido) =>
      marca().writeAsStringSync(jsonEncode(conFirma(repo.path, contenido)));

  int ahora() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Una marca para **otra** carpeta, con su propio archivo. Hace falta para probar que
  /// la de arriba cubre lo de dentro y que la de dentro puede contradecirla.
  void marcarOtra(String carpeta, Map<String, Object?> contenido) {
    final nombre = carpeta.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    File('${cuenta.path}/nexus-planes/$nombre.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(conFirma(carpeta, contenido)));
  }

  /// El motivo por el que denegó, o `null` si dejó pasar.
  Future<String?> alIntentarEscribirEn(String donde) async {
    final proceso = await Process.start(
      'python3',
      [hook],
      workingDirectory: donde,
      environment: {'CLAUDE_CONFIG_DIR': cuenta.path},
    );
    proceso.stdin.write(
      jsonEncode({
        'cwd': donde,
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

  Future<String?> alIntentarEscribir() => alIntentarEscribirEn(repo.path);

  group('la marca cubre lo que hay dentro de la carpeta', () {
    // El fallo que salió al encender el interruptor por primera vez en la app: Nexus
    // arranca el encargo **dentro** del repo elegido, no en la carpeta emparejada. Con
    // una raíz de varios repos, comparar rutas exactas dejaba escribir sin plan en cada
    // repo de dentro — y en silencio, que es el peor final posible para esto.
    test('un repo dentro de la carpeta también se deniega', () async {
      marcar({'exige': true});
      final dentro = Directory('${repo.path}/un-repo-dentro')
        ..createSync(recursive: true);

      expect(await alIntentarEscribirEn(dentro.path), isNotNull);
      // Y más abajo todavía: el encargo puede arrancar en cualquier subdirectorio.
      final mas = Directory('${dentro.path}/lib')..createSync(recursive: true);
      expect(await alIntentarEscribirEn(mas.path), isNotNull);
    });

    test('la marca más cercana manda sobre la de arriba', () async {
      // Apagarlo en un sitio concreto tiene que ser posible: si mandara la de arriba,
      // una excepción deliberada no se podría expresar.
      marcar({'exige': true});
      final dentro = Directory('${repo.path}/con-excepcion')
        ..createSync(recursive: true);
      marcarOtra(dentro.path, {'exige': false});

      expect(await alIntentarEscribir(), isNotNull);
      expect(await alIntentarEscribirEn(dentro.path), isNull);
    });

    test('una carpeta de al lado no se ve afectada', () async {
      // Subir hasta la raíz del sistema no puede convertir esto en un gate global.
      marcar({'exige': true});
      final vecina = Directory.systemTemp.createTempSync('vecina');
      addTearDown(() => vecina.deleteSync(recursive: true));

      expect(await alIntentarEscribirEn(vecina.path), isNull);
    });
  });

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
    expect(motivo, contains('2 horas'), reason: 'no dice cuánto hace que se firmó');
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

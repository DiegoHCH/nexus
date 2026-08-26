import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';

/// Cómo llegan las credenciales a Maestro.
///
/// **Ningún valor de aquí se parece a una credencial**, a propósito: esto se lee en
/// un PR público.
void main() {
  const ds = E2eDataSource();

  group('los argumentos que se le pasan', () {
    test('sin variables, la llamada es la de siempre', () {
      final args = E2eDataSource.argumentosDe(
        deviceId: 'emulator-5554',
        salida: '/tmp/salida',
        flow: '/repo/.maestro/login.yaml',
      );

      expect(args, [
        '--device',
        'emulator-5554',
        'test',
        '--no-ansi',
        '--debug-output',
        '/tmp/salida',
        '/repo/.maestro/login.yaml',
      ]);
    });

    test('cada variable va como un -e propio, antes del flow', () {
      final args = E2eDataSource.argumentosDe(
        deviceId: 'emulator-5554',
        salida: '/tmp/salida',
        flow: '/repo/.maestro/login.yaml',
        variables: const {'CORREO': 'a@b.c'},
      );

      expect(args, containsAllInOrder(['-e', 'CORREO=a@b.c']));
      expect(args.last, '/repo/.maestro/login.yaml');
    });

    test('un valor con un igual dentro no se parte', () {
      // Maestro corta por el primer `=`, así que un valor en base64 llega entero.
      final args = E2eDataSource.argumentosDe(
        deviceId: 'd',
        salida: '/tmp/s',
        flow: 'f.yaml',
        variables: const {'TOKEN': 'a=b=c'},
      );
      expect(args, contains('TOKEN=a=b=c'));
    });

    test('**solo llegan las del flow, no el archivo entero**', () {
      // La razón de que esto tenga prueba: los valores de `-e` se ven con `ps`, así
      // que meter en el `argv` credenciales que esta prueba no usa es exposición
      // gratis. El filtrado pasa antes, en `paraElFlow`; aquí se comprueba que lo
      // que llega es lo que se pasa y nada más.
      final variables = LasVariablesDelProyecto.paraElFlow(
        yaml: '- inputText: \${CORREO}\n',
        variables: const {'CORREO': 'a@b.c', 'OTRA': 'no-deberia-ir'},
      );
      final args = E2eDataSource.argumentosDe(
        deviceId: 'd',
        salida: '/tmp/s',
        flow: 'f.yaml',
        variables: variables,
      );

      expect(args, contains('CORREO=a@b.c'));
      expect(args.join(' '), isNot(contains('OTRA')));
      expect(args.join(' '), isNot(contains('no-deberia-ir')));
    });
  });

  group('leer el archivo del proyecto', () {
    late Directory proyecto;
    setUp(() => proyecto = Directory.systemTemp.createTempSync('proy'));
    tearDown(() => proyecto.deleteSync(recursive: true));

    test('sale del .env.local de su raíz', () {
      File('${proyecto.path}/${LasVariablesDelProyecto.archivo}')
          .writeAsStringSync('CORREO=a@b.c\n');

      expect(ds.variablesDe(proyecto.path), {'CORREO': 'a@b.c'});
    });

    test('sin archivo no es un error, es que no hay', () {
      expect(ds.variablesDe(proyecto.path), isEmpty);
    });
  });
}

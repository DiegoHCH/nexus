import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/tool_activity_reader.dart';

/// La primera prueba del proyecto, y no por casualidad: esta clase traduce lo
/// que el CLI dice a lo que el usuario lee mientras trabaja, y sus reglas se
/// rompen en silencio — nada falla, solo se lee distinto.
void main() {
  const workingDirectory = '/Users/alguien/proyecto';

  Map<String, dynamic> block(String name, Map<String, dynamic> input) => {
    'id': 'toolu_1',
    'name': name,
    'input': input,
  };

  group('delegación', () {
    // El motivo de existir de esta prueba: el CLI usa los dos nombres para la
    // misma herramienta, y atarse a uno dejaba la delegación medio invisible.
    for (final name in ['Task', 'Agent']) {
      test('$name se lee como delegación, con lo que se encargó', () {
        final used = ToolActivityReader.read(
          block(name, {
            'description': 'Revisar el historial de git',
            'prompt': 'Mira los últimos veinte commits y resume qué cambió',
            'subagent_type': 'general-purpose',
          }),
          workingDirectory: workingDirectory,
        );

        expect(used, isNotNull);
        expect(used!.description, 'Delegando: Revisar el historial de git');
        // El encargo entero queda en el detalle: es lo único que cuenta qué se
        // llevó el subagente, porque su trabajo ocurre en otro contexto.
        expect(
          used.detail,
          'Mira los últimos veinte commits y resume qué cambió',
        );
        expect(used.writes, isFalse);
      });
    }

    test('sin descripción se cae al tipo de subagente', () {
      final used = ToolActivityReader.read(
        block('Task', {'subagent_type': 'Explore', 'prompt': 'Busca X'}),
        workingDirectory: workingDirectory,
      );

      expect(used!.description, 'Delegando: Explore');
    });

    test('sin descripción ni tipo, la primera línea del encargo', () {
      final used = ToolActivityReader.read(
        block('Task', {
          'prompt': 'Busca los usos de Foo\ny dime cuáles sobran',
        }),
        workingDirectory: workingDirectory,
      );

      expect(used!.description, 'Delegando: Busca los usos de Foo');
    });

    test('sin nada que decir, no se queda «Delegando:» a medias', () {
      final used = ToolActivityReader.read(
        block('Task', const {}),
        workingDirectory: workingDirectory,
      );

      expect(used!.description, 'Delegando: una tarea');
    });
  });

  group('qué escribe y qué no', () {
    test('Write y Edit se marcan como escritura', () {
      for (final name in ['Write', 'Edit', 'MultiEdit', 'NotebookEdit']) {
        final used = ToolActivityReader.read(
          block(name, {
            'file_path': '$workingDirectory/lib/main.dart',
            'notebook_path': '$workingDirectory/lib/main.dart',
          }),
          workingDirectory: workingDirectory,
        );
        expect(used!.writes, isTrue, reason: name);
      }
    });

    // Decisión de 3.2, y esta prueba es la que la sostiene: Bash puede escribir
    // o no, y marcarlo siempre enseñaría a ignorar el aviso.
    test('Bash no se marca como escritura, ni siquiera escribiendo', () {
      final used = ToolActivityReader.read(
        block('Bash', {'command': 'echo hola > archivo.txt'}),
        workingDirectory: workingDirectory,
      );

      expect(used!.writes, isFalse);
      expect(used.description, 'Corriendo echo hola > archivo.txt');
    });
  });

  group('lo que se lee de un vistazo', () {
    test('las rutas salen relativas a la carpeta de trabajo', () {
      final used = ToolActivityReader.read(
        block('Read', {'file_path': '$workingDirectory/lib/core/theme.dart'}),
        workingDirectory: workingDirectory,
      );

      expect(used!.description, 'Leyendo lib/core/theme.dart');
      // El detalle conserva la ruta entera: la línea es para leer de reojo, el
      // detalle para saber exactamente qué se tocó.
      expect(used.detail, '$workingDirectory/lib/core/theme.dart');
    });

    test('de Bash se enseña el comando, no la description en inglés', () {
      final used = ToolActivityReader.read(
        block('Bash', {
          'command': 'git status',
          'description': 'Read repo registry',
        }),
        workingDirectory: workingDirectory,
      );

      expect(used!.description, 'Corriendo git status');
    });

    test('un bloque sin id o sin nombre no produce actividad', () {
      expect(
        ToolActivityReader.read(const {
          'name': 'Read',
        }, workingDirectory: workingDirectory),
        isNull,
      );
      expect(
        ToolActivityReader.read(const {
          'id': 'toolu_1',
        }, workingDirectory: workingDirectory),
        isNull,
      );
    });
  });
}

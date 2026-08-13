import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/domain/usecases/blocked_commands.dart';

void main() {
  group('lo que se le manda al CLI', () {
    // El comodín a los dos lados, comprobado contra el binario: el comando real
    // casi nunca empieza por el fragmento que uno recuerda —se escribe
    // `build_runner` y lo que corre es `dart run build_runner build`—.
    test('un fragmento se convierte en patrón de Bash', () {
      expect(BlockedCommands.patterns(['build_runner']), [
        'Bash(*build_runner*)',
      ]);
    });

    test('varios, y con espacios dentro', () {
      expect(BlockedCommands.patterns(['pod install', 'make generate']), [
        'Bash(*pod install*)',
        'Bash(*make generate*)',
      ]);
    });

    // Ahí lo que sobra es el conector entero, no un comando.
    test('una herramienta entera se pasa tal cual', () {
      expect(BlockedCommands.patterns(['WebFetch', 'mcp__jira']), [
        'WebFetch',
        'mcp__jira',
      ]);
    });

    test('un patrón ya escrito no se envuelve dos veces', () {
      expect(BlockedCommands.patterns(['Bash(git push*)']), [
        'Bash(git push*)',
      ]);
    });

    // Poder dejar escrito **por qué** se bloqueó algo es lo que uno agradece
    // tres meses después.
    test('los comentarios y las líneas vacías no llegan', () {
      expect(
        BlockedCommands.patterns([
          'build_runner # tarda cuatro minutos',
          '   ',
          '# solo un comentario',
        ]),
        ['Bash(*build_runner*)'],
      );
    });
  });

  group('lo que se le dice a Claude', () {
    test('sin nada bloqueado no se le dice nada', () {
      expect(BlockedCommands.notice(const []), isNull);
      expect(BlockedCommands.notice(['# nada']), isNull);
    });

    // Bloquear a secas hace que tropiece a media tarea y se calle; sabiéndolo,
    // hace lo demás y termina diciendo el comando exacto.
    test('con algo bloqueado, se le nombra y se le dice qué hacer', () {
      final aviso = BlockedCommands.notice(['build_runner', 'pod install'])!;

      expect(aviso, contains('build_runner'));
      expect(aviso, contains('pod install'));
      expect(aviso, contains('comando exacto'));
    });
  });
}

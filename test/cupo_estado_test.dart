import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_usage_data_source.dart';

/// Lo que decide este archivo, y lo único que se puede afirmar sin red: **por
/// qué no hay cifras**. Los dos estados de aquí son los que antes se decían con
/// la misma frase, y piden cosas opuestas de quien lo lee — iniciar sesión, o
/// no hacer absolutamente nada.
void main() {
  test(
    'sin token y sin sesión: no hay cuenta, y eso sí hay que decirlo',
    () async {
      final leido = await const ClaudeUsageDataSource(
        readToken: _sinToken,
        askSession: _noHaySesion,
      ).read(configDir: '/Users/alguien/.claude-private');

      expect(leido.state, UsageState.noSession);
      expect(leido.usage, isNull);
    },
  );

  test(
    'sin token pero con sesión abierta: la lectura caducó, no la cuenta',
    () async {
      // El caso de todos los días: el acceso dura horas y el refresco semanas,
      // así que cualquier cuenta que lleves un rato sin usar cae aquí. Antes
      // se anunciaba como «esa cuenta no tiene sesión abierta», que manda a
      // iniciar sesión para arreglar algo que no está roto.
      final leido = await const ClaudeUsageDataSource(
        readToken: _sinToken,
        askSession: _haySesion,
      ).read(configDir: '/Users/alguien/.claude-private');

      expect(leido.state, UsageState.staleReading);
      expect(leido.usage, isNull);
    },
  );

  test(
    'se le pregunta al CLI una sola vez, y el token se relee después',
    () async {
      // La relectura no es por si acaso: preguntarle al CLI puede hacer que
      // renueve el token, y entonces sí hay cifras que dar. Sin ella, ese caso
      // se perdería hasta la siguiente vez que se abriera el panel.
      expect(_lecturas, 0);
      await const ClaudeUsageDataSource(
        readToken: _cuentaLecturas,
        askSession: _haySesion,
      ).read(configDir: '/Users/alguien/.claude-private');

      expect(_lecturas, 2, reason: 'una antes de preguntar y otra después');
    },
  );
}

Future<String?> _sinToken(String _) async => null;
Future<bool> _noHaySesion(String _) async => false;
Future<bool> _haySesion(String _) async => true;

int _lecturas = 0;
Future<String?> _cuentaLecturas(String _) async {
  _lecturas++;
  return null;
}

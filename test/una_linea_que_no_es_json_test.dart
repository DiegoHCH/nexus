import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';

/// Una línea de texto plano en el flujo **no es el final del encargo**.
///
/// Lo era: `jsonDecode` reventaba con ella y se llevaba la petición entera. Y
/// encima disparaba el reintento sin memoria, que volvía a chocar con lo mismo
/// —así que el usuario perdía la sesión de la conversación **y** se quedaba sin
/// saber qué había pasado.
///
/// El CLI escribe texto plano justo cuando algo va mal antes de arrancar el
/// flujo, que es cuando más falta hace leerlo.
void main() {
  test('un evento del flujo se reconoce', () {
    final evento = ClaudeCliDataSource.comoJson(
      '{"type":"assistant","message":{"role":"assistant"}}',
    );

    expect(evento, isNotNull);
    expect(evento!['type'], 'assistant');
  });

  test('lo que no es JSON no revienta: se descarta', () {
    for (final linea in [
      'Failed to authenticate: OAuth session expired and could not be refreshed',
      'npm warn deprecated something@1.0.0',
      '{ esto no cierra',
    ]) {
      expect(ClaudeCliDataSource.comoJson(linea), isNull, reason: linea);
    }
  });

  // JSON válido que no es un objeto tampoco es un evento. Ya se descartaba, y
  // sigue descartándose por el mismo sitio.
  test('un JSON que no es un objeto tampoco es un evento', () {
    expect(ClaudeCliDataSource.comoJson('[1,2,3]'), isNull);
    expect(ClaudeCliDataSource.comoJson('"hola"'), isNull);
  });
}

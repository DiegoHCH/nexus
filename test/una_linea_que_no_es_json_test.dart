import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/datasources/gemini_live_data_source.dart';

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

  /// El mismo fallo, en el otro socket.
  ///
  /// La lección de arriba se aprendió en el flujo de Claude y no cruzó: el
  /// socket de Gemini seguía haciendo `jsonDecode` a pelo dentro del `onData`.
  /// Y ahí es peor que una excepción normal — **una lanzada dentro del
  /// manejador de un `listen` no llega al `onError` de esa suscripción**: sale
  /// a la zona, o sea a nadie.
  group('y en el socket de la voz', () {
    test('un marco del servicio se reconoce', () {
      final marco = GeminiLiveConnection.comoJson('{"setupComplete":{}}');

      expect(marco, isNotNull);
      expect(marco!.keys, contains('setupComplete'));
    });

    test('un marco de texto que no es JSON se descarta sin reventar', () {
      for (final marco in ['Internal error', '{"serverContent": ', '']) {
        expect(GeminiLiveConnection.comoJson(marco), isNull, reason: marco);
      }
    });

    // El socket puede entregar binario, y `utf8.decode` revienta con bytes que
    // no son UTF-8 — por eso entra en el mismo `try` que el `jsonDecode`.
    test('bytes que no son UTF-8 se descartan sin reventar', () {
      expect(GeminiLiveConnection.comoJson(const [0xC3, 0x28, 0xA9]), isNull);
    });

    test('binario que sí es JSON se lee igual', () {
      final marco = GeminiLiveConnection.comoJson(
        utf8.encode('{"toolCall":{"functionCalls":[]}}'),
      );

      expect(marco, isNotNull);
      expect(marco!.keys, contains('toolCall'));
    });

    test('un JSON que no es un objeto tampoco es un marco', () {
      expect(GeminiLiveConnection.comoJson('[1,2,3]'), isNull);
      expect(GeminiLiveConnection.comoJson('null'), isNull);
    });
  });
}

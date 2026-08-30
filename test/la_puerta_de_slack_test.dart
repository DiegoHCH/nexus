import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/history/data/datasources/slack_api.dart';

/// La quinta puerta de salida: el parte del día hacia Slack.
///
/// Lo que se prueba es lo que Slack hace mal y cuesta un fallo silencioso:
/// **contesta 200 con `ok: false`** cuando el token está mal o el destino no
/// existe. Mirar el código de estado deja a alguien creyendo que su parte se
/// envió, y un parte que no llegó al daily es peor que no haberlo escrito.

void main() {
  group('qué contestó Slack', () {
    test('un ok verdadero es que llegó', () {
      expect(SlackApi.loQueDijo('{"ok":true}'), isNull);
    });

    // El fallo silencioso, y el motivo de que esto esté separado del socket.
    test('un ok falso es un fallo, y se dice cuál', () {
      expect(
        SlackApi.loQueDijo('{"ok":false,"error":"invalid_auth"}'),
        'invalid_auth',
      );
      expect(
        SlackApi.loQueDijo('{"ok":false,"error":"channel_not_found"}'),
        'channel_not_found',
      );
    });

    test('un ok falso sin motivo tampoco pasa por bueno', () {
      expect(SlackApi.loQueDijo('{"ok":false}'), isNotNull);
    });

    // Lo que no se entiende no se da por bueno: al revés sería tragarse un
    // cambio de la API en silencio y seguir diciendo «enviado».
    test('lo que no se entiende es un fallo, no un sí', () {
      expect(SlackApi.loQueDijo(''), isNotNull);
      expect(SlackApi.loQueDijo('<html>502</html>'), isNotNull);
      expect(SlackApi.loQueDijo('[]'), isNotNull);
      expect(SlackApi.loQueDijo('{}'), isNotNull);
    });
  });

  group('lo que ni sale a la red', () {
    // Sin esto, la primera prueba de alguien sin configurar sería un viaje a
    // Slack para que Slack le diga lo que ya sabíamos aquí.
    test('sin token, sin destino o sin texto se contesta en casa', () async {
      const api = SlackApi();
      expect(await api.mandar(token: '', destino: 'U1', texto: 'x'), isNotNull);
      expect(
        await api.mandar(token: 't', destino: '  ', texto: 'x'),
        isNotNull,
      );
      expect(
        await api.mandar(token: 't', destino: 'U1', texto: ' '),
        isNotNull,
      );
    });
  });
}

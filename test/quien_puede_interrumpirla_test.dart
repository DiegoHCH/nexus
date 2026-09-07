import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';

/// Quién puede interrumpirla, que **no es igual en una conversación que en la
/// puerta**.
///
/// 🔴 **Esta prueba existe porque se rompió por ahí.** Al cerrar el audio ajeno
/// —la conversación de la habitación que el modelo contestaba— se le pidió al
/// servicio que **no interrumpiera nunca**, y eso viajó también a la puerta del
/// arranque. Reportado de oído, las dos cosas por la misma línea:
///
/// - **El saludo se volvió a oír entrecortado.** Sin `interrupted` no se tira lo
///   que quedaba por sonar, así que la cola vieja se oye pisada con la nueva. Lo
///   avisaba el propio código de la puerta, en el `case` que lo descarta.
/// - **Y abrió la carpeta sin decir la frase.** El `turnComplete` del saludo
///   llega *después* de que se sepa la carpeta, y la puerta lo toma por «acabó
///   de despedirse»: se abre el área de trabajo y la confirmación no suena.
///
/// El saludo es largo —la hora, tu nombre, la pregunta y la lista de carpetas— y
/// contestar antes de que acabe es lo normal: en la puerta, que la interrumpas
/// **es el diseño**.
void main() {
  Map<String, dynamic> comoSeEscucha(PerfilDeVoz perfil) =>
      GeminiVoiceGateway.comoSeEscucha(perfil);

  Map<String, dynamic> deteccion(PerfilDeVoz perfil) =>
      comoSeEscucha(perfil)['automaticActivityDetection']
          as Map<String, dynamic>;

  test('en una conversación, el servicio no interrumpe', () {
    const conversando = ComoUnaConversacion();

    expect(comoSeEscucha(conversando)['activityHandling'], 'NO_INTERRUPTION');
    expect(
      deteccion(conversando)['startOfSpeechSensitivity'],
      'START_SENSITIVITY_LOW',
      reason: 'la habitación no puede contar como que alguien empezó a hablar',
    );
  });

  test('en la puerta sí, que interrumpirla es el diseño', () {
    const puerta = ComoLaPuerta(saludo: 'Buenos días', carpetas: ['nexus']);

    expect(
      comoSeEscucha(puerta).containsKey('activityHandling'),
      isFalse,
      reason:
          'sin interrupción, el saludo se oye pisado y la puerta abre sin '
          'decir la frase — las dos reportadas de oído',
    );
    expect(
      deteccion(puerta).containsKey('startOfSpeechSensitivity'),
      isFalse,
      reason: 'en la puerta hay que oírte a la primera, no a la segunda',
    );
  });

  // El aviso de agenda no abre micrófono: lo que no se usa no se configura.
  test('el aviso no configura nada de escuchar', () {
    const aviso = ComoUnAviso('Reunión en cinco minutos');

    expect(comoSeEscucha(aviso).containsKey('activityHandling'), isFalse);
    expect(deteccion(aviso).containsKey('startOfSpeechSensitivity'), isFalse);
  });

  // Lo que **no** cambia por perfil, y conviene que siga así: el detector
  // alargado. Una instrucción larga tiene pausas para pensar, y con el corte de
  // fábrica el servicio se queda con media frase y contesta a eso.
  test('el detector va alargado en los tres', () {
    for (final perfil in const <PerfilDeVoz>[
      ComoUnaConversacion(),
      ComoLaPuerta(saludo: 'Buenas', carpetas: ['nexus']),
      ComoUnAviso('Reunión'),
    ]) {
      final vad = deteccion(perfil);
      expect(vad['endOfSpeechSensitivity'], 'END_SENSITIVITY_LOW');
      expect(vad['silenceDurationMs'], 1200);
      expect(
        vad['prefixPaddingMs'],
        300,
        reason: 'sin esto se come el principio de la primera palabra',
      );
    }
  });
}

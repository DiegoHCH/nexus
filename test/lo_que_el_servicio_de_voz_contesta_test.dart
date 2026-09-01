import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';

/// Lo que se anota cuando el servicio de voz manda algo que no se entiende.
///
/// Antes se tiraba con un `return` seco, y con él **lo único que el servicio
/// tenía que decir** cuando algo iba mal. Medido en el registro de la app: cinco
/// sesiones seguidas con «203 trozos del micro, 203 enviados, 1 eventos
/// recibidos · primera señal del servicio en todavía nada». Para quien usa la
/// app eso es silencio — el orbe escucha, se calla y vuelve a dormir.
void main() {
  group('qué se anota', () {
    test('las claves del marco, para saber qué llegó', () {
      final linea = GeminiVoiceGateway.loQueMandoElServicio({
        'algoNuevo': 1,
        'otraCosa': 2,
      });

      expect(linea, contains('algoNuevo'));
      expect(linea, contains('otraCosa'));
    });

    test('y el mensaje del error, que es la respuesta que se buscaba', () {
      final linea = GeminiVoiceGateway.loQueMandoElServicio({
        'error': {'code': 429, 'message': 'Quota exceeded for model'},
      });

      expect(linea, contains('Quota exceeded for model'));
    });

    test('el estado si no hay mensaje', () {
      final linea = GeminiVoiceGateway.loQueMandoElServicio({
        'error': {'status': 'RESOURCE_EXHAUSTED'},
      });

      expect(linea, contains('RESOURCE_EXHAUSTED'));
    });

    test('un error que no es un objeto también se dice', () {
      expect(
        GeminiVoiceGateway.loQueMandoElServicio({'error': 'se cayó'}),
        contains('se cayó'),
      );
    });

    test('sin error, solo las claves y sin colgar un separador vacío', () {
      final linea = GeminiVoiceGateway.loQueMandoElServicio({
        'goAwayRaro': <String, Object?>{},
      });

      expect(linea, endsWith('goAwayRaro'));
    });
  });

  // 🔴 **La razón de que esta función sea pura y pública.**
  //
  // Por ese socket viaja lo que dices y lo que Claude leyó de tu carpeta, y este
  // registro acaba en los informes de fallo. Volcar el marco entero sería sacar
  // de la máquina —por una puerta que nadie mira— exactamente lo que la app
  // promete no sacar: «nada de esa carpeta viaja a Gemini, ni siquiera el audio»
  // es una negativa, no una preferencia, y un registro que se manda por correo
  // la rompería por el otro lado.
  group('qué NO se anota', () {
    test('el contenido de lo que se dijo, jamás', () {
      final linea = GeminiVoiceGateway.loQueMandoElServicio({
        'algoNuevo': {
          'texto': 'la contraseña de producción es hunter2',
          'transcripcion': 'lo que dijo la persona en voz alta',
        },
      });

      expect(linea, contains('algoNuevo'), reason: 'la clave sí');
      expect(linea, isNot(contains('hunter2')));
      expect(linea, isNot(contains('contraseña')));
      expect(linea, isNot(contains('en voz alta')));
    });

    // Un error trae su mensaje —de eso se trata— pero no el resto del objeto:
    // un `details` de Google puede llevar dentro el fragmento que lo provocó.
    test('ni lo que acompaña a un error, solo su mensaje', () {
      final linea = GeminiVoiceGateway.loQueMandoElServicio({
        'error': {
          'message': 'Quota exceeded',
          'details': 'la petición contenía: mi repositorio privado',
        },
      });

      expect(linea, contains('Quota exceeded'));
      expect(linea, isNot(contains('repositorio privado')));
    });
  });
}

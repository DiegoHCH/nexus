import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';
import 'package:nexus/features/assistant/domain/usecases/quien_es_nexus.dart';
import 'package:nexus/features/assistant/domain/usecases/voice_routing.dart';

/// **Quién dice que es.**
///
/// 🔴 Reportado usando la app: «si le preguntas quién eres responde que es
/// Claude, o que es Gemini hablando». Y tenía que pasar, por dos motivos
/// distintos según por dónde entres:
///
/// - **hablando**, «¿quién eres?» son dos palabras que no son cortesía, así que
///   [VoiceRouting] las mandaba a Claude — el único sitio que **no** puede
///   responderlas, porque Claude contesta con verdad quién es él;
/// - **escribiendo**, al encargo viajaban los nombres —«en esta app te llamas
///   X»— y nada de qué es. Un nombre sin identidad detrás se lee como un apodo.
void main() {
  group('cómo se presenta', () {
    test('con el nombre que se le configuró, y la casa aparte', () {
      final dicho = QuienEsNexus.comoSePresenta('Hal');

      expect(dicho, contains('Te llamas Hal'));
      expect(
        dicho,
        contains('vives en Nexus'),
        reason: 'el nombre es de quien atiende; Nexus es la casa',
      );
      // Lo que pidió quien lo reportó, con sus palabras: «si le preguntan si es
      // Nexus, responda algo como en parte sí, mi nombre es tal».
      expect(dicho, contains('en parte'));
    });

    test('sin nombre elegido es el de la app, y no se dice dos veces', () {
      for (final nada in [null, '', '   ']) {
        final dicho = QuienEsNexus.comoSePresenta(nada);
        expect(dicho, contains('Te llamas Nexus'), reason: '$nada');
        expect(
          dicho,
          isNot(contains('vives en Nexus')),
          reason: '«te llamas Nexus y vives en Nexus» es un trabalenguas',
        );
      }
    });

    test('el nombre se limpia, que se escribe a mano en Ajustes', () {
      expect(QuienEsNexus.elNombreDe('  Hal  '), 'Hal');
      expect(QuienEsNexus.elNombreDe(null), 'Nexus');
    });

    // 🔴 **No es un disfraz, y esto lo fija.** Pedirle que niegue el modelo que
    // lo mueve sería enseñarle a mentir sobre sí mismo por un adorno. Dice su
    // nombre primero y el motor cuando se lo preguntan.
    test('y lo que hay debajo no se esconde si lo preguntan', () {
      final dicho = QuienEsNexus.comoSePresenta('Hal');

      expect(dicho, contains('Claude Code'));
      expect(dicho, contains('Google'));
      expect(
        dicho,
        contains('no es lo que te preguntaron'),
        reason: 'no se esconde, pero tampoco se saca de primeras',
      );
    });

    test('dice para qué sirve, que es la mitad de la respuesta', () {
      final dicho = QuienEsNexus.comoSePresenta(null);

      for (final loQueHace in ['encargos', 'permiso', 'registro', 'agenda']) {
        expect(dicho, contains(loQueHace), reason: loQueHace);
      }
    });
  });

  // Los dos caminos tienen que contestar lo mismo, y por eso sale de un solo
  // sitio: preguntárselo hablando y escribiendo no puede dar dos respuestas.
  test('la voz lleva la misma identidad que el encargo escrito', () {
    final instruccion = GeminiVoiceGateway.instruccionDelSistema(
      agente: 'Hal',
      idioma: 'español',
      nombres: '',
    );

    expect(instruccion, contains(QuienEsNexus.comoSePresenta('Hal')));
    // Y la pregunta sobre sí misma entra en lo que contesta sola: si no, el
    // propio modelo la mandaría a Claude aunque la app se lo permita.
    expect(instruccion, contains('sobre ti mismo'));
  });

  // La otra mitad del mismo reporte: escribiendo también contestaba «soy
  // Claude», y por otro motivo — al encargo viajaban los nombres y nada de qué
  // es.
  test('y el encargo escrito la lleva también, junto a los nombres', () {
    final texto = ProjectContextPrompt.compose(
      rules: const [],
      nombres: 'En esta app te llamas Hal.',
      identidad: QuienEsNexus.comoSePresenta('Hal'),
    )!;

    expect(texto, contains('En esta app te llamas Hal.'));
    expect(texto, contains('Te llamas Hal'));
    expect(
      texto.indexOf('te llamas Hal.'),
      lessThan(texto.indexOf('QUIÉN ERES')),
      reason: 'las dos frases se leen juntas: cómo lo llamas y qué es',
    );
  });

  test('sin identidad, el prompt del encargo no cambia', () {
    final texto = ProjectContextPrompt.compose(rules: const [], language: 'es');

    expect(texto, isNot(contains('QUIÉN ERES')));
  });

  group('lo que se pregunta sobre ella lo contesta ella', () {
    test('las preguntas de identidad no van a Claude', () {
      for (final dicho in [
        '¿Quién eres?',
        'quien eres',
        '¿Cómo te llamas?',
        '¿Tú eres Nexus o eres Claude?',
        '¿eres una IA?',
        'preséntate',
        '¿qué modelo eres?',
        'who are you',
        "what's your name",
        'are you nexus',
        'tell me about yourself',
      ]) {
        expect(VoiceRouting.needsClaude(dicho), isFalse, reason: dicho);
      }
    });

    test('y lo que sabe hacer, dicho a secas, tampoco', () {
      for (final dicho in [
        '¿para qué sirves?',
        '¿qué puedes hacer?',
        '¿qué sabes hacer?',
        'what can you do',
      ]) {
        expect(VoiceRouting.needsClaude(dicho), isFalse, reason: dicho);
      }
    });

    // ⚠️ **La mitad delicada.** «¿Qué puedes hacer?» habla de ella; «¿qué
    // puedes hacer con este repositorio?» es un encargo de los buenos, y
    // contestarlo de memoria cuesta un dato falso dicho con seguridad.
    test('pero con algo de esta máquina delante, va a Claude', () {
      for (final dicho in [
        '¿qué puedes hacer con este repositorio?',
        '¿qué puedes hacer en mi carpeta?',
        'what can you do with this project',
        '¿qué sabes hacer con las pruebas de aquí?',
      ]) {
        expect(VoiceRouting.needsClaude(dicho), isTrue, reason: dicho);
      }
    });

    test('y los encargos de siempre siguen yendo', () {
      for (final dicho in [
        'mira el historial de git',
        '¿qué reuniones tengo hoy?',
        'dame el parte',
        'quién escribió esta línea',
      ]) {
        expect(VoiceRouting.needsClaude(dicho), isTrue, reason: dicho);
      }
    });

    test('la cortesía sigue siendo cortesía', () {
      for (final dicho in ['hola', 'gracias', 'para', 'repite']) {
        expect(VoiceRouting.needsClaude(dicho), isFalse, reason: dicho);
      }
    });
  });
}

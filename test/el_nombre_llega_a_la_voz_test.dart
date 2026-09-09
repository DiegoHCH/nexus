import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';
import 'package:nexus/features/workspace/domain/entities/los_nombres.dart';

/// El nombre elegido en Ajustes **llega a la voz**.
///
/// No llegaba. Los nombres viajaban al prompt de Claude y a la etiqueta del
/// chat, pero la instrucción de sistema de la voz decía «Eres Nexus» cableado:
/// le ponías nombre a quien contesta y ella no lo sabía, ni sabía cómo
/// llamarte. Se reportó hablándole por su nombre —contestó bien— y viendo que
/// no usaba el de quien preguntaba.
void main() {
  String instruccion(LosNombres nombres) =>
      GeminiVoiceGateway.instruccionDelSistema(
        agente: nombres.agente,
        idioma: 'español',
        nombres: switch (nombres.paraElPrompt()) {
          final linea? => '$linea\n',
          null => '',
        },
      );

  // La frase la escribe ahora [QuienEsNexus], que es de donde salen también
  // los encargos escritos: preguntarle quién es hablando y escribiendo no puede
  // dar dos respuestas. Antes esto era «Eres <nombre>, un asistente de voz» y
  // nada más — y con eso, al preguntarle quién era contestaba lo que sí sabía
  // de sí mismo: el modelo que lo mueve.
  test('sin nombres elegidos, sigue siendo Nexus', () {
    final texto = instruccion(const LosNombres());

    expect(texto, contains('Te llamas Nexus'));
    // Y sin una línea de nombres colgando en medio de la instrucción.
    expect(texto, isNot(contains('La persona con la que hablas')));
  });

  test('con nombre de agente, se presenta con él', () {
    final texto = instruccion(const LosNombres(agente: 'Hestia'));

    expect(texto, contains('Te llamas Hestia'));
    expect(texto, isNot(contains('Te llamas Nexus')));
    expect(
      texto,
      contains('vives en Nexus'),
      reason: 'el nombre es de quien atiende; Nexus es la casa',
    );
  });

  test('con tu nombre, sabe cómo llamarte', () {
    final texto = instruccion(const LosNombres(tuyo: 'Argonauta'));

    expect(texto, contains('Argonauta'));
  });

  test('los dos a la vez, que es como se configuró al reportarlo', () {
    final texto = instruccion(
      const LosNombres(agente: 'Hestia', tuyo: 'Argonauta'),
    );

    expect(texto, contains('Te llamas Hestia'));
    expect(texto, contains('Argonauta'));
  });

  /// Lo que no cambia al meter los nombres: la instrucción es larga y lleva
  /// dentro las reglas que hacen que la voz no conteste de memoria. Un nombre
  /// no puede colarse en medio y partirlas.
  test('las reglas siguen enteras', () {
    final texto = instruccion(
      const LosNombres(agente: 'Hestia', tuyo: 'Argonauta'),
    );

    expect(texto, contains('REGLA PRINCIPAL'));
    expect(texto, contains('pedir_a_claude'));
    expect(texto, contains('ZONA GRIS'));
    expect(texto, contains('EL PARTE'));
    expect(texto, contains('SKILLS'));
    expect(texto, contains('Respondes en español'));
  });

  /// 🔴 **Es información, no disfraz.** [LosNombres.paraElPrompt] lo dice y la
  /// voz tiene que respetarlo igual que Claude: se le dice cómo se llama y cómo
  /// llamar a quien pregunta, no que actúe como otra persona.
  test('no se le pide un personaje', () {
    final texto = instruccion(const LosNombres(agente: 'Hestia'));

    expect(texto, isNot(contains('actúa como')));
    expect(texto, isNot(contains('interpreta')));
    expect(texto, isNot(contains('personalidad')));
  });
}

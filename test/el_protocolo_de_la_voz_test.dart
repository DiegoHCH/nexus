import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';

/// Lo que se lee de vuelta del servicio de voz.
///
/// 🔴 **Era la mitad sin red.** Lo que se le *manda* al modelo tiene prueba
/// desde esta mañana; lo que se *lee* no la tenía — y es justo la mitad que no
/// controlamos: **el formato lo decide Google**. Si cambia la forma de un marco
/// esto no da error, simplemente deja de emitir ese evento, y la conversación
/// se queda esperando algo que ya pasó. Sin excepción, sin log, sin nada que
/// mirar.
///
/// **De dónde salen estos marcos, dicho:** están escritos a partir de las formas
/// que el adaptador declara manejar, no grabados de una sesión real — grabar una
/// pide la llave y una llamada de verdad. Aun así fijan el contrato contra el
/// cambio accidental, que es de lo que iba esto. Cambiarlos por una grabación,
/// como `delegacion_real.jsonl` hizo con el flujo de Claude, es lo que queda.
void main() {
  LoQueDiceElMarco leer(Map<String, dynamic> marco) =>
      GeminiVoiceGateway.leerElMarco(marco);

  test('el saludo del servicio abre la sesión', () {
    expect(leer({'setupComplete': <String, dynamic>{}}).eventos, [
      isA<VoiceSessionReady>(),
    ]);
  });

  group('el asa para reenganchar', () {
    // Se renueva sola durante la conversación: hay que quedarse con la última.
    test('una asa nueva se recoge', () {
      final dice = leer({
        'sessionResumptionUpdate': {'newHandle': 'asa-2', 'resumable': true},
      });

      expect(dice.asaNueva, 'asa-2');
      expect(dice.eventos, isEmpty);
    });

    // 🔴 Guardar un asa que el servicio marcó como no reanudable es prometer un
    // reenganche que va a fallar cuando más falta hace: al volver de un corte.
    test('una que no es reanudable no se guarda', () {
      expect(
        leer({
          'sessionResumptionUpdate': {'newHandle': 'asa', 'resumable': false},
        }).asaNueva,
        isNull,
      );
      expect(
        leer({
          'sessionResumptionUpdate': <String, dynamic>{'resumable': true},
        }).asaNueva,
        isNull,
      );
    });
  });

  // El corte se atiende igual cuando llega, con aviso o sin él.
  test('el aviso de cierre no produce nada', () {
    final dice = leer({'goAway': <String, dynamic>{}});

    expect(dice.eventos, isEmpty);
    expect(dice.sinReconocer, isFalse);
  });

  group('lo que dice y lo que contesta', () {
    test('la transcripción de quien habla', () {
      final dice = leer({
        'serverContent': {
          'inputTranscription': {'text': 'arregla el login'},
        },
      });

      expect(
        (dice.eventos.single as VoiceUserTranscript).text,
        'arregla el login',
      );
    });

    test('y la de lo que contesta', () {
      final dice = leer({
        'serverContent': {
          'outputTranscription': {'text': 'voy a mirarlo'},
        },
      });

      expect(
        (dice.eventos.single as VoiceReplyTranscript).text,
        'voy a mirarlo',
      );
    });

    // Un texto vacío no es un turno: emitirlo pinta una línea en blanco en la
    // franja de subtítulos.
    test('un texto vacío no produce evento', () {
      expect(
        leer({
          'serverContent': {
            'inputTranscription': {'text': ''},
            'outputTranscription': {'text': ''},
          },
        }).eventos,
        isEmpty,
      );
    });

    test('el audio llega decodificado', () {
      final dice = leer({
        'serverContent': {
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/pcm',
                  'data': base64Encode([1, 2, 3]),
                },
              },
            ],
          },
        },
      });

      expect((dice.eventos.single as VoiceReplyAudio).pcm, [1, 2, 3]);
    });

    // Una parte de texto sin `inlineData` es lo normal cuando el modelo escribe
    // además de hablar: no puede tumbar el audio que venga detrás.
    test('una parte que no es audio se salta sin llevarse las demás', () {
      final dice = leer({
        'serverContent': {
          'modelTurn': {
            'parts': [
              {'text': 'algo'},
              {
                'inlineData': {
                  'data': base64Encode([9]),
                },
              },
            ],
          },
        },
      });

      expect((dice.eventos.single as VoiceReplyAudio).pcm, [9]);
    });
  });

  // 🔴 El orden importa: quien escuche tiene que tirar la cola del altavoz
  // **antes** de dar el turno por cerrado. Al revés se oye la coleta de lo que
  // se acaba de interrumpir.
  test('interrumpir va antes que cerrar el turno', () {
    final dice = leer({
      'serverContent': {'interrupted': true, 'turnComplete': true},
    });

    expect(dice.eventos.map((e) => e.runtimeType), [
      VoiceInterrupted,
      VoiceTurnCompleted,
    ]);
  });

  test(
    'un turno entero sale en orden: lo dicho, lo contestado, el audio y el fin',
    () {
      final dice = leer({
        'serverContent': {
          'inputTranscription': {'text': 'hola'},
          'outputTranscription': {'text': 'dime'},
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'data': base64Encode([7]),
                },
              },
            ],
          },
          'turnComplete': true,
        },
      });

      expect(dice.eventos.map((e) => e.runtimeType), [
        VoiceUserTranscript,
        VoiceReplyTranscript,
        VoiceReplyAudio,
        VoiceTurnCompleted,
      ]);
    },
  );

  group('cuando el modelo llama a una herramienta', () {
    test('llega con su identificador, su nombre y sus argumentos', () {
      final dice = leer({
        'toolCall': {
          'functionCalls': [
            {
              'id': 'fc-1',
              'name': 'pedir_a_claude',
              'args': {'instruccion': 'arregla el login'},
            },
          ],
        },
      });

      final pedida = dice.eventos.single as VoiceToolRequested;
      expect(pedida.callId, 'fc-1');
      expect(pedida.name, 'pedir_a_claude');
      expect(pedida.arguments['instruccion'], 'arregla el login');
    });

    // 🔴 Sin `id` no se puede contestar —la respuesta no se empareja con la
    // pregunta y el modelo espera para siempre—, así que se salta esa y no se
    // pierden las demás.
    test('una llamada sin id o sin nombre se salta, y las otras siguen', () {
      final dice = leer({
        'toolCall': {
          'functionCalls': [
            {'name': 'pedir_a_claude'},
            {'id': 'fc-2'},
            {'id': 'fc-3', 'name': 'consultar_agenda'},
          ],
        },
      });

      expect(dice.eventos.map((e) => (e as VoiceToolRequested).callId), [
        'fc-3',
      ]);
    });

    test('sin argumentos no revienta: llegan vacíos', () {
      final dice = leer({
        'toolCall': {
          'functionCalls': [
            {'id': 'fc-1', 'name': 'pedir_el_parte'},
          ],
        },
      });

      expect((dice.eventos.single as VoiceToolRequested).arguments, isEmpty);
    });
  });

  // 🔴 El caso que motivó todo esto. Cinco sesiones seguidas con «203 trozos
  // del micro, 203 enviados, 1 eventos recibidos»: ese 1 era el `setupComplete`,
  // y un marco de error —cuota, modelo retirado— habría desaparecido igual.
  group('lo que no se reconoce', () {
    test('se marca para anotarlo, no se tira', () {
      final dice = leer({
        'error': {'code': 429, 'message': 'quota exceeded'},
      });

      expect(dice.sinReconocer, isTrue);
      expect(dice.eventos, isEmpty);
    });

    test('un marco vacío también', () {
      expect(leer(<String, dynamic>{}).sinReconocer, isTrue);
    });

    // Y lo que sí se entiende no se anota: si todo se anotara, el registro
    // dejaría de señalar nada.
    test('lo que sí se entiende no se marca', () {
      for (final marco in <Map<String, dynamic>>[
        {'setupComplete': <String, dynamic>{}},
        {'goAway': <String, dynamic>{}},
        {
          'serverContent': {'turnComplete': true},
        },
      ]) {
        expect(leer(marco).sinReconocer, isFalse, reason: '$marco');
      }
    });
  });
}

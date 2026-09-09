import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/state/lo_que_hace_un_evento.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';

/// **Lo que un evento de Claude le hace a la conversación**, ahora que se puede
/// mirar de una en una.
///
/// 🔴 Es el paso siguiente que el PR #306 dejó anotado al partir el controlador,
/// y el mismo patrón que ya usa la feature de correr —«puro y aparte del
/// controlador para poder probar la traducción sin lanzar un `flutter run`»—.
/// Aquí el equivalente es **sin lanzar un Claude**: hasta ahora, comprobar que
/// el orbe se duerme al terminar el turno pedía montar la conversación entera
/// con su Claude de mentira, y por eso no se comprobaba.
///
/// Y lo que se rompe aquí **no falla**: hace otra cosa. El orbe se queda
/// pensando cuando ya contestó, la espera no se cierra al llegar el turno, el
/// medidor cuenta los tokens del turno anterior. Nada de eso lanza.
void main() {
  const espera = (laPropia: 'Comprimiendo esta', deOtra: 'Trabajando en otra');
  TextosDeLaEspera losTextos() => espera;

  AssistantHudState conElEventoDe(
    AssistantHudState actual,
    ClaudeEvent evento, {
    bool comprimiendose = false,
    String? respondeA,
    bool esElParte = false,
  }) => conElEvento(
    actual,
    evento,
    espera: losTextos,
    comprimiendose: comprimiendose,
    respondeA: respondeA,
    esElParte: esElParte,
  );

  ChatMessage mensaje(
    ChatAuthor autor,
    String texto, {
    bool streaming = false,
  }) => ChatMessage(author: autor, text: texto, streaming: streaming);

  group('esperar turno', () {
    test('se dice de quién es la espera', () {
      final esperando = conElEventoDe(
        const AssistantHudState(),
        const ClaudeQueued(),
      );

      expect(esperando.orbState, NexusOrbState.think);
      expect(esperando.activity.single.description, 'Trabajando en otra');
      expect(esperando.activity.single.writes, isFalse);
    });

    // 🔴 **Decirlo mal es decirle a alguien que espera por su propio trabajo
    // cuando espera por el de otro** — o al revés, que es peor: parece que la
    // app se colgó por su cuenta.
    test('y si es la propia compresión, se dice eso', () {
      final esperando = conElEventoDe(
        const AssistantHudState(),
        const ClaudeQueued(),
        comprimiendose: true,
      );

      expect(esperando.activity.single.description, 'Comprimiendo esta');
    });

    test('al arrancar la sesión se cierra, y se apunta el modelo', () {
      final esperando = conElEventoDe(
        const AssistantHudState(),
        const ClaudeQueued(),
      );

      final arrancada = conElEventoDe(
        esperando,
        const ClaudeSessionStarted(sessionId: 's1', model: 'claude-opus-5[1m]'),
      );

      expect(arrancada.activity.single.done, isTrue);
      expect(arrancada.meter.model, 'claude-opus-5[1m]');
    });

    // Un modelo vacío no pisa el que ya había: el medidor enseñaría un hueco
    // donde antes decía algo.
    test('y un modelo vacío no borra el que ya estaba', () {
      const antes = AssistantHudState(
        meter: SessionMeter(model: 'claude-opus-5'),
      );

      final despues = conElEventoDe(
        antes,
        const ClaudeSessionStarted(sessionId: 's1', model: ''),
      );

      expect(despues.meter.model, 'claude-opus-5');
    });
  });

  group('los pasos del turno', () {
    const leyendo = ClaudeToolUsed(
      id: 't1',
      description: 'Leyendo lib/main.dart',
      writes: false,
      detail: 'Read(lib/main.dart)',
      parentId: 'sub-1',
    );

    // 🔴 **El detalle se estaba tirando**: el lector lo traía y la fila no lo
    // recibía, así que un paso no se podía abrir hasta que terminara — y
    // entonces solo enseñaba lo que devolvió, nunca lo que se ejecutó.
    test('un paso llega con su detalle y con de quién cuelga', () {
      final conPaso = conElEventoDe(const AssistantHudState(), leyendo);

      expect(conPaso.orbState, NexusOrbState.think);
      expect(conPaso.activity.single.detail, 'Read(lib/main.dart)');
      expect(conPaso.activity.single.parentId, 'sub-1');
      expect(conPaso.activity.single.hasDetail, isTrue);
    });

    test('y al terminar se marca solo ese, con lo que devolvió', () {
      final dos = conElEventoDe(
        conElEventoDe(const AssistantHudState(), leyendo),
        const ClaudeToolUsed(id: 't2', description: 'Corriendo', writes: true),
      );

      final unoHecho = conElEventoDe(
        dos,
        const ClaudeToolFinished('t1', output: '42 líneas'),
      );

      expect(unoHecho.activity.first.done, isTrue);
      expect(unoHecho.activity.first.output, '42 líneas');
      expect(unoHecho.activity.last.done, isFalse, reason: 'el otro sigue');
    });

    test('cerrar un paso que no existe no inventa ninguno', () {
      final igual = conElEventoDe(
        const AssistantHudState(),
        const ClaudeToolFinished('no-existe'),
      );

      expect(igual.activity, isEmpty);
    });
  });

  group('el texto que llega a trozos', () {
    test('el primer trozo crea el turno, con su cita', () {
      final conTexto = conElEventoDe(
        const AssistantHudState(),
        const ClaudeTextDelta('Voy a '),
        respondeA: '¿qué falta?',
      );

      expect(conTexto.orbState, NexusOrbState.speak);
      expect(conTexto.isStreaming, isTrue);
      expect(conTexto.messages.single.text, 'Voy a ');
      expect(conTexto.messages.single.streaming, isTrue);
      expect(conTexto.messages.single.respondeA, '¿qué falta?');
    });

    // 🔴 **La cita solo cuaja al crear.** Alargando no se toca: si cada trozo la
    // volviera a poner, la respuesta citaría la pregunta en cada porción; y si
    // la pusiera a `null`, el segundo trozo la borraría.
    test('los siguientes alargan el mismo, sin repetir la cita', () {
      final unTrozo = conElEventoDe(
        const AssistantHudState(),
        const ClaudeTextDelta('Voy a '),
        respondeA: '¿qué falta?',
      );

      final dosTrozos = conElEventoDe(
        unTrozo,
        const ClaudeTextDelta('mirarlo.'),
      );

      expect(dosTrozos.messages, hasLength(1));
      expect(dosTrozos.messages.single.text, 'Voy a mirarlo.');
      expect(dosTrozos.messages.single.respondeA, '¿qué falta?');
    });

    test('y no se pega a un turno que ya se cerró', () {
      final antes = AssistantHudState(
        messages: [mensaje(ChatAuthor.nexus, 'lo de antes')],
      );

      final despues = conElEventoDe(antes, const ClaudeTextDelta('lo nuevo'));

      expect(despues.messages.map((m) => m.text), ['lo de antes', 'lo nuevo']);
    });

    test('ni al turno de quien preguntó', () {
      final antes = AssistantHudState(
        messages: [mensaje(ChatAuthor.user, 'arréglalo', streaming: true)],
      );

      final despues = conElEventoDe(antes, const ClaudeTextDelta('vale'));

      expect(despues.messages, hasLength(2));
      expect(despues.messages.last.author, ChatAuthor.nexus);
    });

    // El botón de mandar a Slack va bajo el parte, y solo bajo la respuesta:
    // lo que se pidió es la instrucción que lo generó.
    test('el parte se marca al crear la respuesta, no lo que se pidió', () {
      final conParte = conElEventoDe(
        const AssistantHudState(),
        const ClaudeTextDelta('Ayer se hizo…'),
        esElParte: true,
      );

      expect(conParte.messages.single.esElParte, isTrue);
    });
  });

  group('el turno que termina', () {
    test('se sella el mensaje, se duerme el orbe y se cuenta el gasto', () {
      final hablando = conElEventoDe(
        const AssistantHudState(),
        const ClaudeTextDelta('ya está'),
      );

      final terminado = conElEventoDe(
        hablando,
        const ClaudeTurnCompleted(
          result: '',
          turnTokens: 1200,
          contextTokens: 63300,
        ),
      );

      expect(terminado.messages.single.streaming, isFalse);
      expect(terminado.orbState, NexusOrbState.sleep);
      expect(terminado.isStreaming, isFalse);
      expect(terminado.meter.turnTokens, 1200);
      expect(terminado.meter.contextTokens, 63300);
    });

    // 🔴 **Un turno que no llegó a decir nada no se deja en la ventana**: sería
    // una burbuja vacía con su cursor puesto para siempre.
    test('y un turno que no dijo nada no se queda', () {
      final antes = AssistantHudState(
        messages: [
          mensaje(ChatAuthor.user, 'arréglalo'),
          mensaje(ChatAuthor.nexus, '', streaming: true),
        ],
      );

      final terminado = conElEventoDe(
        antes,
        const ClaudeTurnCompleted(result: '', turnTokens: 0, contextTokens: 0),
      );

      expect(terminado.messages, hasLength(1));
      expect(terminado.messages.single.author, ChatAuthor.user);
    });

    test('sellar dos veces no borra lo que ya está sellado', () {
      final antes = AssistantHudState(
        messages: [mensaje(ChatAuthor.nexus, 'dicho')],
      );

      final terminado = conElEventoDe(
        antes,
        const ClaudeTurnCompleted(result: '', turnTokens: 1, contextTokens: 1),
      );

      expect(terminado.messages.single.text, 'dicho');
    });
  });

  // 🔴 Los tres que **no** son mapeo: el fallo hay que traducirlo y
  // clasificarlo, y los dos avisos se dicen una vez, lo que pide recordar qué
  // se dijo antes. Eso es coreografía y se queda en el controlador — pero tiene
  // que quedar claro que aquí no tocan nada, o se harían dos veces.
  group('los que lleva el controlador', () {
    test('no tocan el estado', () {
      final antes = AssistantHudState(
        messages: [mensaje(ChatAuthor.nexus, 'algo', streaming: true)],
        orbState: NexusOrbState.speak,
      );

      for (final evento in const [
        ClaudeFailed('se cayó'),
        ClaudeMcpCaido(['g66']),
        ClaudeRulesChanged(['CLAUDE.md']),
      ]) {
        final despues = conElEventoDe(antes, evento);

        expect(despues, same(antes), reason: '$evento');
      }
    });
  });

  // Por aquí pasan los deltas —cientos por respuesta— y solo un evento necesita
  // traducir algo. Leer los textos en cada uno sería un `ref.read` por letra.
  test('los textos solo se piden cuando hacen falta', () {
    var veces = 0;

    conElEvento(
      const AssistantHudState(),
      const ClaudeTextDelta('hola'),
      espera: () {
        veces++;
        return espera;
      },
      comprimiendose: false,
    );
    expect(veces, 0);

    conElEvento(
      const AssistantHudState(),
      const ClaudeQueued(),
      espera: () {
        veces++;
        return espera;
      },
      comprimiendose: false,
    );
    expect(veces, 1);
  });

  group('lo que dejó el encargo, colgado del mensaje', () {
    test('va en el último de Nexus y no en el de quien preguntó', () {
      final mensajes = [
        mensaje(ChatAuthor.nexus, 'lo de antes'),
        mensaje(ChatAuthor.user, 'y ahora esto'),
        mensaje(ChatAuthor.nexus, 'hecho'),
      ];

      final conDocumento = LosMensajes.conLoQueDejo(
        mensajes,
        documento: '/cajon/nuevo.html',
      );

      expect(conDocumento[2].documento, '/cajon/nuevo.html');
      expect(conDocumento[0].documento, isNull, reason: 'el turno anterior');
      expect(conDocumento[1].author, ChatAuthor.user);
    });

    test('y si Nexus no ha dicho nada, no se cuelga de nadie', () {
      final mensajes = [mensaje(ChatAuthor.user, 'arréglalo')];

      expect(
        LosMensajes.conLoQueDejo(mensajes, documento: '/x.html'),
        same(mensajes),
      );
    });
  });
}

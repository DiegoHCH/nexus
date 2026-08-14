import 'dart:async';

import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/claude_errand.dart';
import 'package:nexus/features/assistant/domain/usecases/voice_routing.dart';

/// La conversación completa: micrófono → socket → altavoz, y Claude en medio
/// cuando hay trabajo de verdad que hacer.
///
/// No extiende `UseCase<ReturnType, Params>` por lo mismo que [AskClaude]: ese
/// contrato es para trabajo de una sola respuesta, y esto es una sesión viva.
///
/// Aquí se junta lo que las piezas no saben la una de la otra: el micrófono no
/// sabe que su PCM va a un socket, el socket no sabe que su audio se reproduce,
/// el altavoz no sabe que puede ser interrumpido, y Claude no sabe que quien le
/// encarga el trabajo es otro modelo. Cada una sigue probándose por separado;
/// el pegamento es esto.
class HoldVoiceConversation {
  const HoldVoiceConversation(
    this._voiceInput,
    this._gateway,
    this._output,
    this._askClaude,
    this._log,
  );

  /// A dónde van los diagnósticos de la sesión. **Se inyecta y no se elige
  /// aquí** por una razón medida: los de b11 se escribieron con
  /// `dart:developer`, que era lo único que el dominio podía usar sin depender
  /// de Flutter — y `developer.log` no sale ni en el registro del sistema ni en
  /// la consola de `flutter run`. La sesión falló otra vez y no dejó rastro:
  /// ese silencio es la razón de que b11 siga sin diagnóstico. Recibiendo la
  /// función, el dominio sigue sin conocer Flutter y quien cablea la app le
  /// pasa `debugPrint`, que sí se lee.
  final void Function(String message) _log;

  /// Cuánto se espera sin actividad antes de cerrar sola la sesión.
  ///
  /// Corto a propósito: mientras está abierta, tu micrófono sale hacia Google.
  /// Pero no tan corto como para matar la conversación entre una respuesta y
  /// la repregunta, que es lo que pasaría cerrando al terminar cada frase.
  static const _idleTimeout = Duration(seconds: 6);

  /// Reenganches seguidos sin que llegue nada en medio antes de rendirse.
  /// Reintentar en bucle contra un servicio caído solo esconde el problema.
  static const _maxReconnects = 3;

  final VoiceInput _voiceInput;
  final VoiceGateway _gateway;
  final AudioOutput _output;
  final AskClaude _askClaude;

  /// Lo que la pantalla enseña como titular del trabajo.
  ///
  /// Para un encargo normal es la instrucción que redactó el modelo, que es lo
  /// que se va a ejecutar y la única parte revisable. Para crear una skill,
  /// el encargo es una plantilla de veinte líneas que no dice nada al leerla:
  /// ahí el titular útil es el nombre.
  static String _headline(VoiceToolRequested request) {
    if (request.name == ClaudeErrand.skillTool) {
      return 'Creando la skill ${ClaudeErrand.skillName(request.arguments['nombre'] as String?) ?? ''}'
          .trim();
    }
    return (request.arguments['instruccion'] as String?)?.trim() ??
        request.name;
  }

  /// Abre la conversación y emite lo que ocurre dentro. **Cancelar la
  /// suscripción la cierra entera**: micrófono, socket y altavoz. Ese es el
  /// único mando de apagado, para que no exista un estado donde el micro
  /// quede abierto hacia Google sin que nadie escuche los eventos.
  Stream<VoiceEvent> call() {
    late StreamController<VoiceEvent> controller;
    VoiceSession? session;
    StreamSubscription<AudioFrame>? micSubscription;
    StreamSubscription<VoiceEvent>? sessionSubscription;
    Timer? idleTimer;
    late void Function(VoiceSession) attach;
    void Function()? abortErrand;
    var reconnects = 0;
    var closing = false;

    // Que todo pase por Claude es una instrucción al modelo, no un candado
    // (b6): nada en el código lo obliga, y en la zona gris puede contestar de
    // memoria sin avisar. No se puede impedir —la respuesta ya va en audio
    // cuando nos enteramos— pero sí contar cuántas veces pasa, que es lo que
    // faltaba para decidir si hace falta la salida cara.
    // **Se acumula, no se sobrescribe.** La transcripción de lo que dices llega
    // en pedazos —lo dice el propio evento—, así que quedarse con el último
    // dejaba una frase larga reducida a su cola: dos o tres palabras. Y eso
    // rompía las dos cosas que dependen de aquí. `needsClaude` juzga con un
    // tope de cuatro palabras, pensado para separar «hola» de «hola, mira el
    // historial de git»; con un trozo suelto ese tope no distingue nada. Y la
    // corrección le mandaba a Claude ese mismo trozo como encargo, que es la
    // frase cortada a mitad que se veía (b11). Con las cortas no se notaba
    // porque caben en un pedazo.
    final asked = StringBuffer();
    var answeredAlone = 0;

    /// Sube con **cada frase nueva** del usuario. Existe para saber si una
    /// corrección que tardó sigue siendo de lo que se está hablando.
    ///
    /// Un encargo a Claude tarda segundos y la conversación no espera: para
    /// cuando vuelve la respuesta buena, puedes haber preguntado otra cosa. Sin
    /// esto, la corrección entraba igual y el modelo abandonaba lo que estaba
    /// diciendo para narrar la respuesta de dos turnos atrás — medido en una
    /// sesión real: dos correcciones seguidas se pisaron entre ellas y la
    /// segunda dejó a la primera a medias.
    var turn = 0;
    var stale = 0;

    var micFrames = 0;
    var sentFrames = 0;
    var eventsSeen = 0;

    Future<void> shutdown() async {
      closing = true;
      // Primero el encargo: si hay un `claude -p` en marcha, cerrar la
      // conversación sin matarlo lo deja trabajando de fondo para nadie.
      abortErrand?.call();
      abortErrand = null;
      idleTimer?.cancel();
      idleTimer = null;
      await micSubscription?.cancel();
      await sessionSubscription?.cancel();
      await _output.stop();
      await session?.close();
      micSubscription = null;
      sessionSubscription = null;
      session = null;
    }

    /// Reinicia la cuenta atrás de inactividad.
    ///
    /// La marca de "aquí sigue pasando algo" son los eventos del servicio, no
    /// el volumen del micrófono: un umbral de RMS depende de la sala, del
    /// micro y de si hay un ventilador cerca, y se equivoca justo cuando peor
    /// viene. Los trozos de micrófono no cuentan —llegan aunque no hables—,
    /// pero una transcripción de lo que dijiste sí: eso ya es el servicio
    /// diciendo que te oyó. Mientras el modelo responde también llegan
    /// eventos, así que nunca se corta a media frase.
    void keepAlive() {
      idleTimer?.cancel();
      idleTimer = Timer(_idleTimeout, () async {
        // Con un encargo en marcha no se cierra, y punto. Reiniciar la cuenta
        // con cada evento de Claude no bastaba: **el primero tarda más que el
        // propio plazo** —arrancar el CLI, cargar los CLAUDE.md del árbol— así
        // que la sesión se cerraba antes de recibir nada y `shutdown()` mataba
        // el proceso. Silencio mientras se trabaja no es inactividad.
        if (abortErrand != null) {
          keepAlive();
          return;
        }

        // «Dejaron de llegar eventos» tampoco es «dejó de hablar»: el servicio
        // entrega la respuesta más rápido que en tiempo real, así que el
        // altavoz puede tener frases enteras pendientes cuando el socket ya
        // está callado. Cerrar aquí cortaba la respuesta a media palabra.
        final pending = await _output.pending();
        if (pending > Duration.zero) {
          idleTimer?.cancel();
          idleTimer = Timer(pending + _idleTimeout, () => keepAlive());
          return;
        }
        _log(
          'voz · cierre por inactividad tras ${_idleTimeout.inSeconds} s · '
          '$micFrames trozos del micro, $sentFrames enviados, '
          '$eventsSeen eventos recibidos · $turn turnos, '
          '$answeredAlone corregidos, $stale descartados por viejos',
        );
        await shutdown();
        if (!controller.isClosed) await controller.close();
      });
    }

    /// Atiende un encargo del modelo: se lo pasa a Claude y le devuelve el
    /// resultado para que lo narre.
    ///
    /// Nunca deja de contestar. Si Claude falla, lo que viaja de vuelta es la
    /// explicación del fallo: el modelo está esperando esta respuesta y sin
    /// ella la conversación se queda muda para siempre, que es peor que una
    /// mala noticia bien contada.
    /// Le pasa un encargo a Claude y devuelve lo que respondió, o `null` si se
    /// canceló por el camino.
    ///
    /// Lo usan los dos caminos: cuando el modelo pide la herramienta, y cuando
    /// **no** la pidió debiendo hacerlo y hay que corregirlo.
    Future<String?> runErrand(String instruction, String headline) async {
      controller.add(VoiceToolStarted(headline));
      final answer = StringBuffer();
      var ok = true;
      var aborted = false;
      int? turnTokens;
      int? contextTokens;
      final ended = Completer<void>();
      void finish() {
        if (!ended.isCompleted) ended.complete();
      }

      final errand = _askClaude(instruction).listen(
        (event) {
          // Un encargo puede tardar minutos, y en ese rato no llega nada del
          // servicio de voz: sin esto, la sesión se cerraría sola por
          // inactividad justo mientras se trabaja para ella.
          keepAlive();
          switch (event) {
            // Otra conversación tiene la carpeta ocupada. Hablando esto hay
            // que decirlo en voz alta: la pantalla puede estar detrás y el
            // silencio se interpreta como que no oyó.
            case ClaudeQueued():
              controller.add(
                const VoiceToolProgress(
                  'Espero turno: hay otra conversación trabajando en esa '
                  'carpeta.',
                ),
              );
            case ClaudeTextDelta(:final text):
              answer.write(text);
              controller.add(VoiceToolProgress(text));
            case ClaudeTurnCompleted(:final result):
              if (result.isNotEmpty) {
                answer
                  ..clear()
                  ..write(result);
              }
              // Las cifras del turno se guardan para sacarlas con el final del
              // encargo: son las que mueven el medidor de contexto, y hasta
              // ahora morían aquí dentro.
              turnTokens = event.turnTokens;
              contextTokens = event.contextTokens;
            case ClaudeFailed(:final message):
              ok = false;
              answer
                ..clear()
                ..write('La tarea falló: $message');
            case ClaudeToolUsed():
              controller.add(
                VoiceToolActivity(
                  id: event.id,
                  description: event.description,
                  writes: event.writes,
                  done: false,
                  detail: event.detail,
                ),
              );
            case ClaudeToolFinished():
              controller.add(
                VoiceToolActivity(
                  id: event.id,
                  description: '',
                  writes: false,
                  done: true,
                  output: event.output,
                ),
              );
            case ClaudeSessionStarted():
              break;
          }
        },
        onError: (Object error) {
          ok = false;
          answer
            ..clear()
            ..write('No se pudo ejecutar la tarea: $error');
          finish();
        },
        onDone: finish,
        cancelOnError: true,
      );

      // Se escucha con `listen` y no con `await for` justamente por esto: un
      // `await for` no se puede cortar desde fuera, y cerrar la conversación
      // tiene que matar el encargo — cancelar la suscripción mata el proceso.
      abortErrand = () {
        aborted = true;
        unawaited(errand.cancel());
        finish();
      };

      await ended.future;
      abortErrand = null;
      await errand.cancel();

      // Cancelado: no hay a quién contestar, la sesión se está cerrando.
      if (aborted || closing) return null;

      controller.add(
        VoiceToolFinished(
          ok: ok,
          turnTokens: turnTokens,
          contextTokens: contextTokens,
        ),
      );
      keepAlive();
      return answer.isEmpty
          ? 'La tarea terminó sin devolver nada.'
          : answer.toString();
    }

    /// El modelo contestó por su cuenta algo que tenía que haber ido a Claude.
    ///
    /// Aquí está el candado que b6 pedía: la comprobación no la hace el modelo,
    /// la hace este código con lo que el usuario dijo de verdad. Lo que ya se
    /// esté oyendo se corta —igual que una interrupción— y en su lugar suena la
    /// respuesta buena.
    Future<void> enforceClaude(String utterance, int askedAt) async {
      unawaited(_output.discard());
      final answer = await runErrand(utterance, utterance);
      if (answer == null || closing) return;

      // **Solo si sigue siendo de este turno.** Si mientras Claude trabajaba
      // volviste a hablar, esta respuesta ya no viene a cuento: entregarla
      // interrumpe lo que el modelo esté diciendo para contar lo de antes, que
      // es peor que no corregir. Se descarta y se cuenta, porque cuántas veces
      // pasa es lo que dirá si hace falta algo más fino que esto —encolarla
      // para el final del turno, por ejemplo— o si con no estorbar basta.
      if (turn != askedAt) {
        stale++;
        _log(
          'b6 · corrección descartada por vieja ($stale en esta sesión): se '
          'pidió en el turno $askedAt y vamos por el $turn — «$utterance»',
        );
        return;
      }
      session?.sendSystemNote(VoiceRouting.correction(answer));
    }

    Future<void> runTool(VoiceToolRequested request) async {
      final instruction = ClaudeErrand.forTool(request.name, request.arguments);
      // Herramienta desconocida o argumentos incompletos: se contesta igual.
      // Callarse dejaría al modelo esperando una respuesta que no va a llegar,
      // y la conversación muda para siempre.
      if (instruction == null || instruction.isEmpty) {
        session?.sendToolResult(
          callId: request.callId,
          name: request.name,
          result:
              'No se pudo ejecutar «${request.name}»: faltan datos o esa herramienta no existe.',
        );
        return;
      }

      final answer = await runErrand(instruction, _headline(request));
      if (answer == null) return;
      session?.sendToolResult(
        callId: request.callId,
        name: request.name,
        result: answer,
      );
    }

    /// Reengancha la conversación cuando el servicio corta la conexión.
    ///
    /// El corte llega cada pocos minutos por diseño del servicio, y con los
    /// encargos a Claude sosteniendo la sesión abierta se alcanza de verdad.
    /// Si el reenganche falla se cierra y punto: seguir con la memoria en
    /// blanco, disimulando que es la misma charla, sería peor.
    Future<void> reconnect() async {
      // El motivo del corte se arrastra al mensaje de error: si el reenganche
      // acaba fallando, «no se pudo recuperar la conversación» a secas no dice
      // nada, y la causa real (llave mala, cuota, red) está aquí.
      final because = session?.endReason;

      if (reconnects >= _maxReconnects) {
        controller.add(
          VoiceSessionFailed(
            'La conexión con el servicio de voz no se sostiene: ${because ?? 'se cortó varias veces seguidas'}.',
          ),
        );
        if (!controller.isClosed) await controller.close();
        return;
      }
      reconnects++;

      try {
        await sessionSubscription?.cancel();
        sessionSubscription = null;
        attach(await _gateway.resume());
      } catch (error) {
        controller.add(
          VoiceSessionFailed(because == null ? '$error' : '$error ($because)'),
        );
        if (!controller.isClosed) await controller.close();
      }
    }

    attach = (VoiceSession live) {
      session = live;
      sessionSubscription = live.events.listen(
        (event) {
          // Llegó algo: la conexión va bien, así que la cuenta de reenganches
          // vuelve a cero. Si no, tres cortes en toda una tarde acabarían
          // pareciendo un servicio caído.
          reconnects = 0;
          eventsSeen++;
          keepAlive();
          switch (event) {
            // El audio no sale hacia la interfaz: se reproduce y punto. Lo
            // que la interfaz necesita de la respuesta es el texto, que
            // llega aparte como transcripción.
            case VoiceReplyAudio(:final pcm):
              _output.enqueue(pcm);
            case VoiceInterrupted():
              unawaited(_output.discard());
              controller.add(event);
            // La petición no sale hacia la interfaz: la atiende este caso de
            // uso, que es quien tiene el puente. La pantalla ve el trabajo
            // empezar y avanzar, no la fontanería.
            case VoiceToolRequested():
              // Lo pasó a Claude: este turno cumplió la regla.
              asked.clear();
              unawaited(runTool(event));
            case VoiceUserTranscript(:final text):
              // El primer pedazo de una frase es el que estrena turno: los
              // siguientes son la misma frase llegando a trozos.
              if (asked.isEmpty) turn++;
              asked.write(text);
              controller.add(event);
            case VoiceTurnCompleted():
              // Terminó un turno sin que el modelo llamara a nadie. Si lo que
              // se pidió no era de la lista corta —saludos, «para», «repite»—,
              // aquí se corrige: va a Claude y lo que suena es su respuesta.
              // El turno cierra la frase: lo acumulado hasta aquí es lo que
              // dijo el usuario entero, y a partir del siguiente pedazo empieza
              // otra.
              final utterance = asked.toString().trim();
              asked.clear();
              if (utterance.isNotEmpty) {
                if (VoiceRouting.needsClaude(utterance)) {
                  answeredAlone++;
                  _log(
                    'b6 · contestó sin pasar por Claude ($answeredAlone en esta '
                    'sesión) y se corrige: «$utterance»',
                  );
                  unawaited(enforceClaude(utterance, turn));
                  break;
                }
              }
              controller.add(event);
            default:
              controller.add(event);
          }
        },
        onError: controller.addError,
        // Que se acabe el stream no significa que se acabe la conversación:
        // puede ser el corte de conexión periódico. Solo se cierra de verdad
        // si ya estábamos apagando o si no hay forma de volver.
        onDone: () {
          if (closing || controller.isClosed) return;
          unawaited(reconnect());
        },
      );
    };

    Future<void> boot() async {
      try {
        // En paralelo a propósito: arrancar el motor de audio tarda medio
        // segundo largo —el cancelador de eco construye un dispositivo agregado
        // juntando micro y altavoz— y abrir el socket otros tantos. En serie,
        // ese retardo se nota entre pulsar el atajo y poder hablar; a la vez,
        // se paga una sola vez.
        final booted = await (_output.start(), _gateway.connect()).wait;
        attach(booted.$2);
        keepAlive();

        micSubscription = _voiceInput.listen().listen(
          // Se lee `session` en cada trozo a propósito: tras un reenganche es
          // otra sesión, y capturarla en una variable mandaría el audio a la
          // conexión muerta.
          (frame) {
            // Se cuentan los dos por separado y no uno solo: antes se sumaba
            // siempre, hubiera sesión o no, así que el registro decía «trozos
            // enviados» de audio que no salió de la máquina — que es
            // exactamente la mitad del diagnóstico que este contador existe
            // para dar.
            micFrames++;
            final live = session;
            if (live != null) {
              live.sendAudio(frame.pcm);
              sentFrames++;
            }
            // Un recuento cada dos segundos, no un evento por trozo: es lo que
            // distingue «el micro no llega» de «el servicio no contesta»,
            // que se arreglan en sitios opuestos y desde fuera se ven igual.
            if (micFrames % 25 == 0) {
              _log(
                'voz · $micFrames trozos del micro, $sentFrames enviados · '
                '$eventsSeen eventos recibidos',
              );
            }
          },
          onError: (Object error) =>
              controller.add(VoiceSessionFailed('$error')),
        );
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    }

    controller = StreamController<VoiceEvent>(
      onListen: () => unawaited(boot()),
      onCancel: shutdown,
    );

    return controller.stream;
  }
}

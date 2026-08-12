import 'dart:async';

import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';

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
  const HoldVoiceConversation(this._voiceInput, this._gateway, this._output, this._askClaude);

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
    Future<void> runTool(VoiceToolRequested request) async {
      controller.add(VoiceToolStarted(request.instruction));
      final answer = StringBuffer();
      var ok = true;
      var aborted = false;
      final ended = Completer<void>();
      void finish() {
        if (!ended.isCompleted) ended.complete();
      }

      final errand = _askClaude(request.instruction).listen(
        (event) {
          // Un encargo puede tardar minutos, y en ese rato no llega nada del
          // servicio de voz: sin esto, la sesión se cerraría sola por
          // inactividad justo mientras se trabaja para ella.
          keepAlive();
          switch (event) {
            case ClaudeTextDelta(:final text):
              answer.write(text);
              controller.add(VoiceToolProgress(text));
            case ClaudeTurnCompleted(:final result):
              if (result.isNotEmpty) {
                answer
                  ..clear()
                  ..write(result);
              }
            case ClaudeFailed(:final message):
              ok = false;
              answer
                ..clear()
                ..write('La tarea falló: $message');
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

      // Cancelado: no hay a quién contestar, la sesión se está cerrando. Y sin
      // este corte, el `sendToolResult` iría a una sesión ya muerta.
      if (aborted || closing) return;

      session?.sendToolResult(
        callId: request.callId,
        name: request.name,
        result: answer.isEmpty ? 'La tarea terminó sin devolver nada.' : answer.toString(),
      );
      controller.add(VoiceToolFinished(ok: ok));
      keepAlive();
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
        controller.add(VoiceSessionFailed('La conexión con el servicio de voz no se sostiene: ${because ?? 'se cortó varias veces seguidas'}.'));
        if (!controller.isClosed) await controller.close();
        return;
      }
      reconnects++;

      try {
        await sessionSubscription?.cancel();
        sessionSubscription = null;
        attach(await _gateway.resume());
      } catch (error) {
        controller.add(VoiceSessionFailed(because == null ? '$error' : '$error ($because)'));
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
              unawaited(runTool(event));
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
          (frame) => session?.sendAudio(frame.pcm),
          onError: (Object error) => controller.add(VoiceSessionFailed('$error')),
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

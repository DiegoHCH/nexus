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

    Future<void> shutdown() async {
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

      try {
        await for (final event in _askClaude(request.instruction)) {
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
        }
      } catch (error) {
        ok = false;
        answer
          ..clear()
          ..write('No se pudo ejecutar la tarea: $error');
      }

      session?.sendToolResult(
        callId: request.callId,
        name: request.name,
        result: answer.isEmpty ? 'La tarea terminó sin devolver nada.' : answer.toString(),
      );
      controller.add(VoiceToolFinished(ok: ok));
      keepAlive();
    }

    Future<void> boot() async {
      try {
        await _output.start();
        final live = await _gateway.connect();
        session = live;

        keepAlive();

        sessionSubscription = live.events.listen(
          (event) {
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
          onDone: controller.close,
        );

        micSubscription = _voiceInput.listen().listen(
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

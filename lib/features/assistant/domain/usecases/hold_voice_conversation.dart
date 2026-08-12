import 'dart:async';

import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';

/// La conversación completa: micrófono → socket → altavoz.
///
/// No extiende `UseCase<ReturnType, Params>` por lo mismo que [AskClaude]: ese
/// contrato es para trabajo de una sola respuesta, y esto es una sesión viva.
///
/// Aquí se junta lo que las tres piezas no saben la una de la otra: el
/// micrófono no sabe que su PCM va a un socket, el socket no sabe que su audio
/// se reproduce, y el altavoz no sabe que puede ser interrumpido. Cada una
/// sigue probándose por separado; el pegamento es esto.
class HoldVoiceConversation {
  const HoldVoiceConversation(this._voiceInput, this._gateway, this._output);

  /// Cuánto se espera sin actividad antes de cerrar sola la sesión.
  ///
  /// Corto a propósito: mientras está abierta, tu micrófono sale hacia Google.
  /// Pero no tan corto como para matar la conversación entre una respuesta y
  /// la repregunta, que es lo que pasaría cerrando al terminar cada frase.
  static const _idleTimeout = Duration(seconds: 6);

  final VoiceInput _voiceInput;
  final VoiceGateway _gateway;
  final AudioOutput _output;

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

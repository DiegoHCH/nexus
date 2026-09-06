import 'dart:async';

import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/la_puerta_que_saluda.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Lo que va pasando en la puerta, para quien la esté mirando.
sealed class LoQuePasaEnLaPuerta {
  const LoQuePasaEnLaPuerta();
}

/// La sesión quedó montada: a partir de aquí te oye.
final class LaPuertaEstaLista extends LoQuePasaEnLaPuerta {
  const LaPuertaEstaLista();
}

/// Lo que la puerta va diciendo, para el subtítulo bajo el orbe.
final class LaPuertaDice extends LoQuePasaEnLaPuerta {
  const LaPuertaDice(this.texto);
  final String texto;
}

/// Ya se sabe dónde: se abre esa conversación y la puerta se cierra.
final class LaPuertaEligio extends LoQuePasaEnLaPuerta {
  const LaPuertaEligio(this.carpeta, this.tarea);
  final PairedFolder carpeta;

  /// Lo que dijiste además de la carpeta, si dijiste algo.
  final String tarea;
}

/// No se pudo, y por qué. **Nunca se queda callada**: sin esto, un servicio que
/// no contesta se ve igual que una app que se colgó al arrancar.
final class LaPuertaSeCayo extends LoQuePasaEnLaPuerta {
  const LaPuertaSeCayo(this.motivo);
  final String motivo;
}

/// La puerta: saluda al arrancar y escucha dónde se va a trabajar.
///
/// 🔴 **Es una sesión de voz sin carpeta, y esa es toda su rareza.** El resto de
/// la app abre voz *dentro* de una conversación, que tiene carpeta, cuenta,
/// modelo y permisos colgando de ella; aquí no hay nada de eso todavía, porque
/// justamente lo que se está preguntando es dónde. Por eso no reusa
/// `HoldVoiceConversation` —once dependencias atadas a una carpeta— sino solo
/// las tres que hacen falta: el micro, el servicio y el altavoz.
///
/// **Y por eso no tiene herramientas.** No hay puente a Claude, no lee nada, no
/// escribe nada. Lo único que sale de la máquina es tu voz y los nombres de las
/// carpetas que se ofrecen — decidido a la vista, porque un nombre no es su
/// contenido y una puerta que esconde la mitad de las carpetas es media puerta.
///
/// Lo que dijiste **no lo interpreta el modelo**: lo resuelve
/// [LaPuertaQueSaluda] aquí dentro, con el mismo reconocedor que enruta un
/// encargo. Dejárselo al modelo sería pedirle que acierte un nombre de carpeta y
/// que además lo devuelva en un formato — dos cosas que fallan por separado.
class LaSesionDePuerta {
  const LaSesionDePuerta(this._microfono, this._servicio, this._altavoz);

  final VoiceInput _microfono;
  final VoiceGateway _servicio;
  final AudioOutput _altavoz;

  /// Abre la puerta. Cancelar el stream la cierra entera.
  ///
  /// 🔴 **Un `StreamController` y no un `async*`**, y no es estilo: cancelar la
  /// suscripción de un generador **no ejecuta sus `finally`** —medido, ver
  /// `LaSalidaQueSeCancela`—, así que con un `async*` el micrófono se quedaría
  /// abierto y el socket vivo cada vez que alguien cierra esta pantalla.
  Stream<LoQuePasaEnLaPuerta> abrir({
    required String saludo,
    required List<PairedFolder> carpetas,
  }) {
    late final StreamController<LoQuePasaEnLaPuerta> fuera;
    VoiceSession? sesion;
    StreamSubscription<VoiceEvent>? deLaSesion;
    StreamSubscription<AudioFrame>? delMicro;
    final oido = StringBuffer();
    var cerrada = false;

    Future<void> cerrar() async {
      if (cerrada) return;
      cerrada = true;
      await delMicro?.cancel();
      await deLaSesion?.cancel();
      await _altavoz.stop();
      await sesion?.close();
    }

    void terminar(LoQuePasaEnLaPuerta ultimo) {
      if (fuera.isClosed) return;
      fuera.add(ultimo);
      unawaited(
        cerrar().then((_) {
          if (!fuera.isClosed) fuera.close();
        }),
      );
    }

    void atender(VoiceEvent evento) {
      switch (evento) {
        case VoiceSessionReady():
          // El saludo se le pide en cuanto acepta audio, no antes: mandarlo
          // durante el montaje es hablarle a una sesión que todavía no escucha.
          sesion?.sendSystemNote(_loQueTieneQueDecir(saludo, carpetas));
          fuera.add(const LaPuertaEstaLista());

        // El audio se reproduce y no sale hacia la pantalla; lo que la pantalla
        // necesita es el texto, que llega aparte.
        case VoiceReplyAudio(:final pcm):
          _altavoz.enqueue(pcm);

        case VoiceReplyTranscript(:final text):
          fuera.add(LaPuertaDice(text));

        // 🔴 **Se mira en cada trozo, no al final del turno.** La transcripción
        // llega a pedazos y el nombre de una carpeta aparece entero en cuanto se
        // dice; esperar al final del turno añadiría un segundo de silencio justo
        // después de que ya se sabe la respuesta.
        case VoiceUserTranscript(:final text):
          oido.write(text);
          final dicho = LaPuertaQueSaluda.interpreta(oido.toString(), carpetas);
          if (dicho case SeTrabajaAqui(:final carpeta, :final tarea)) {
            terminar(LaPuertaEligio(carpeta, tarea));
          }

        case VoiceSessionFailed(:final message):
          terminar(LaPuertaSeCayo(message));

        // Lo demás es de una conversación con herramientas, y esta no las tiene.
        case _:
          break;
      }
    }

    fuera = StreamController<LoQuePasaEnLaPuerta>(
      onListen: () async {
        try {
          await _altavoz.start();
          final live = await _servicio.connect();
          sesion = live;
          deLaSesion = live.events.listen(
            atender,
            onError: (Object error) => terminar(LaPuertaSeCayo('$error')),
          );
          delMicro = _microfono.listen().listen(
            (frame) => sesion?.sendAudio(frame.pcm),
          );
        } on Object catch (error) {
          terminar(LaPuertaSeCayo('$error'));
        }
      },
      onCancel: cerrar,
    );

    return fuera.stream;
  }

  /// La instrucción que se le da al servicio: qué decir y qué esperar.
  ///
  /// Se le nombran las carpetas **para que sepa reconocerlas al oírlas**, no
  /// para que elija: quien elige es el reconocedor de aquí dentro. Y se le pide
  /// que no invente ninguna, que es el fallo que convertiría un «trabajemos en
  /// la tienda» en una carpeta que no existe.
  static String _loQueTieneQueDecir(
    String saludo,
    List<PairedFolder> carpetas,
  ) {
    final nombres = [for (final carpeta in carpetas) carpeta.name].join(', ');
    return 'Empieza diciendo exactamente esto y nada más: "$saludo". '
        'Después escucha en qué carpeta se va a trabajar y no hagas nada más. '
        'Las carpetas disponibles son: $nombres. '
        'Si lo que oyes no es ninguna de ellas, dilo en una frase corta y '
        'vuelve a preguntar. No inventes carpetas y no ofrezcas hacer nada '
        'más: lo único que hay que averiguar aquí es dónde se trabaja.';
  }
}

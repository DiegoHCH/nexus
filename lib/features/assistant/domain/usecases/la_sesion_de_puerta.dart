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
  const LaSesionDePuerta(
    this._microfono,
    this._servicio,
    this._altavoz, [
    this._log = _alVacio,
  ]);

  final VoiceInput _microfono;
  final VoiceGateway _servicio;
  final AudioOutput _altavoz;

  /// 🔴 **Sin esto no se puede diagnosticar nada.** La primera vez que esta
  /// puerta habló de verdad, decir «nexus» no abrió la conversación y el
  /// registro no tenía **una sola línea** de la puerta: ni lo que oyó, ni lo que
  /// dijo, ni por qué no eligió. Se mira lo mismo que ya mira la conversación de
  /// voz, que para eso lleva su contador de trozos desde el día que hizo falta.
  final void Function(String) _log;

  static void _alVacio(String _) {}

  /// Cuánto se espera a que **empiece** a despedirse.
  ///
  /// 🔴 **Dos plazos y no uno, porque protegen de cosas distintas.** Este cubre
  /// el caso de que no diga nada: llamó a la función y se quedó callado. Ahí
  /// esperar cinco segundos con la carpeta ya elegida se siente como un cuelgue,
  /// así que se abre y punto.
  static const plazoParaEmpezar = Duration(milliseconds: 1800);

  /// Y cuánto se le deja **mientras habla**, por si no termina nunca.
  ///
  /// Una frase de cortesía son dos segundos; ocho es cuatro veces eso. Lo que se
  /// protege es que una puerta abierta con el micrófono cogido no se quede
  /// esperando indefinidamente a un servicio que dejó de contestar.
  static const plazoHablando = Duration(seconds: 8);

  /// El nombre de la única función que la puerta puede recibir.
  static const _laHerramienta = 'elegirCarpeta';

  /// Lo que se le manda para que arranque a hablar.
  ///
  /// Llega como turno de usuario —es lo único que hay— así que es lo más
  /// neutro posible, y su instrucción de sistema le dice que no lo mencione.
  static const _laSenalDeArranque = '(inicio)';

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

    /// La puerta ya sabe dónde y se está despidiendo.
    ///
    /// 🔴 **Se avisa a la pantalla y la sesión se queda un momento más.**
    /// Cerrando en el mismo instante, la frase de «vale, abro nexus» se cortaba
    /// antes de empezar: la interfaz aparecía y la puerta se iba muda. Ahora la
    /// conversación se abre ya —que es lo que se pidió— y la despedida se oye
    /// encima, mientras llega.
    LaPuertaEligio? loElegido;
    Timer? elPlazoDeLaDespedida;

    /// Está hablando ella, así que el micro no se le manda.
    ///
    /// 🔴 **Media duplex a propósito, y medido.** Con el micro abierto mientras
    /// habla, el servicio toma cualquier ruido por una interrupción: en una
    /// prueba real transcribió una conversación de la habitación —«sí, porque el
    /// otro muchacho fue el que hizo el servicio en el día»— y cortó el saludo a
    /// media frase. Cada interrupción tira el audio en cola, y eso desde fuera
    /// se oye entrecortado; su «vale, abro nexus» ni llegó a sonar.
    ///
    /// El precio es no poder cortarla mientras habla. Para una puerta que dice
    /// una frase de tres segundos es el intercambio correcto: lo que se pierde
    /// es interrumpir un saludo, y lo que se gana es que se entienda.
    var hablando = false;

    Future<void> cerrar() async {
      if (cerrada) return;
      cerrada = true;
      elPlazoDeLaDespedida?.cancel();
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

    /// Ya se sabe dónde: se guarda y **se le deja despedirse**.
    ///
    /// 🔴 Un solo sitio para los dos caminos. La carpeta puede llegar por la
    /// llamada a la función o por la transcripción de lo que dijiste, y el
    /// segundo abría de golpe: se veía como que cambiaba la pantalla sin decir
    /// nada, que es justo lo que se estaba arreglando en el primero.
    void yaSeSabeDonde(PairedFolder carpeta, String tarea) {
      if (loElegido != null) return;
      loElegido = LaPuertaEligio(carpeta, tarea);
      // Dos plazos: uno corto por si no llega a abrir la boca, y otro largo
      // por si la abre y no la cierra. Ver [plazoParaEmpezar] y [plazoHablando].
      elPlazoDeLaDespedida = Timer(plazoParaEmpezar, () {
        if (hablando) {
          _log('puerta · está diciéndolo, se le deja acabar');
          elPlazoDeLaDespedida = Timer(plazoHablando, () {
            _log('puerta · no acabó de despedirse');
            final elegido = loElegido;
            if (elegido != null) terminar(elegido);
          });
          return;
        }
        _log('puerta · no dijo nada, se abre igual');
        final elegido = loElegido;
        if (elegido != null) terminar(elegido);
      });
    }

    void atender(VoiceEvent evento) {
      switch (evento) {
        case VoiceSessionReady():
          _log('puerta · sesión lista, se dispara el saludo');
          // 🔴 **Solo la señal de arranque, no el saludo.** Lo que se manda por
          // aquí llega como un turno de usuario, y con el saludo dentro el
          // modelo lo delataba: «me pidieron que dijera eso exactamente». La
          // frase vive en su instrucción de sistema; esto solo dice cuándo.
          sesion?.sendSystemNote(_laSenalDeArranque);
          fuera.add(const LaPuertaEstaLista());

        // El audio se reproduce y no sale hacia la pantalla; lo que la pantalla
        // necesita es el texto, que llega aparte.
        case VoiceReplyAudio(:final pcm):
          hablando = true;
          _altavoz.enqueue(pcm);

        case VoiceReplyTranscript(:final text):
          _log('puerta · dice: $text');
          fuera.add(LaPuertaDice(text));

        // 🔴 **Se mira en cada trozo, no al final del turno.** La transcripción
        // llega a pedazos y el nombre de una carpeta aparece entero en cuanto se
        // dice; esperar al final del turno añadiría un segundo de silencio justo
        // después de que ya se sabe la respuesta.
        case VoiceUserTranscript(:final text):
          oido.write(text);
          final acumulado = oido.toString();
          final dicho = LaPuertaQueSaluda.interpreta(acumulado, carpetas);
          _log('puerta · oye «$acumulado» → ${dicho.runtimeType}');
          if (dicho case SeTrabajaAqui(:final carpeta, :final tarea)) {
            _log('puerta · se trabaja en ${carpeta.name}');
            yaSeSabeDonde(carpeta, tarea);
          }

        // 🔴 **Así es como dice dónde**, y no por la transcripción. Medido: el
        // modelo oía «nexus» perfectamente y la transcripción de lo dicho no
        // llegaba —una sola trama en toda una sesión—, así que la puerta se
        // quedaba esperando algo que no venía. Que lo diga llamando a una
        // función es lo que el servicio sí manda siempre.
        //
        // **Y lo valida la app.** Que acierte el nombre es su trabajo; que esa
        // carpeta exista es el nuestro, y se comprueba con el mismo reconocedor
        // que enruta un encargo.
        case VoiceToolRequested(:final callId, :final name, :final arguments):
          if (name != _laHerramienta) break;
          final dicho = (arguments['carpeta'] as String?)?.trim() ?? '';
          final tarea = (arguments['tarea'] as String?)?.trim() ?? '';
          final resuelto = LaPuertaQueSaluda.interpreta(dicho, carpetas);
          _log('puerta · eligió «$dicho» → ${resuelto.runtimeType}');
          switch (resuelto) {
            case SeTrabajaAqui(:final carpeta):
              sesion?.sendToolResult(
                callId: callId,
                name: name,
                result:
                    'Abierta ${carpeta.name}. Dilo en una frase corta y no '
                    'preguntes nada más.',
              );
              // La interfaz no aparece todavía: se le deja decir «vale, abro
              // nexus» y la pantalla cambia cuando acabe. Ver [yaSeSabeDonde].
              yaSeSabeDonde(carpeta, tarea);
            case SeNombraronDos():
            case NoSeEntendioDonde():
              // Se le contesta que no, y sigue preguntando ella misma: cortar
              // aquí dejaría al modelo esperando una respuesta que no llega.
              sesion?.sendToolResult(
                callId: callId,
                name: name,
                result:
                    'No hay ninguna carpeta que se llame así. Pregunta otra vez '
                    'en una frase corta.',
              );
          }

        // Terminó de hablar: el micro vuelve a contar.
        case VoiceTurnCompleted() when loElegido == null:
          hablando = false;

        // Acabó de despedirse: ahora sí se abre la carpeta y se cierra.
        case VoiceTurnCompleted() when loElegido != null:
          _log('puerta · dicho lo suyo, se abre la carpeta');
          terminar(loElegido!);

        // Lo interrumpido se tira, o lo viejo se sigue oyendo pisado con lo
        // nuevo — que desde fuera se oye entrecortado. Lo mismo que hace una
        // conversación de voz.
        case VoiceInterrupted():
          unawaited(_altavoz.discard());

        case VoiceSessionFailed(:final message):
          _log('puerta · se cayó: $message');
          terminar(LaPuertaSeCayo(message));

        // Lo demás es de una conversación con herramientas, y esta no las tiene.
        case _:
          break;
      }
    }

    fuera = StreamController<LoQuePasaEnLaPuerta>(
      onListen: () async {
        try {
          // 🔴 **El micro se engancha antes de conectar, y el orden importa.**
          // El motor de audio nativo monta un grafo distinto según quién lo
          // tenga cogido, así que enganchar el micrófono **después** de que
          // empiece a sonar la respuesta lo remonta a media reproducción: el
          // saludo se oía entrecortado y una conversación normal no, porque ahí
          // hablas tú primero y el grafo ya está montado cuando llega el audio.
          await _altavoz.start();
          delMicro = _microfono.listen().listen((frame) {
            // La sesión todavía no existe al principio; esos trozos se caen, que
            // es justo lo que se quiere: lo que hace falta es el motor montado,
            // no mandar audio antes de tiempo. Y mientras habla ella tampoco se
            // le manda — ver [hablando].
            if (hablando) return;
            sesion?.sendAudio(frame.pcm);
          });

          final live = await _servicio.connect(
            perfil: ComoLaPuerta(
              saludo: saludo,
              carpetas: [for (final carpeta in carpetas) carpeta.name],
            ),
          );
          sesion = live;
          deLaSesion = live.events.listen(
            atender,
            onError: (Object error) => terminar(LaPuertaSeCayo('$error')),
          );
        } on Object catch (error) {
          terminar(LaPuertaSeCayo('$error'));
        }
      },
      onCancel: cerrar,
    );

    return fuera.stream;
  }
}

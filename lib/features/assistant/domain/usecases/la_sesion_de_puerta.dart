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

/// Está diciendo algo, o acabó de decirlo.
///
/// 🔴 **Porque la barra decía «Escuchando» mientras hablaba.** El orbe y el
/// rótulo se ponían en «escuchando» al abrir la puerta y ahí se quedaban, así
/// que durante el saludo entero la pantalla contaba lo contrario de lo que
/// pasaba — y quien lo mira aprende a no creerle. Escuchar es lo que hace
/// **cuando termina la frase**, y eso es justo lo que este evento dice.
final class LaPuertaHabla extends LoQuePasaEnLaPuerta {
  const LaPuertaHabla(this.hablando);

  final bool hablando;
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
  ///
  /// 🔴 **Y se deriva del silencio que cierra el turno, no se elige a mano.**
  /// Eran 1800 ms fijos, menos de lo que el propio servicio tarda en dar por
  /// terminada tu frase —1,2 s de silencio, y solo entonces llama a la función y
  /// habla—. O sea que el plazo vencía **antes** de que pudiera abrir la boca y
  /// la carpeta se abría en silencio: reportado dos veces con las mismas
  /// palabras, «abre de una el chat y no dice lo del mensaje». Medido en el
  /// registro: «puerta · no dijo nada, se abre igual».
  ///
  /// Dos segundos por encima de ese silencio: lo que tarda en decidir y arrancar
  /// la voz. Si el número del servicio cambia, este se mueve con él — que es
  /// justo lo que no pasaba cuando eran dos constantes en dos capas.
  static final plazoParaEmpezar =
      ElRitmoDeLaVoz.silencioQueCierraElTurno + const Duration(seconds: 2);

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
    ///
    /// 🔴 **Y cuando los dos caminos no coinciden, manda la función.** Pasó, con
    /// el registro delante: la transcripción llegó hecha polvo —«Franma Y B2C
    /// Mobile B2C Nexus Franma Y B2C Oé, hazme caso»— y ahí dentro estaba la
    /// palabra «nexus», así que el reconocedor eligió *nexus*; un segundo
    /// después el modelo llamó a la función con *front-mobile-b2c*, que es lo
    /// que de verdad le habían dicho. Como el primero ya había escrito, se le
    /// contestó «abierta front-mobile-b2c» —y eso es lo que dijo en voz alta— y
    /// se abrió **nexus**. Decir una cosa y abrir otra es el único fallo de esta
    /// pantalla que no se puede permitir, así que [corrige] existe: mientras no
    /// se haya abierto nada, la función reescribe lo que la transcripción
    /// adivinó.
    void yaSeSabeDonde(
      PairedFolder carpeta,
      String tarea, {
      bool corrige = false,
    }) {
      final antes = loElegido;
      if (antes != null && !corrige) return;
      if (antes != null && antes.carpeta.path != carpeta.path) {
        _log(
          'puerta · la función manda: era ${antes.carpeta.name} y es '
          '${carpeta.name}',
        );
      }
      loElegido = LaPuertaEligio(carpeta, tarea);
      // Corrigiendo no se rearman los plazos: el que hay ya está contando desde
      // que se supo la carpeta, y reiniciarlo alargaría la espera cada vez que
      // el modelo confirma lo que la transcripción ya había acertado.
      if (antes != null) return;
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
          // Solo en el primer trozo: son decenas por frase y la pantalla no
          // tiene por qué enterarse de cada uno.
          if (!hablando) {
            fuera.add(const LaPuertaHabla(true));
            // 🔴 **Y lo oído se cierra aquí.** El acumulado cruzaba turnos, así
            // que una palabra de hace tres frases podía decidir la carpeta de
            // ahora: en el registro, un «nexus» perdido en medio de un intento
            // fallido eligió esa carpeta cuando lo que se estaba diciendo era
            // otra. Que ella contesta significa que tu turno ya se consumió.
            oido.clear();
          }
          hablando = true;
          _altavoz.enqueue(pcm);

        case VoiceReplyTranscript(:final text):
          _log('puerta · dice: $text');
          fuera.add(LaPuertaDice(text));

        // 🔴 **Se apunta lo que oye, y no se decide nada con ello.** Aquí se
        // elegía la carpeta en cuanto el nombre aparecía en la transcripción, y
        // eso daba dos clases de falso positivo, las dos medidas:
        //
        // - **Ruido con una palabra dentro.** «Franma Y B2C Mobile B2C Nexus
        //   Franma Y B2C Oé, hazme caso» eligió *nexus* porque ahí estaba la
        //   palabra, cuando lo que se estaba diciendo era otra carpeta. Y como
        //   el primero en escribir ganaba, la función llegó después con la
        //   buena, se le contestó «abierta front-mobile-b2c» —que es lo que
        //   dijo en voz alta— y se abrió *nexus*.
        // - **Una negación.** «No, nexus no, espera» también elegía.
        //
        // La carpeta la dice **la función**, que es el camino que el servicio
        // manda siempre y el que su instrucción le pide usar primero. Un solo
        // sitio donde se decide: si el modelo no llama, se repite la frase — que
        // es infinitamente mejor que abrir la carpeta equivocada.
        //
        // La transcripción se sigue registrando porque es con lo que se
        // diagnostica: sin ella, «no me hizo caso» no tiene evidencia.
        case VoiceUserTranscript(:final text):
          oido.write(text);
          _log('puerta · oye «${oido.toString().trim()}»');

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
              //
              // Y **corrigiendo**: si la transcripción había adivinado otra, la
              // que se abre es esta, que es la que él acaba de anunciar.
              yaSeSabeDonde(carpeta, tarea, corrige: true);
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
          fuera.add(const LaPuertaHabla(false));

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
            // 🔴 **Y en cuanto se sabe la carpeta, el micrófono deja de
            // importar.** Lo único que falta es que diga su frase, y mandarle
            // audio mientras la prepara es darle motivos para no decirla: en la
            // puerta el servicio **sí** interrumpe —ahí está bien, es como se
            // le corta el saludo— así que cualquier ruido de la habitación, o
            // el final de tu propia frase, le pisaba la despedida antes de
            // empezar. Medido en el registro: «eligió front-mobile-b2c» y, tres
            // segundos después, «no dijo nada, se abre igual», dos veces
            // seguidas y con la transcripción llena de ruido mal oído.
            if (loElegido != null) return;
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

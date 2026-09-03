import 'dart:async';

import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/el_despacho_de_carpeta.dart';
import 'package:nexus/features/assistant/domain/repositories/la_agenda_de_hoy.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/repositories/correr_una_prueba.dart';
import 'package:nexus/features/assistant/domain/repositories/el_parte_del_dia.dart';
import 'package:nexus/features/assistant/domain/usecases/claude_errand.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_sale_hacia_la_voz.dart';
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
    this._correrUnaPrueba,
    this._elParteDelDia,
    this._laAgendaDeHoy,
    this._despacho,
    this._carpetaDeAqui, {
    this.graciaDeLaRuta = _graciaDeLaRuta,
  });

  /// A qué carpeta va lo que se dice, y quien lo lleva.
  ///
  /// 🔴 **Entra por aquí porque hablando no se pasa por `submit`.** El enrutado
  /// vivía dentro del controlador, y el compositor y el teléfono entran por ahí;
  /// esta conversación llama al puente de Claude directamente. Resultado: «en el
  /// front mobile, arregla el login» funcionaba escribiendo y no hablando, que
  /// es de donde salió la idea.
  ///
  /// Es un puerto y no una función suelta porque **mover un encargo es mover la
  /// pantalla** —enfocar otra conversación, o abrirla— y eso no lo puede hacer
  /// el dominio.
  final ElDespachoDeCarpeta _despacho;

  /// La carpeta de esta conversación, leída en el momento.
  ///
  /// Una función y no un valor por lo mismo que el idioma y los nombres: se
  /// puede cambiar mientras la sesión está abierta, y un valor fijo se
  /// congelaría al conectar.
  final String? Function() _carpetaDeAqui;

  /// Cuánto se le da al modelo para pasar por Claude lo que contestó de
  /// memoria, antes de hacerlo por él. Ver [_graciaDeLaRuta].
  ///
  /// Inyectable por lo mismo que el tope del registro: hay pruebas que van del
  /// **contenido** que llega a Claude, no de los plazos, y obligarlas a mover
  /// un reloj falso para llegar a lo que afirman las convierte en pruebas de
  /// otra cosa.
  final Duration graciaDeLaRuta;

  static const _sinAgenda =
      'Los avisos de agenda están apagados o no tienen carpeta, así que no hay '
      'calendario leído. Dilo así, y sugiere encenderlos en Ajustes › Avisos.';

  /// Quien sabe lanzar una prueba sin pasar por Claude. Ver [CorrerUnaPrueba].
  final CorrerUnaPrueba _correrUnaPrueba;

  /// Quien sabe qué se hizo el último día de trabajo. Ver [ElParteDelDia].
  final ElParteDelDia _elParteDelDia;

  /// Quien ya tiene leída la agenda de hoy. Ver [LaAgendaDeHoy].
  final LaAgendaDeHoy _laAgendaDeHoy;

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

  /// Lo que se espera **antes de que el servicio dé la primera señal**.
  ///
  /// Más largo porque ahí no se está vigilando una conversación: se está
  /// esperando a que empiece. Cabe el montaje (2,5 s medidos), lo que tardes en
  /// decidir qué decir, y la espera del detector de voz del servicio. Y sigue
  /// siendo un plazo y no una espera infinita: si abres la voz sin querer, el
  /// micrófono se cierra solo — que es la regla que sostiene todo esto.
  static const _openingGrace = Duration(seconds: 20);

  /// Lo que se le da al modelo para pasar por Claude lo que contestó de
  /// memoria, **antes de hacerlo por él**.
  ///
  /// Diez segundos porque lo que se le pide es un turno entero: entender la
  /// nota y llamar a la herramienta. Cumpliendo tarda uno o dos; el plazo está
  /// puesto para el caso en que no piensa cumplir, no para el normal.
  static const _graciaDeLaRuta = Duration(seconds: 10);

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
    StreamSubscription<void>? pausaSubscription;
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

    /// El turno cuya ruta se le pidió al modelo y todavía no ha atendido, y el
    /// reloj que decide cuándo se deja de esperar.
    ///
    /// 🔴 Existe porque pedirle que lo pase **no es garantía**: la API de voz no
    /// admite obligar a llamar a una herramienta. Si hace caso, la instrucción
    /// la redacta él —que es quien oyó el audio— y no llega ni una palabra de
    /// la transcripción a Claude. Si no, vence el plazo y va el camino de
    /// antes, que sigue existiendo por eso.
    int? rutaPedidaEn;
    Timer? relojDeLaRuta;

    /// Cuántas veces hizo caso y cuántas hubo que hacerlo por él. Se cuenta por
    /// lo de siempre en este archivo: para saber si la petición sirve de algo
    /// antes de decidir si hace falta algo más.
    var loPaso = 0;
    var noLoPaso = 0;

    var micFrames = 0;
    var sentFrames = 0;
    var eventsSeen = 0;

    /// El reloj de la sesión, y las dos marcas que hacen falta para saber si
    /// b11 es lo que parece.
    ///
    /// Los contadores dicen **cuántos** trozos y eventos, no **cuándo**, y sin
    /// eso no se puede distinguir «el servicio tardó más que el plazo» de «el
    /// micrófono entrega cinco veces menos de lo normal»: las dos cosas se ven
    /// igual en un recuento. Con el reloj, un trozo pasa a valer milisegundos y
    /// la sospecha se convierte en una cifra.
    final clock = Stopwatch()..start();

    /// Cuándo contestó el servicio que la sesión está montada.
    int? readyAt;

    /// Cuándo llegó el primer evento que **no** es ese: la primera señal de que
    /// nos oyó. Es el que corre contra [_idleTimeout], y por tanto el número
    /// que decide si esto era una carrera perdida.
    int? heardAt;

    /// Se acaba de mandar el resultado de una herramienta y el modelo todavía
    /// no ha dicho nada sobre él.
    ///
    /// 🔴 **Es el mismo caso que abrir la sesión, no el de una pausa al
    /// hablar.** Al modelo le toca generar una respuesta entera desde cero, y
    /// eso tarda lo que tarda una primera señal: medido entre 5 y 11 s en esta
    /// máquina. Los 6 s del plazo corto están calibrados para el silencio de
    /// alguien que está pensando qué decir, que es otra cosa.
    ///
    /// Se vio pidiendo la agenda: dijo «consulto tu agenda, Argonauta» y se
    /// quedó ahí. Reiniciar el reloj no arreglaba nada —cada evento del
    /// servicio ya lo reinicia, y la petición de la herramienta es un evento—:
    /// lo que hacía falta era **darle el plazo largo** mientras se espera.
    var esperandoRespuesta = false;

    /// Cuántas herramientas del modelo se están atendiendo ahora mismo.
    ///
    /// 🔴 **El plazo largo de [responder] llega tarde: hay que sostener la
    /// sesión mientras se *calcula* el resultado, no solo mientras se narra.**
    /// `responder` reinicia el reloj cuando el resultado ya está listo, y eso no
    /// sirve de nada si producirlo tarda más que el plazo: para cuando por fin
    /// se manda, `session` ya es `null` y el resultado no va a ninguna parte.
    ///
    /// Medido pidiendo la agenda a los 34 s de abrir la app: la lectura del
    /// calendario del arranque seguía en vuelo —un `claude -p` con el conector,
    /// 32 s— y `deHoy()` se queda esperándola. Dijo «consulto tu agenda de hoy»
    /// y ahí acabó todo. En el registro se ve entero: cierre por inactividad a
    /// las 07:38:49 y el resultado saliendo a las 07:39:07, contra una sesión
    /// que llevaba dieciocho segundos cerrada.
    ///
    /// Es un contador y no un booleano porque el modelo puede pedir dos
    /// herramientas en el mismo turno, y la primera que acabe no puede levantar
    /// la protección de la otra.
    var herramientasEnVuelo = 0;

    String reloj() {
      final ready = readyAt == null ? '—' : '${readyAt}ms';
      final heard = heardAt == null ? 'todavía nada' : '${heardAt}ms';
      return 't+${clock.elapsedMilliseconds}ms · sesión lista en $ready · '
          'primera señal del servicio en $heard';
    }

    Future<void> shutdown() async {
      closing = true;
      // Primero el encargo: si hay un `claude -p` en marcha, cerrar la
      // conversación sin matarlo lo deja trabajando de fondo para nadie.
      abortErrand?.call();
      abortErrand = null;
      idleTimer?.cancel();
      idleTimer = null;
      relojDeLaRuta?.cancel();
      relojDeLaRuta = null;
      await micSubscription?.cancel();
      await pausaSubscription?.cancel();
      await sessionSubscription?.cancel();
      await _output.stop();
      await session?.close();
      micSubscription = null;
      pausaSubscription = null;
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
      // Apagando no hay nada que mantener vivo. Sin esto, un `keepAlive` que
      // llegara después del cierre —el resultado de una herramienta que volvió
      // tarde, por ejemplo— dejaba un temporizador huérfano que vencía solo
      // para escribir un segundo «cierre por inactividad» de una sesión que ya
      // no existía. Se vio en el registro justo debajo del cierre de verdad.
      if (closing) return;

      // **Antes de la primera señal se espera más**, y ese era b11.
      //
      // El plazo corto está pensado para notar que una conversación viva se
      // apagó. Al principio no hay conversación que mantener: hay una espera
      // legítima, y el contador la estaba midiendo como si fuera abandono.
      //
      // Medido en una sesión que se salvó por los pelos: el `setupComplete`
      // llegó a los 2453 ms —y como es un evento, reinició la cuenta—, y la
      // primera señal de que el servicio nos oía, a los **7251 ms**. Con 6 s
      // desde el setup, el cierre tocaba a los 8453: sobrevivió por 1,2 s. Las
      // sesiones que fallaban perdían esa misma carrera, y encajan clavadas —
      // 63 trozos a ~100 ms cada uno son los 6 s enteros de ventana.
      //
      // El hueco es estructuralmente pequeño: el montaje se come 2,5 s y el
      // detector de voz del servicio está alargado a propósito
      // —`silenceDurationMs: 1200`, sensibilidad baja— para no cortar frases
      // largas. No es que fuera lento: es que se le estaba dando menos tiempo
      // del que su propia configuración necesita.
      final grace = heardAt == null || esperandoRespuesta
          ? _openingGrace
          : _idleTimeout;
      idleTimer?.cancel();
      idleTimer = Timer(grace, () async {
        // Con un encargo en marcha —o con una herramienta a medio atender— no
        // se cierra, y punto. Reiniciar la cuenta con cada evento de Claude no
        // bastaba: **el primero tarda más que el propio plazo** —arrancar el
        // CLI, cargar los CLAUDE.md del árbol— así que la sesión se cerraba
        // antes de recibir nada y `shutdown()` mataba el proceso. Silencio
        // mientras se trabaja no es inactividad.
        //
        // Las dos condiciones porque `abortErrand` solo cubre las herramientas
        // que pasan por `runErrand`, y hay tres que no: la agenda, las pruebas
        // y la herramienta inventada. Esas se creían instantáneas.
        if (abortErrand != null || herramientasEnVuelo > 0) {
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
          'voz · cierre por inactividad tras ${grace.inSeconds} s '
          '${heardAt == null ? '(sin señal del servicio todavía)' : ''}· '
          '$micFrames trozos del micro, $sentFrames enviados, '
          '$eventsSeen eventos recibidos · $turn turnos, '
          '$answeredAlone corregidos, $stale descartados por viejos · '
          '${reloj()}',
        );
        await shutdown();
        if (!controller.isClosed) await controller.close();
      });
    }

    /// Le devuelve al servicio el resultado de una herramienta **y reinicia el
    /// reloj de inactividad**.
    ///
    /// 🔴 **Las dos cosas juntas, y por eso existe esta función.** Mandar un
    /// resultado significa que ahora le toca al modelo lo que más tarda:
    /// generar la respuesta hablada. Eso son los mismos segundos que la primera
    /// señal de cualquier turno —medido entre 5 y 11 s en esta máquina— y en
    /// ese rato no llega ni un evento, así que el plazo de inactividad corría
    /// desde antes de la llamada y podía ganar la carrera.
    ///
    /// Pasó pidiendo la agenda por voz: dijo «consulto tu agenda, Argonauta» y
    /// se quedó ahí. La agenda se contesta de memoria y no pasa por
    /// `runErrand`, así que ni `abortErrand` ni los eventos de Claude tocaban
    /// el reloj — nada lo reiniciaba. Los caminos con encargo tenían la misma
    /// carrera, solo que menos visible porque el último evento de Claude cae
    /// más cerca de la narración.
    ///
    /// Se resuelve aquí y no con un `keepAlive()` en cada sitio porque hay seis
    /// y ya se habían olvidado en cuatro. Un invariante que hay que recordar en
    /// seis puntos se rompe en el séptimo.
    void responder({
      required String callId,
      required String name,
      required String result,
    }) {
      final viva = session;
      // Sin sesión no hay a quién contestar, y callarlo era parte de por qué
      // esto costó dos intentos: el `?.` se comía la entrega sin dejar rastro y
      // en pantalla no había ni fallo ni respuesta, solo la frase de antes.
      if (viva == null || closing) {
        _log(
          'voz · el resultado de «$name» llegó a una sesión ya cerrada, '
          'así que nadie lo va a narrar · ${reloj()}',
        );
        return;
      }
      viva.sendToolResult(callId: callId, name: name, result: result);
      esperandoRespuesta = true;
      keepAlive();
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
    /// 🔴 **El idioma de lo que sale de aquí es una decisión, no un olvido.**
    ///
    /// Lo que devuelve `runErrand` —«La tarea falló: …», «La tarea terminó sin
    /// devolver nada.»— está en español a pelo, fuera de `NexusStrings`, y eso
    /// se ha señalado dos veces como una fuga de i18n. No lo es, y conviene
    /// dejarlo escrito para no volver a levantarlo cada revisión.
    ///
    /// **Estos textos no van a la pantalla: son el resultado de la herramienta
    /// que se le devuelve al modelo.** Gemini los lee y los narra en el idioma
    /// que tenga configurado, así que alguien con la app en inglés no oye
    /// español — oye a Gemini contando en inglés lo que leyó en español. Son
    /// material para un modelo, igual que la instrucción de sistema y las
    /// descripciones de las herramientas, y el idioma de esos ya se decidió
    /// aparte.
    ///
    /// Lo que **sí** iría a `NexusStrings` es cualquier cosa que se pinte o se
    /// hable directamente. Si algún día uno de estos se enseña tal cual, deja de
    /// valer este argumento y hay que moverlo.
    Future<String?> runErrand(String instruction, String headline) async {
      controller.add(VoiceToolStarted(headline));
      final answer = StringBuffer();
      var ok = true;
      var aborted = false;
      int? turnTokens;
      int? contextTokens;
      String? modelo;
      final ended = Completer<void>();
      void finish() {
        if (!ended.isCompleted) ended.complete();
      }

      final errand = _askClaude(instruction).listen(
        (event) {
          // Un encargo puede tardar minutos, y en ese rato no llega nada del
          // servicio de voz: sin esto, la sesión se cerraría sola por
          // inactividad justo mientras se trabaja para ella.
          // Ya dijo algo sobre el resultado: a partir de aquí el silencio
          // vuelve a ser silencio conversacional y manda el plazo corto.
          if (event is! VoiceSessionReady) esperandoRespuesta = false;
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
            // Hablando, la pantalla puede estar detrás: el mismo motivo por el
            // que la cola se dice en voz alta. Que las reglas del repositorio
            // hayan cambiado desde la última vez es justo lo que no puede
            // quedarse en un chip que nadie está mirando.
            case ClaudeRulesChanged(:final paths):
              controller.add(
                VoiceToolProgress(
                  'Aviso: han cambiado las reglas del repositorio '
                  '(${paths.length} archivo(s)). Sigo con el encargo.',
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
              // El modelo se guarda para sacarlo con el fin del encargo. Esto era
              // un `break`, y ese `break` era el defecto: sin modelo el medidor
              // asumía una ventana de 200k, así que hablando con un modelo de un
              // millón el porcentaje salía multiplicado por cinco.
              modelo = event.model;
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
          model: modelo,
        ),
      );
      keepAlive();
      return answer.isEmpty
          ? 'La tarea terminó sin devolver nada.'
          : answer.toString();
    }

    /// El tope de lo que sale hacia el servicio de voz, aplicado **en los dos
    /// sitios por los que sale** y no al devolver el encargo.
    ///
    /// La diferencia importa: lo que devuelve `runErrand` también alimenta la
    /// pantalla, y ahí la respuesta se ve entera. Recortar en el origen
    /// escondería en el Mac algo que el Mac sí puede enseñar; lo que se recorta
    /// es lo que cruza la frontera.
    String loQueCabe(String respuesta, String de) {
      if (!LoQueSaleHaciaLaVoz.sobra(respuesta)) return respuesta;
      _log(
        'voz · «$de» devolvió ${respuesta.length} caracteres y hacia el '
        'servicio de voz salen ${LoQueSaleHaciaLaVoz.maxCaracteres}: el resto '
        'se queda en la pantalla',
      );
      return LoQueSaleHaciaLaVoz.recortar(respuesta);
    }

    /// El modelo contestó por su cuenta algo que tenía que haber ido a Claude.
    ///
    /// Aquí está el candado que b6 pedía: la comprobación no la hace el modelo,
    /// la hace este código con lo que el usuario dijo de verdad. Lo que ya se
    /// esté oyendo se corta —igual que una interrupción— y en su lugar suena la
    /// respuesta buena.
    Future<void> enforceClaude(String utterance, int askedAt) async {
      unawaited(_output.discard());
      // Lo que viaja va **marcado como transcripción**, no como una frase que
      // alguien dijo: es lo que le permite a Claude leer la intención en vez de
      // contestar literalmente a una palabra mal oída. El titular sigue siendo
      // el texto crudo, que es lo que de verdad se va a interpretar.
      final answer = await runErrand(
        VoiceRouting.deLaTranscripcion(utterance),
        utterance,
      );
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
      session?.sendSystemNote(
        VoiceRouting.correction(loQueCabe(answer, 'la corrección')),
      );
    }

    /// Le pide al modelo que pase por Claude lo que acaba de contestar de
    /// memoria, y **solo lo hace por él si no atiende**.
    ///
    /// 🔴 Este es el orden nuevo, y el motivo está en [VoiceRouting.pasaloTu]:
    /// la transcripción de lo que dijiste la escribe el servicio de voz aparte
    /// y llega mal —«¿qué reuniones tengo para hoy?» salió como «Este
    /// akeroniano es tengo para hoy»— mientras que el modelo había entendido
    /// bien. Pedirle que redacte él la instrucción usa la pieza que funcionó en
    /// vez de la que falló.
    void pidelaRuta(String utterance, int askedAt) {
      // El audio de memoria se tira igual que antes: es una respuesta que no
      // le tocaba dar, y dejarla sonar mientras se arregla es peor.
      unawaited(_output.discard());
      session?.sendSystemNote(VoiceRouting.pasaloTu);
      // Le toca generar un turno entero, así que manda el plazo largo del
      // reloj de inactividad, igual que después de un resultado.
      esperandoRespuesta = true;
      keepAlive();

      rutaPedidaEn = askedAt;
      relojDeLaRuta?.cancel();
      relojDeLaRuta = Timer(graciaDeLaRuta, () {
        // Lo pasó él, o ya se habla de otra cosa: no hay nada que rescatar.
        if (rutaPedidaEn != askedAt || turn != askedAt || closing) return;
        rutaPedidaEn = null;
        noLoPaso++;
        _log(
          'b6 · no lo pasó ni pidiéndoselo ($noLoPaso de '
          '${loPaso + noLoPaso} en esta sesión): va la transcripción, y '
          'marcada como tal — «$utterance»',
        );
        unawaited(enforceClaude(utterance, askedAt));
      });
    }

    Future<void> runTool(VoiceToolRequested request) async {
      // La de las pruebas se atiende aquí y no acaba en Claude: va al lanzador
      // de Nexus, así que no depende de que un MCP esté vivo ni del modo de
      // permisos. Va delante del resto porque `ClaudeErrand.forTool` no la
      // conoce y la trataría como una herramienta inventada.
      if (request.name == ClaudeErrand.testTool) {
        final pedido = (request.arguments['prueba'] as String?)?.trim() ?? '';
        controller.add(VoiceToolStarted('Pruebas: $pedido'));
        final dicho = await _correrUnaPrueba.loQuePidieron(pedido);
        controller.add(const VoiceToolFinished(ok: true));
        responder(
          callId: request.callId,
          name: request.name,
          result: loQueCabe(dicho, request.name),
        );
        return;
      }

      // El parte sí acaba en Claude, pero con un encargo que aquí no se sabe
      // escribir: el material —qué día fue el último con trabajo, qué se hizo y
      // en qué carpetas— lo trae el puerto. De ahí en adelante es un encargo
      // como cualquier otro, y por eso pasa por `runErrand`: así el servicio de
      // voz se mantiene vivo mientras Claude redacta, que puede ser un minuto.
      // 🔴 **No pasa por Claude ni sale de la máquina**, y por eso no usa
      // `runErrand`: no hay encargo que mantener vivo. Lo que no se puede
      // prometer es que sea instantáneo. Casi siempre lo es —la agenda ya está
      // leída, hizo falta para poder avisar— pero si la lectura del día está en
      // vuelo, `deHoy()` espera a que acabe, y esa sí es un `claude -p` con el
      // conector de Calendar: 32 s medidos al arrancar la app. Que es
      // exactamente cuando alguien pregunta qué reuniones tiene.
      //
      // De ahí las dos líneas de alrededor: el titular, porque treinta segundos
      // sin nada en pantalla se leen como que no oyó; y `atender`, que sostiene
      // la sesión mientras esto tarda.
      if (request.name == ClaudeErrand.agendaTool) {
        // 🔴 `VoiceLookupStarted` y **no** la pareja de un encargo: esto no
        // toca el repositorio, no produce documentos y no gasta contexto.
        // Anunciarlo como encargo hacía que al terminar corriera la cola de
        // después de uno, y eso colgó un documento viejo de la respuesta.
        controller.add(const VoiceLookupStarted('La agenda de hoy'));
        final agenda = await _laAgendaDeHoy.deHoy();
        responder(
          callId: request.callId,
          name: request.name,
          // Sin agenda que mirar —avisos apagados, sin carpeta— se dice tal
          // cual en vez de contestar «no tienes nada», que sería mentira.
          result: agenda ?? _sinAgenda,
        );
        return;
      }

      if (request.name == ClaudeErrand.parteTool) {
        final delDia = await _elParteDelDia.instruccion();
        if (delDia == null) {
          responder(
            callId: request.callId,
            name: request.name,
            result:
                'No hay ningún día anterior con trabajo que contar, así que no '
                'hay parte.',
          );
          return;
        }

        final parte = await runErrand(delDia, 'El parte del día');
        if (parte == null) return;
        // Antes de contestarle al modelo: lo que llegue después es su
        // narración, y el parte tiene que estar ya puesto —con su botón— para
        // cuando quien escucha mire la pantalla.
        _elParteDelDia.yaEstaEscrito(parte);
        responder(
          callId: request.callId,
          name: request.name,
          result: loQueCabe(parte, request.name),
        );
        return;
      }

      var instruction = ClaudeErrand.forTool(request.name, request.arguments);
      // Herramienta desconocida o argumentos incompletos: se contesta igual.
      // Callarse dejaría al modelo esperando una respuesta que no va a llegar,
      // y la conversación muda para siempre.
      if (instruction == null || instruction.isEmpty) {
        responder(
          callId: request.callId,
          name: request.name,
          result:
              'No se pudo ejecutar «${request.name}»: faltan datos o esa herramienta no existe.',
        );
        return;
      }

      // A qué carpeta va, antes de trabajar. Solo para el encargo general: las
      // demás herramientas —la prueba, el parte, la agenda— ya saben dónde van.
      if (request.name == ClaudeErrand.askTool) {
        final donde = await _despacho.despachar(
          instruction,
          carpetaDeAqui: _carpetaDeAqui(),
          loQueSeVe: instruction,
          allowWrites: true,
          attachments: const [],
        );
        switch (donde) {
          case AtiendeloTu(:final tarea):
            instruction = tarea;
          // Se fue a otra conversación: allí se ve el trabajo. Aquí solo queda
          // decirlo, y **decirlo importa** — sin eso la voz se queda callada y
          // parece que no pasó nada.
          case YaSeFue(:final carpeta):
            responder(
              callId: request.callId,
              name: request.name,
              result:
                  'El encargo se mandó a «$carpeta», que es la carpeta que se '
                  'nombró. El trabajo sale por ahí. Dilo en una frase.',
            );
            return;
          case HayQueDecir(:final texto):
            responder(
              callId: request.callId,
              name: request.name,
              result: texto,
            );
            return;
        }
      }

      final answer = await runErrand(instruction, _headline(request));
      if (answer == null) return;
      responder(
        callId: request.callId,
        name: request.name,
        result: loQueCabe(answer, request.name),
      );
    }

    /// Atiende una herramienta **sosteniendo la sesión mientras dura**.
    ///
    /// 🔴 Envuelve a `runTool` en vez de contar dentro de él porque ahí hay seis
    /// salidas —una por herramienta, y dos que vuelven sin contestar cuando el
    /// encargo se canceló—. El `finally` de aquí es el único punto por el que
    /// pasan todas. Es la misma razón por la que existe [responder]: un
    /// invariante repartido en seis sitios se rompe en el séptimo.
    Future<void> atender(VoiceToolRequested request) async {
      herramientasEnVuelo++;
      // El reloj venía corriendo desde el último evento del servicio, que fue
      // esta misma petición: sin reiniciarlo, el plazo empieza ya gastado.
      keepAlive();
      try {
        await runTool(request);
      } finally {
        herramientasEnVuelo--;
        // Lo que queda por delante es la narración y le toca el plazo largo,
        // que lo pone `responder`. Pero si la herramienta salió sin contestar
        // —encargo cancelado— nadie ha tocado el reloj desde que empezó.
        keepAlive();
      }
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
          // El montaje de la sesión no cuenta como «nos oyó»: llega siempre,
          // hables o no, y es justo el único evento que tenían las sesiones
          // que fallaron.
          if (event is VoiceSessionReady) {
            readyAt ??= clock.elapsedMilliseconds;
          } else if (heardAt == null) {
            heardAt = clock.elapsedMilliseconds;
            _log('voz · primera señal del servicio · ${reloj()}');
          }
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
              // Y si se le había pedido, hizo caso: se cancela el plazo para
              // que no vaya además la transcripción por detrás. La instrucción
              // que va a Claude es la que redactó él, sin una palabra del texto
              // del servicio de voz — que es el arreglo entero.
              if (rutaPedidaEn != null) {
                rutaPedidaEn = null;
                relojDeLaRuta?.cancel();
                loPaso++;
                _log(
                  'b6 · se le pidió que lo pasara y lo pasó ($loPaso de '
                  '${loPaso + noLoPaso} en esta sesión), con su propia '
                  'instrucción y sin la transcripción',
                );
              }
              unawaited(atender(event));
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
                  pidelaRuta(utterance, turn);
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
                '$eventsSeen eventos recibidos · ${reloj()}',
              );
            }
          },
          // Si el flujo termina, el audio también. Sirve para el micrófono del Mac,
          // cuyo flujo solo acaba cuando acaba la sesión — el del teléfono se cierra
          // **sin** terminar su flujo, y para eso está la escucha de pausas de abajo.
          onDone: () => session?.endAudio(),
          onError: (Object error) =>
              controller.add(VoiceSessionFailed('$error')),
        );

        // **El aviso que de verdad hacía falta.**
        //
        // El detector de turno es automático y mira el audio: espera ver silencio para
        // decidir que terminaste de hablar. Un micrófono abierto se lo da solo —las
        // pausas entre palabras viajan— pero el del teléfono **se cierra de golpe**, y
        // el servicio se quedaba esperando un silencio que ya no llegaba: sesiones
        // enteras muriendo por inactividad con cero turnos.
        //
        // Estuvo colgado del `onDone` de arriba y **estaba mal**: cerrar el micrófono
        // del teléfono no termina su flujo a propósito —tiene que seguir vivo para que
        // la sesión conteste, y para que volver a abrirlo caiga en la misma sesión— así
        // que el aviso no se mandaba nunca. «No entra más audio por ahora» y «esta
        // entrada se acabó» son dos cosas, y confundirlas costó una tarde sin respuesta.
        pausaSubscription = _voiceInput.pausas.listen((_) {
          _log('voz · el audio se cortó: que el servicio cierre el turno');
          session?.endAudio();
        });
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

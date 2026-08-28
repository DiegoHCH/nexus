import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// Convierte lo que pasa en la app en eventos numerados para el teléfono.
///
/// **Se hace de diferencias de estado, no de deltas acumulados**, y esa es la
/// decisión que sostiene la pieza. El escritorio ya tiene un flujo de deltas y era
/// lo obvio de reenviar, pero un flujo acumulado tiene una propiedad mala: si se
/// pierde uno, el teléfono queda mal **para siempre** y nada lo delata. Con
/// diferencias, cada envío se calcula contra lo último que se mandó de verdad, así
/// que un hueco se cierra solo en el siguiente.
///
/// Y encima es lo que hace que agrupar sea trivial: agrupar deltas obliga a
/// concatenarlos a mano y a decidir qué hacer con los que se contradicen; agrupar
/// diferencias es mirar el estado al final de la ventana y restar.
///
/// No sabe qué es un socket ni qué es Riverpod: recibe vistas y publica eventos.
class EventBridge {
  EventBridge({
    required this.log,
    required this.publicar,
    this.ventana = const Duration(milliseconds: 100),
    void Function(Duration, void Function())? programar,
  }) : _programar = programar ?? ((d, f) => Timer(d, f));

  /// Quien numera. El `seq` lo pone el registro y no esto: dos conversaciones
  /// cambiando a la vez con contadores propios compartirían número, y el resync se
  /// saltaría uno para siempre.
  final EventLog log;

  /// Dónde van los eventos ya numerados. Normalmente, a todos los conectados.
  final void Function(Event) publicar;

  /// Lo que dice la decisión 4.5 del contrato: ~100 ms.
  ///
  /// El escritorio pinta cada fragmento porque le sale gratis —es memoria
  /// compartida—; por red no. En móvil con mala señal, un evento por fragmento es
  /// inusable, y la batería lo nota.
  final Duration ventana;

  /// Inyectable porque **la agrupación es tiempo**, y probarla con temporizadores de
  /// verdad significaría dormir en cada prueba y aceptar que fallen de vez en cuando.
  final void Function(Duration, void Function()) _programar;

  /// Lo último que llegó de cada conversación, esperando a que cierre su ventana.
  final _pendiente = <String, ConversationView>{};

  /// Lo último que se **mandó** de cada una. Contra esto se resta.
  final _enviado = <String, ConversationView>{};

  final _armado = <String>{};
  var _cerrado = false;

  /// Cuántas ventanas hay abiertas ahora mismo. Para las pruebas y para saber que
  /// cerrar no deja nada colgando.
  @visibleForTesting
  int get ventanasAbiertas => _armado.length;

  /// Algo cambió en una conversación.
  ///
  /// Se llama tantas veces como haga falta —cada fragmento de texto, cada paso— y lo
  /// que sale es un evento cada ~100 ms como mucho.
  void observar(ConversationView vista) {
    if (_cerrado) return;
    _pendiente[vista.conversationId] = vista;

    // **Una ventana por conversación, y no una global.**
    //
    // La cuenta empieza cuando cambió *esta*, así que un cambio nunca espera al
    // reloj de otra. Con una global, una conversación quieta que cambia justo
    // después de un vaciado se quedaría los 100 ms enteros esperando.
    if (_armado.add(vista.conversationId)) {
      _programar(ventana, () => _vaciar(vista.conversationId));
    }
  }

  /// La conversación se cerró: se avisa y se olvida.
  ///
  /// Olvidar importa: sin esto, `_enviado` guardaría el estado de conversaciones
  /// muertas mientras la app siga abierta, y el snapshot las seguiría contando.
  void olvidar(String conversationId) {
    _pendiente.remove(conversationId);
    _enviado.remove(conversationId);
    if (_cerrado) return;
    publicar(log.emitir('closed', {'conversation': conversationId}));
  }

  /// Avisa de que el acento del Mac cambió.
  ///
  /// **No es de ninguna conversación**, y de ahí que vaya por su cuenta: es del Mac
  /// entero. Existe porque el acento se leía solo en el saludo, así que cambiarlo con
  /// el teléfono ya conectado no llegaba hasta la siguiente reconexión — y lo que se
  /// prometió es que se hereda sin volver a emparejar, no que haya que reconectar.
  ///
  /// Va por el mismo registro numerado que lo demás para que un teléfono que se
  /// reincorpora lo reciba en su resync sin un camino aparte.
  void acento(int argb) {
    if (_cerrado) return;
    publicar(log.emitir('accent', {'argb': argb}));
  }

  /// «Tira lo que te quede por sonar.»
  ///
  /// **No lleva conversación**, igual que el acento: la respuesta que suena es una sola
  /// —solo la del foco abre sesión de voz— y meterle un identificador daría a entender
  /// que puede haber varias sonando a la vez.
  ///
  /// Va por el registro numerado y no como audio porque es una **orden y no un caudal**:
  /// el audio no se numera ni se guarda a propósito, y esto tiene que llegar en orden
  /// respecto a los trozos que lo rodean.
  void descartarLoQueSuena() {
    if (_cerrado) return;
    publicar(log.emitir('playback', {'action': 'discard'}));
  }

  /// El estado entero, para quien pide desde un `seq` que ya se tiró.
  ///
  /// Sale de lo mismo que se fue mandando, así que no hay una segunda forma de
  /// contar lo que pasa —que es donde aparecen las diferencias entre el snapshot y
  /// los eventos, y las diferencias ahí se ven como una pantalla que se queda a
  /// medias sin motivo.
  Snapshot snapshot() => Snapshot(
    seq: log.lastSeq,
    data: {
      'conversations': [for (final v in _enviado.values) v.toJson()],
    },
  );

  /// Cierra las ventanas abiertas sin mandar nada más.
  void cerrar() {
    _cerrado = true;
    _pendiente.clear();
    _armado.clear();
  }

  void _vaciar(String id) {
    _armado.remove(id);
    if (_cerrado) return;
    final ahora = _pendiente.remove(id);
    if (ahora == null) return;

    final antes = _enviado[id];
    // Se guarda **antes** de publicar: si publicar lanzara, lo siguiente se
    // calcularía contra un estado que el teléfono ya recibió a medias. Perder un
    // evento es recuperable —la próxima diferencia lo arrastra—; mandar dos veces lo
    // mismo con distinto número, no.
    _enviado[id] = ahora;

    for (final evento in _diferencias(antes, ahora)) {
      publicar(evento);
    }
  }

  Iterable<Event> _diferencias(
    ConversationView? antes,
    ConversationView ahora,
  ) {
    final salida = <Event>[];
    final id = ahora.conversationId;

    // ── el texto ────────────────────────────────────────────────────────────
    final viejo = antes?.reply ?? '';
    if (ahora.reply != viejo) {
      // Lo normal es que la respuesta **crezca**, y entonces se manda solo lo nuevo:
      // ahí está el ahorro de todo esto.
      if (ahora.reply.startsWith(viejo)) {
        final nuevo = ahora.reply.substring(viejo.length);
        if (nuevo.isNotEmpty) {
          salida.add(log.emitir('text', {'conversation': id, 'append': nuevo}));
        }
      } else {
        // Y lo que no es crecer es **otra respuesta**: empieza un turno nuevo y el
        // búfer se vació. Sin distinguir este caso, el teléfono pegaría la respuesta
        // nueva al final de la anterior y enseñaría las dos juntas.
        salida.add(
          log.emitir('text', {
            'conversation': id,
            'append': ahora.reply,
            'replace': true,
          }),
        );
      }
    }

    // ── lo que dijo el usuario ──────────────────────────────────────────────
    //
    // Entero y no por trozos, al revés que la respuesta: una pregunta aparece de
    // golpe cuando se termina de transcribir, así que no hay nada que ir sumando. Y
    // solo cuando cambia a algo con contenido: el vacío del arranque no es una
    // pregunta, y mandarlo pintaría un turno en blanco.
    if (ahora.ask.isNotEmpty && ahora.ask != (antes?.ask ?? '')) {
      salida.add(log.emitir('ask', {'conversation': id, 'text': ahora.ask}));
    }

    // ── la sesión de voz ────────────────────────────────────────────────────
    if (antes?.voice != ahora.voice) {
      salida.add(
        log.emitir('voice', {'conversation': id, 'active': ahora.voice}),
      );
    }

    // ── el turno ────────────────────────────────────────────────────────────
    if (antes?.streaming != ahora.streaming) {
      salida.add(
        log.emitir('turn', {'conversation': id, 'streaming': ahora.streaming}),
      );
    }

    // ── el orbe ─────────────────────────────────────────────────────────────
    //
    // Aparte del turno y no dentro: `streaming` y el orbe cambian en momentos
    // distintos —el micro se abre sin que haya nada corriendo— y meterlos en el
    // mismo evento haría que uno arrastrara al otro.
    if (antes?.orb != ahora.orb) {
      salida.add(
        log.emitir('orb', {'conversation': id, 'state': ahora.orb.name}),
      );
    }

    // ── el nombre ───────────────────────────────────────────────────────────
    if (antes?.title != ahora.title) {
      salida.add(
        log.emitir('title', {'conversation': id, 'title': ahora.title}),
      );
    }

    // ── los pasos ───────────────────────────────────────────────────────────
    //
    // La lista entera y no un diff. Son un puñado de pasos, y un diff obligaría al
    // teléfono a saber reordenar y casar por id: eso es lógica que se rompe en la
    // versión vieja del móvil, que es justo la que no se puede arreglar.
    if (!_mismosPasos(antes?.steps, ahora.steps)) {
      salida.add(
        log.emitir('activity', {
          'conversation': id,
          'steps': [for (final p in ahora.steps) p.toJson()],
        }),
      );
    }

    // ── el medidor ──────────────────────────────────────────────────────────
    if (antes?.meter.contextTokens != ahora.meter.contextTokens ||
        antes?.meter.contextWindow != ahora.meter.contextWindow ||
        antes?.meter.model != ahora.meter.model) {
      salida.add(
        log.emitir('meter', {'conversation': id, ...ahora.meter.toJson()}),
      );
    }

    // ── el aviso ────────────────────────────────────────────────────────────
    //
    // **El teléfono también lanza encargos**, así que también le cambian las
    // reglas del repositorio bajo los pies. Sin esto, el delimitado se aplicaba
    // igual pero no había forma de enterarse desde ahí.
    if (antes?.notice != ahora.notice) {
      salida.add(
        log.emitir('notice', {
          'conversation': id,
          // Sin `?`, igual que el error: que se quite también es una noticia.
          'message': ahora.notice,
        }),
      );
    }

    // ── el error ────────────────────────────────────────────────────────────
    if (antes?.error != ahora.error) {
      salida.add(
        log.emitir('error', {
          'conversation': id,
          // Sin `?`: que se quite el error también es una noticia, y con la clave
          // ausente el teléfono no podría distinguir «sigue igual» de «ya está».
          'message': ahora.error,
        }),
      );
    }

    return salida;
  }

  bool _mismosPasos(List<RemoteStep>? antes, List<RemoteStep> ahora) {
    if (antes == null) return ahora.isEmpty;
    if (antes.length != ahora.length) return false;
    for (var i = 0; i < ahora.length; i++) {
      if (antes[i] != ahora[i]) return false;
    }
    return true;
  }
}

/// Lo que el móvil ve de una conversación **ahora mismo**.
///
/// Es una foto y no una lista de cambios, por lo mismo que el puente resta en vez de
/// acumular: una foto no se puede desincronizar de la app.
@immutable
class ConversationView {
  const ConversationView({
    required this.conversationId,
    required this.streaming,
    required this.reply,
    required this.ask,
    required this.voice,
    required this.steps,
    required this.meter,
    required this.orb,
    required this.title,
    this.error,
    this.notice,
  });

  final String conversationId;

  /// **Lo último que dijo el usuario.**
  ///
  /// Viaja porque el teléfono no siempre lo sabe: cuando el encargo se escribe allí,
  /// sí —lo acaba de teclear—, pero **hablando no**. La voz se transcribe en el Mac, y
  /// sin esto el teléfono veía llegar la respuesta a una pregunta que nunca se pintó.
  /// Lo que se veía era una conversación contestando sola.
  ///
  /// Es el gemelo de [reply]: aquel es lo último que dijo Nexus y este lo último que
  /// dijo quien pregunta.
  final String ask;

  /// Si hay algo corriendo.
  final bool streaming;

  /// **Si el Mac tiene la sesión de voz abierta.**
  ///
  /// El teléfono presta su micrófono, pero quien decide cuándo termina es el Mac: la
  /// sesión se cierra sola por inactividad. Sin esta señal, el teléfono se quedaba con
  /// el micrófono abierto mandando trozos a una sesión que ya no existía, y en pantalla
  /// seguía diciendo que estaba escuchando. Se dice y no se deduce del orbe: `sleep`
  /// también sale al terminar un encargo escrito.
  final bool voice;

  /// **El estado del orbe, tal cual lo tiene el Mac.**
  ///
  /// Va por el canal en vez de deducirse en el teléfono, y ese es el punto de la
  /// pieza: el móvil solo sabía si algo estaba corriendo, así que de sus cuatro
  /// estados podía dibujar dos. `escuchando` y `hablando` no se pueden inferir de
  /// `streaming` —el micro abierto no es trabajo corriendo, y la voz saliendo tampoco—
  /// y adivinarlos sería justo la clase de mentira que esta pieza existe para evitar.
  ///
  /// El Mac ya lo calcula para su propia pantalla, así que aquí no se computa nada
  /// nuevo: se reenvía. Con eso el orbe del teléfono **es** el del Mac y no una
  /// imitación que se desincroniza en el primer estado que se añada.
  final NexusOrbState orb;

  /// Con qué se reconoce esta conversación.
  ///
  /// **El primer encargo**, que es el mejor título que nadie ha escrito — es lo que ya
  /// usa el archivo del escritorio—. Y viaja en la vista y no solo en la lista porque
  /// una conversación **nace de un evento**: se abre desde el teléfono, llega por el
  /// puente, y hasta la siguiente lista no tenía ni carpeta ni nombre. Lo que se veía
  /// entonces era su identificador, que no dice nada.
  final String title;

  /// La respuesta en curso, **completa**. El puente ya se encarga de mandar solo lo
  /// que falta; guardarla entera aquí es lo que permite calcularlo.
  final String reply;

  final List<RemoteStep> steps;
  final RemoteMeter meter;
  final String? error;

  /// Algo que conviene saber y que **no es un fallo**: hoy, que los archivos de
  /// reglas del repositorio cambiaron desde el encargo anterior.
  ///
  /// Viaja aparte del error y no reusa su hueco por lo mismo que en el
  /// escritorio: pintarlo en rojo diría que algo se rompió, y lo que pasa es que
  /// algo cambió. Y porque los dos pueden coincidir.
  final String? notice;

  Map<String, Object?> toJson() => {
    'id': conversationId,
    'streaming': streaming,
    'orb': orb.name,
    'title': title,
    'reply': reply,
    'steps': [for (final p in steps) p.toJson()],
    'meter': meter.toJson(),
    'error': ?error,
    'notice': ?notice,
  };
}

/// Un paso de la actividad, en la forma en que viaja.
@immutable
class RemoteStep {
  const RemoteStep({
    required this.id,
    required this.description,
    required this.writes,
    required this.done,
  });

  final String id;
  final String description;

  /// Si ese paso escribe. Viaja porque es lo que el teléfono pinta distinto — y lo
  /// que le permite avisar de que algo está tocando archivos.
  final bool writes;
  final bool done;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': description,
    if (writes) 'writes': true,
    if (done) 'done': true,
  };

  @override
  bool operator ==(Object other) =>
      other is RemoteStep &&
      other.id == id &&
      other.description == description &&
      other.writes == writes &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, description, writes, done);
}

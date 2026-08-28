import 'package:flutter/foundation.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// Lo que el teléfono sabe del Mac, construido aplicando eventos.
///
/// Es el **espejo** del puente de la 4.1: allí se restan estados para producir
/// eventos, aquí se aplican eventos para reconstruir el estado. Los dos lados tienen
/// que estar de acuerdo en qué significa cada clave, y por eso vive en el dominio y
/// se prueba con los mismos nombres que emite el puente — no con los que yo recuerde.
///
/// **No sabe nada del socket ni de Riverpod.** Recibe marcos y devuelve un espejo
/// nuevo: inmutable, así que la pantalla se redibuja comparando.
@immutable
class RemoteMirror {
  const RemoteMirror({this.conversations = const {}, this.order = const []});

  /// Por id. Un mapa y no una lista porque cada evento nombra su conversación, y
  /// buscar en una lista por cada delta de texto es recorrerla miles de veces.
  final Map<String, MirroredConversation> conversations;

  /// En qué orden se enseñan. Aparte del mapa **porque el mapa no lo garantiza**, y
  /// un orden que cambia solo hace saltar las tarjetas en la pantalla.
  final List<String> order;

  List<MirroredConversation> get visibles => [
    for (final id in order) ?conversations[id],
  ];

  bool get vacio => conversations.isEmpty;

  /// Aplica un evento y devuelve el espejo resultante.
  ///
  /// **Un evento de una clase que no se conoce se ignora y no lanza.** Es lo que
  /// permite que el Mac se actualice y añada eventos sin romper este teléfono — la
  /// misma tolerancia hacia adelante que el protocolo tiene en los marcos.
  RemoteMirror aplicar(Event evento) {
    final id = evento.data['conversation'] as String?;
    if (id == null) return this;

    if (evento.kind == 'closed') {
      // Se cierra: fuera del mapa **y del orden**. Dejarla en el orden pintaría un
      // hueco, y dejarla en el mapa la resucitaría al siguiente evento.
      return RemoteMirror(
        conversations: {...conversations}..remove(id),
        order: [...order]..remove(id),
      );
    }

    final antes = conversations[id] ?? MirroredConversation(id: id);
    final despues = switch (evento.kind) {
      'text' => antes.conTexto(
        (evento.data['append'] as String?) ?? '',
        reemplazar: evento.data['replace'] == true,
      ),
      // Entera y no por trozos, al revés que la respuesta: una pregunta aparece de
      // golpe al terminar de transcribirse, así que no hay nada que ir sumando.
      'ask' => antes.copyWith(ask: (evento.data['text'] as String?) ?? ''),
      'voice' => antes.copyWith(voiceOnMac: evento.data['active'] == true),
      'turn' => antes.copyWith(streaming: evento.data['streaming'] == true),
      // El estado del orbe **como lo mandó el Mac**, sin traducir. Un nombre que esta
      // versión no conozca deja el que había: un móvil viejo frente a un Mac nuevo
      // tiene que seguir dibujando algo, no quedarse sin orbe.
      // El nombre que manda el Mac. Llega por evento porque una conversación abierta
      // desde el teléfono nace así: sin esto se quedaba con su identificador hasta la
      // siguiente vez que se pidiera la lista.
      'title' => antes.copyWith(title: evento.data['title'] as String?),
      'orb' => antes.copyWith(
        orb:
            NexusOrbState.values
                .where((e) => e.name == evento.data['state'])
                .firstOrNull ??
            antes.orb,
      ),
      'activity' => antes.copyWith(
        steps: [
          for (final crudo in (evento.data['steps'] as List? ?? const []))
            MirroredStep.fromJson(crudo as Map<String, Object?>),
        ],
      ),
      'meter' => antes.copyWith(
        model: evento.data['model'] as String?,
        contextTokens: evento.data['contextTokens'] as int?,
        percent: evento.data['percent'] as int?,
      ),
      // `error` con la clave presente y nula significa «ya está»: quitarlo es una
      // noticia igual que ponerlo, y sin eso el aviso se queda en la pantalla para
      // siempre.
      'error' => antes.copyWith(
        error: evento.data['message'] as String?,
        borrarError: evento.data['message'] == null,
      ),
      // Mismo trato que el error, y por el mismo motivo: quitarlo es una noticia
      // igual que ponerlo, y sin eso el aviso se queda en la pantalla para
      // siempre.
      'notice' => antes.copyWith(
        notice: evento.data['message'] as String?,
        borrarAviso: evento.data['message'] == null,
      ),
      _ => antes,
    };

    if (identical(antes, despues)) return this;

    return RemoteMirror(
      conversations: {...conversations, id: despues},
      // Una conversación que aparece por un evento se añade al final. Pasa de verdad:
      // se abre una en el Mac mientras el teléfono mira otra.
      order: order.contains(id) ? order : [...order, id],
    );
  }

  /// Rehace el espejo entero desde un snapshot.
  ///
  /// **Reemplaza y no mezcla.** Un snapshot llega justo cuando lo que había puede
  /// estar mal, así que fundirlo con lo anterior conservaría precisamente lo que se
  /// venía a tirar.
  static RemoteMirror desdeSnapshot(Snapshot foto) {
    final crudas = foto.data['conversations'] as List? ?? const [];
    final mapa = <String, MirroredConversation>{};
    final orden = <String>[];
    for (final cruda in crudas) {
      final json = cruda as Map<String, Object?>;
      final conv = MirroredConversation.fromJson(json);
      mapa[conv.id] = conv;
      orden.add(conv.id);
    }
    return RemoteMirror(conversations: mapa, order: orden);
  }

  /// Añade una página de historial.
  ///
  /// **Delante de lo que ya hay**, porque las páginas llegan hacia atrás: la primera
  /// es lo último dicho y cada siguiente es más antigua. Añadirlas al final pondría la
  /// conversación del revés.
  RemoteMirror conHistorial(
    String id,
    List<Map<String, Object?>> pagina, {
    required int? siguiente,
  }) {
    final antes = conversations[id];
    if (antes == null) return this;
    final mensajes = [for (final m in pagina) MirroredMessage.fromJson(m)];
    return RemoteMirror(
      conversations: {
        ...conversations,
        id: antes.copyWith(
          history: [...mensajes, ...antes.history],
          masHistorial: siguiente,
          finDelHistorial: siguiente == null,
        ),
      },
      order: order,
    );
  }

  /// La lista de conversaciones que devuelve el método `conversations`.
  ///
  /// Se mezcla con lo que ya hay en vez de reemplazarlo: esa respuesta trae **quién
  /// existe y su carpeta**, no lo que se está escribiendo. Reemplazar borraría la
  /// respuesta a medias de una conversación por haber refrescado la lista.
  RemoteMirror conLista(List<Map<String, Object?>> lista) {
    final mapa = {...conversations};
    final orden = <String>[];
    for (final cruda in lista) {
      final id = cruda['id'] as String?;
      if (id == null) continue;
      orden.add(id);
      final antes = mapa[id] ?? MirroredConversation(id: id);
      mapa[id] = antes.copyWith(
        folder: cruda['folder'] as String?,
        focused: cruda['focused'] == true,
      );
    }
    // Las que ya no están en la lista se van: la lista es la autoridad sobre quién
    // existe.
    mapa.removeWhere((id, _) => !orden.contains(id));
    return RemoteMirror(conversations: mapa, order: orden);
  }
}

@immutable
class MirroredConversation {
  const MirroredConversation({
    required this.id,
    this.folder,
    this.focused = false,
    this.streaming = false,
    this.orb = NexusOrbState.sleep,
    this.title,
    this.reply = '',
    this.ask = '',
    this.voiceOnMac = false,
    this.steps = const [],
    this.model,
    this.contextTokens,
    this.percent,
    this.error,
    this.notice,
    this.history = const [],
    this.masHistorial,
  });

  factory MirroredConversation.fromJson(Map<String, Object?> j) {
    final medidor = (j['meter'] as Map<String, Object?>?) ?? const {};
    return MirroredConversation(
      id: j['id']! as String,
      folder: j['folder'] as String?,
      streaming: j['streaming'] == true,
      title: j['title'] as String?,
      orb:
          NexusOrbState.values.where((e) => e.name == j['orb']).firstOrNull ??
          NexusOrbState.sleep,
      reply: (j['reply'] as String?) ?? '',
      steps: [
        for (final p in (j['steps'] as List? ?? const []))
          MirroredStep.fromJson(p as Map<String, Object?>),
      ],
      model: medidor['model'] as String?,
      contextTokens: medidor['contextTokens'] as int?,
      percent: medidor['percent'] as int?,
      error: j['error'] as String?,
      notice: j['notice'] as String?,
      history: [
        for (final m in (j['history'] as List? ?? const []))
          MirroredMessage.fromJson(m as Map<String, Object?>),
      ],
      masHistorial: j['nextCursor'] as int?,
    );
  }

  final String id;

  /// La ruta, que es lo que un humano reconoce. `null` hasta que llegue la lista:
  /// una conversación puede aparecer por un evento antes de saber su carpeta.
  final String? folder;
  final bool focused;
  final bool streaming;

  /// El estado del orbe en el Mac. `sleep` de partida, que es lo que le toca a una
  /// conversación de la que todavía no ha llegado nada.
  final NexusOrbState orb;

  /// El nombre que manda el Mac: el primer encargo, o la cola de la carpeta.
  final String? title;

  /// La respuesta en curso, completa. Se construye pegando lo que llega.
  final String reply;

  /// **Lo último que dijo el usuario**, cuando llegó por el canal.
  ///
  /// Existe porque hablando el teléfono no sabe lo que dijo: la voz se transcribe en
  /// el Mac, y sin esto llegaba la respuesta a una pregunta que nunca se pintó — una
  /// conversación contestando sola. Escribiendo no hace falta, pero tenerlo siempre es
  /// más barato que tener dos caminos según de dónde vino el turno.
  final String ask;

  /// Si el Mac tiene la sesión de voz abierta. El teléfono presta el micrófono, pero
  /// quien decide cuándo termina es el Mac.
  final bool voiceOnMac;
  final List<MirroredStep> steps;

  final String? model;
  final int? contextTokens;

  /// El porcentaje **tal como lo mandó el Mac**, sin recalcular. Es la mitad del
  /// valor de mandarlo resuelto: si aquí se volviera a calcular con una ventana
  /// asumida, se repetiría el error que ya se cometió en el escritorio.
  final int? percent;

  final String? error;

  /// Algo que cambió y conviene saber, que **no es un fallo** — hoy, que las
  /// reglas del repositorio no son las mismas que en el encargo anterior.
  ///
  /// Aparte del error por lo mismo que en el escritorio: en rojo se leería como
  /// que algo se rompió, y los dos pueden coincidir.
  final String? notice;

  /// Lo dicho antes, **del más viejo al más nuevo**.
  ///
  /// Vive aquí y no en el `reply` porque son dos cosas: el `reply` es lo que se está
  /// escribiendo **ahora** y llega por eventos, mientras el historial se **pide** y
  /// viene paginado. Meterlos en el mismo campo obligaría a decidir, en cada delta de
  /// texto, si añade a la respuesta o al pasado.
  final List<MirroredMessage> history;

  /// Por dónde seguir pidiendo, o `null` si ya se llegó al principio.
  final int? masHistorial;

  /// Si la respuesta en curso **ya está** en el historial.
  ///
  /// Existe porque se veía dos veces: el texto llega como respuesta en curso y, al
  /// terminar el turno, otra vez como turno del historial. Se compara por contenido y
  /// no por «si está corriendo»: el historial puede llegar antes de que el turno pare
  /// —una página de historial pedida a mano, por ejemplo— y con la regla del estado se
  /// perdería el texto en pantalla justo mientras se está leyendo.
  /// Si lo que dijo el usuario ya está en el historial.
  ///
  /// El gemelo de [respuestaYaEnHistorial], y por lo mismo: la pregunta llega por
  /// evento en cuanto se transcribe y **también** aterriza en el historial cuando se
  /// pide una página, así que sin esto se vería dos veces seguidas.
  bool get preguntaYaEnHistorial {
    if (ask.isEmpty) return false;
    final ultimoMio = history.where((m) => m.mine).lastOrNull;
    if (ultimoMio == null) return false;
    return ultimoMio.text.trim() == ask.trim();
  }

  bool get respuestaYaEnHistorial {
    if (reply.isEmpty) return false;
    final ultimoDeNexus = history.where((m) => !m.mine).lastOrNull;
    if (ultimoDeNexus == null) return false;
    // `trim` porque el streaming deja un espacio al final que el historial no trae, y
    // un espacio no es una respuesta distinta.
    return ultimoDeNexus.text.trim() == reply.trim();
  }

  /// Lo que se enseña como nombre.
  ///
  /// **El título que manda el Mac primero**: es el primer encargo, y reconocer una
  /// conversación por lo que le pediste funciona mejor que por dónde vive. Luego la
  /// ruta, y el id solo si no ha llegado nada — que es lo que se veía en una
  /// conversación recién abierta desde el teléfono, porque nacía de un evento y los
  /// eventos no llevaban ni carpeta ni nombre.
  String get nombre => title ?? folder ?? id;

  /// Para la caché.
  ///
  /// **Tiene que leerse con [MirroredConversation.fromJson]**, y esa pareja es donde
  /// una caché se rompe en silencio: se guarda con unas claves y se lee con otras, y
  /// el resultado es una pantalla en blanco al abrir sin red — que se achaca a la red.
  /// Hay una prueba de ida y vuelta por eso.
  Map<String, Object?> toJson() => {
    'id': id,
    'folder': ?folder,
    if (focused) 'focused': true,
    if (streaming) 'streaming': true,
    'reply': reply,
    'steps': [for (final p in steps) p.toJson()],
    'meter': {
      'model': ?model,
      'contextTokens': ?contextTokens,
      'percent': ?percent,
    },
    'error': ?error,
    'notice': ?notice,
    // El historial **también va a la caché**: es lo que permite abrir la app sin red
    // y leer lo que se dijo, que es la mitad del sentido de tener caché.
    'history': [for (final m in history) m.toJson()],
    'nextCursor': ?masHistorial,
  };

  MirroredConversation conTexto(String trozo, {required bool reemplazar}) =>
      copyWith(reply: reemplazar ? trozo : reply + trozo);

  MirroredConversation copyWith({
    String? folder,
    bool? focused,
    bool? streaming,
    NexusOrbState? orb,
    String? title,
    String? reply,
    String? ask,
    bool? voiceOnMac,
    List<MirroredStep>? steps,
    String? model,
    int? contextTokens,
    int? percent,
    String? error,
    bool borrarError = false,
    String? notice,
    bool borrarAviso = false,
    List<MirroredMessage>? history,
    int? masHistorial,
    bool finDelHistorial = false,
  }) => MirroredConversation(
    id: id,
    folder: folder ?? this.folder,
    focused: focused ?? this.focused,
    streaming: streaming ?? this.streaming,
    orb: orb ?? this.orb,
    title: title ?? this.title,
    ask: ask ?? this.ask,
    voiceOnMac: voiceOnMac ?? this.voiceOnMac,
    reply: reply ?? this.reply,
    steps: steps ?? this.steps,
    model: model ?? this.model,
    contextTokens: contextTokens ?? this.contextTokens,
    percent: percent ?? this.percent,
    // Un `null` en un `copyWith` no puede distinguirse de «no lo pases», así que
    // borrar necesita decirse aparte. Sin esto, «ya no hay error» sería imposible de
    // expresar y el aviso se quedaría pegado.
    error: borrarError ? null : (error ?? this.error),
    notice: borrarAviso ? null : (notice ?? this.notice),
    history: history ?? this.history,
    // Igual que el error: «ya no hay más» es un `null` que hay que poder decir, y un
    // `null` en un `copyWith` no se distingue de «no lo pases».
    masHistorial: finDelHistorial ? null : (masHistorial ?? this.masHistorial),
  );
}

/// Un mensaje del historial.
@immutable
class MirroredMessage {
  const MirroredMessage({required this.mine, required this.text});

  factory MirroredMessage.fromJson(Map<String, Object?> j) => MirroredMessage(
    mine: j['mine'] == true,
    text: (j['text'] as String?) ?? '',
  );

  final bool mine;
  final String text;

  Map<String, Object?> toJson() => {'mine': mine, 'text': text};
}

@immutable
class MirroredStep {
  const MirroredStep({
    required this.id,
    required this.text,
    this.writes = false,
    this.done = false,
  });

  factory MirroredStep.fromJson(Map<String, Object?> j) => MirroredStep(
    id: (j['id'] as String?) ?? '',
    text: (j['text'] as String?) ?? '',
    writes: j['writes'] == true,
    done: j['done'] == true,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    if (writes) 'writes': true,
    if (done) 'done': true,
  };

  final String id;
  final String text;

  /// Si ese paso escribe. Se pinta distinto porque es la única forma que tiene el
  /// teléfono de avisar de que algo está tocando archivos.
  final bool writes;
  final bool done;
}

import 'package:flutter/foundation.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

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
      'turn' => antes.copyWith(streaming: evento.data['streaming'] == true),
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
    this.reply = '',
    this.steps = const [],
    this.model,
    this.contextTokens,
    this.percent,
    this.error,
    this.history = const [],
    this.masHistorial,
  });

  factory MirroredConversation.fromJson(Map<String, Object?> j) {
    final medidor = (j['meter'] as Map<String, Object?>?) ?? const {};
    return MirroredConversation(
      id: j['id']! as String,
      folder: j['folder'] as String?,
      streaming: j['streaming'] == true,
      reply: (j['reply'] as String?) ?? '',
      steps: [
        for (final p in (j['steps'] as List? ?? const []))
          MirroredStep.fromJson(p as Map<String, Object?>),
      ],
      model: medidor['model'] as String?,
      contextTokens: medidor['contextTokens'] as int?,
      percent: medidor['percent'] as int?,
      error: j['error'] as String?,
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

  /// La respuesta en curso, completa. Se construye pegando lo que llega.
  final String reply;
  final List<MirroredStep> steps;

  final String? model;
  final int? contextTokens;

  /// El porcentaje **tal como lo mandó el Mac**, sin recalcular. Es la mitad del
  /// valor de mandarlo resuelto: si aquí se volviera a calcular con una ventana
  /// asumida, se repetiría el error que ya se cometió en el escritorio.
  final int? percent;

  final String? error;

  /// Lo dicho antes, **del más viejo al más nuevo**.
  ///
  /// Vive aquí y no en el `reply` porque son dos cosas: el `reply` es lo que se está
  /// escribiendo **ahora** y llega por eventos, mientras el historial se **pide** y
  /// viene paginado. Meterlos en el mismo campo obligaría a decidir, en cada delta de
  /// texto, si añade a la respuesta o al pasado.
  final List<MirroredMessage> history;

  /// Por dónde seguir pidiendo, o `null` si ya se llegó al principio.
  final int? masHistorial;

  /// Lo que se enseña como nombre. La ruta si se sabe; el id si todavía no.
  String get nombre => folder ?? id;

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
    String? reply,
    List<MirroredStep>? steps,
    String? model,
    int? contextTokens,
    int? percent,
    String? error,
    bool borrarError = false,
    List<MirroredMessage>? history,
    int? masHistorial,
    bool finDelHistorial = false,
  }) => MirroredConversation(
    id: id,
    folder: folder ?? this.folder,
    focused: focused ?? this.focused,
    streaming: streaming ?? this.streaming,
    reply: reply ?? this.reply,
    steps: steps ?? this.steps,
    model: model ?? this.model,
    contextTokens: contextTokens ?? this.contextTokens,
    percent: percent ?? this.percent,
    // Un `null` en un `copyWith` no puede distinguirse de «no lo pases», así que
    // borrar necesita decirse aparte. Sin esto, «ya no hay error» sería imposible de
    // expresar y el aviso se quedaría pegado.
    error: borrarError ? null : (error ?? this.error),
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

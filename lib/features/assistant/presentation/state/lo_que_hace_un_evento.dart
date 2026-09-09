import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// Los dos textos de la espera, ya elegidos fuera.
///
/// Entran como dato y no se leen aquí porque **traducir no es mapear**: con el
/// proveedor de textos dentro, comprobar qué espera se enseña pediría montar
/// media app. Cuál de los dos se usa sí es una regla, y esa se decide aquí.
typedef TextosDeLaEspera = ({String laPropia, String deOtra});

/// Cómo se piden esos textos: **una función y no los textos**, porque por este
/// mapeo pasan los deltas de Claude —cientos por respuesta— y solo uno de los
/// eventos necesita traducir nada. Se lee cuando hace falta.
typedef LosTextosDeLaEspera = TextosDeLaEspera Function();

/// Lo que un evento de Claude le hace a la conversación.
///
/// **Puro y aparte del controlador**, por lo mismo que [aplicaEvento] en la
/// feature de correr: «puro y aparte del controlador para poder probar la
/// traducción sin lanzar un `flutter run`». Aquí el equivalente es sin lanzar un
/// Claude — y era el paso siguiente que el PR #306 dejó anotado al sacar el
/// archivado y lo que dejó el encargo.
///
/// 🔴 **Lo que se puede romper aquí no falla, hace otra cosa**: el orbe se queda
/// pensando cuando ya contestó, la espera no se cierra al llegar el turno, o el
/// medidor cuenta los tokens del turno anterior. Nada de eso lanza una
/// excepción, y por eso hace falta poder mirarlo.
///
/// **Los tres eventos que no están, no están a propósito**: `ClaudeFailed`,
/// `ClaudeMcpCaido` y `ClaudeRulesChanged` no son mapeo — el fallo hay que
/// traducirlo y clasificarlo, y los dos avisos se dicen **una vez** y para eso
/// hay que recordar qué se dijo antes. Eso es coreografía y se queda en el
/// controlador; aquí devuelven el estado tal cual, igual que hace
/// `aplicaEvento` con `daemon.connected`.
AssistantHudState conElEvento(
  AssistantHudState actual,
  ClaudeEvent evento, {
  required LosTextosDeLaEspera espera,

  /// Si esta conversación es la que se está comprimiendo. Decide **cuál** de las
  /// dos esperas se enseña, y era una condición del controlador: la espera es de
  /// esta conversación o de otra, y decirlo mal es decirle a alguien que espera
  /// por su propio trabajo cuando espera por el de otro.
  required bool comprimiendose,

  /// La pregunta que este texto contesta, cuando no es la de justo arriba.
  String? respondeA,

  /// Si la respuesta que se está escribiendo es el parte del día.
  bool esElParte = false,
}) {
  switch (evento) {
    case ClaudeQueued():
      final textos = espera();
      return actual.copyWith(
        orbState: NexusOrbState.think,
        activity: [
          ...actual.activity,
          ActivityItem(
            id: idDeLaEspera,
            description: comprimiendose ? textos.laPropia : textos.deOtra,
            writes: false,
          ),
        ],
      );

    case ClaudeSessionStarted(:final model):
      // **Le llegó el turno**: la espera se cierra en cuanto arranca, y se
      // cierra igual que cualquier otro paso — por su identificador fijo.
      final sinEspera = _terminado(actual.activity, idDeLaEspera);
      return actual.copyWith(
        activity: sinEspera,
        // Un modelo vacío no pisa el que ya había: el medidor enseñaría un
        // hueco donde antes decía algo.
        meter: model.isEmpty
            ? actual.meter
            : actual.meter.copyWith(model: model),
      );

    case ClaudeTextDelta(:final text):
      return actual.copyWith(
        messages: LosMensajes.alargando(
          actual.messages,
          ChatAuthor.nexus,
          text,
          respondeA: respondeA,
          esElParte: esElParte,
        ),
        orbState: NexusOrbState.speak,
        isStreaming: true,
      );

    case ClaudeToolUsed():
      // La actividad se acumula en el turno y se vacía al empezar el siguiente:
      // la columna se llama «Ahora mismo», no «historial».
      return actual.copyWith(
        orbState: NexusOrbState.think,
        activity: [
          ...actual.activity,
          ActivityItem(
            id: evento.id,
            description: evento.description,
            writes: evento.writes,
            // 🔴 El detalle se estaba tirando aquí: el lector lo traía y la
            // fila no lo recibía, así que un paso no se podía abrir hasta que
            // terminara — y entonces solo enseñaba lo que devolvió, nunca lo
            // que se ejecutó.
            detail: evento.detail,
            parentId: evento.parentId,
          ),
        ],
      );

    case ClaudeToolFinished(:final id, :final output):
      return actual.copyWith(activity: _terminado(actual.activity, id, output));

    case ClaudeTurnCompleted(:final turnTokens, :final contextTokens):
      return actual.copyWith(
        messages: LosMensajes.sellados(actual.messages),
        orbState: NexusOrbState.sleep,
        isStreaming: false,
        meter: actual.meter.copyWith(
          turnTokens: turnTokens,
          contextTokens: contextTokens,
        ),
      );

    case ClaudeFailed() || ClaudeMcpCaido() || ClaudeRulesChanged():
      // Ver la cabecera: estos tres no son mapeo. Se nombran uno a uno y no con
      // un `default` para que **añadir un evento nuevo no compile** hasta que
      // alguien decida de qué lado cae.
      return actual;
  }
}

/// Identificador fijo de la espera: solo puede haber una por turno, y así se
/// cierra sin tener que recordar cuál era.
const idDeLaEspera = 'esperando-turno';

List<ActivityItem> _terminado(
  List<ActivityItem> actividad,
  String id, [
  String? output,
]) => [
  for (final paso in actividad)
    if (paso.id == id) paso.asDone(output: output) else paso,
];

/// Cómo queda la lista de mensajes al decir, alargar o sellar.
///
/// 🔴 **Estaban dentro del controlador y las usa también la voz**, así que estas
/// reglas ya se comparten entre dos caminos que no se parecen en nada más — y
/// dos de ellas se han roto antes: la cita que solo cuaja al **crear** el
/// mensaje y el turno vacío que **no se deja** en la ventana. Fuera se pueden
/// mirar de una en una.
abstract final class LosMensajes {
  /// Un turno nuevo, todavía escribiéndose.
  static List<ChatMessage> diciendo(
    List<ChatMessage> mensajes,
    ChatAuthor autor,
    String texto, {
    bool spoken = false,
    List<String> attachments = const [],
    String? respondeA,
    bool esElParte = false,
  }) => [
    ...mensajes,
    ChatMessage(
      author: autor,
      text: texto,
      spoken: spoken,
      streaming: true,
      attachments: attachments,
      respondeA: respondeA,
      // Solo la respuesta, no lo que se pidió: el botón de enviar va bajo el
      // parte, y lo que se pidió es la instrucción que lo generó.
      esElParte: autor == ChatAuthor.nexus && esElParte,
    ),
  ];

  /// Va completando el último turno de ese autor mientras llega.
  ///
  /// El texto entra a trozos —deltas de Claude, transcripción de Gemini— y
  /// crear un mensaje por trozo llenaría la ventana de fragmentos sueltos.
  ///
  /// 🔴 **La cita solo cuaja al crear**: alargando no se toca, así que las
  /// porciones siguientes no la repiten ni la borran.
  static List<ChatMessage> alargando(
    List<ChatMessage> mensajes,
    ChatAuthor autor,
    String texto, {
    bool spoken = false,
    String? respondeA,
    bool esElParte = false,
  }) {
    final ultimo = mensajes.lastOrNull;
    if (ultimo != null && ultimo.author == autor && ultimo.streaming) {
      return [
        ...mensajes.take(mensajes.length - 1),
        ultimo.copyWith(text: ultimo.text + texto),
      ];
    }
    return diciendo(
      mensajes,
      autor,
      texto,
      spoken: spoken,
      respondeA: respondeA,
      esElParte: esElParte,
    );
  }

  /// Cierra el turno en curso: se le quita el cursor.
  ///
  /// 🔴 **Un turno que no llegó a decir nada no se deja en la ventana**, y esto
  /// pasa de verdad: un encargo que falla antes de la primera palabra dejaría
  /// una burbuja vacía con su cursor puesto para siempre.
  static List<ChatMessage> sellados(List<ChatMessage> mensajes) {
    final ultimo = mensajes.lastOrNull;
    if (ultimo == null || !ultimo.streaming) return mensajes;
    final sinElUltimo = mensajes.take(mensajes.length - 1);
    return [
      ...sinElUltimo,
      if (!ultimo.isEmpty) ultimo.copyWith(streaming: false),
    ];
  }

  /// Deja en el último mensaje de Nexus lo que este encargo produjo.
  ///
  /// **En el mensaje y no solo en la pantalla**, que es donde vivía: el estado
  /// guarda uno y lo pisa el siguiente, así que al subir por la conversación el
  /// segundo encargo borraba de la vista lo que había hecho el primero. Cada
  /// turno se queda con lo suyo.
  static List<ChatMessage> conLoQueDejo(
    List<ChatMessage> mensajes, {
    GitChanges? cambios,
    String? documento,
    List<ActivityItem>? actividad,
  }) {
    final donde = mensajes.lastIndexWhere(
      (mensaje) => mensaje.author == ChatAuthor.nexus,
    );
    if (donde == -1) return mensajes;
    return [
      ...mensajes.take(donde),
      mensajes[donde].copyWith(
        cambios: cambios,
        documento: documento,
        actividad: actividad,
      ),
      ...mensajes.skip(donde + 1),
    ];
  }
}

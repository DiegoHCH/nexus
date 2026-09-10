import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Qué queda permitido en esta conversación al pulsar «Permitir todo».
///
/// 🔴 **Porque el botón prometía algo que el CLI no concede.** Reportado por un
/// compañero, con la pantalla delante: «cada cosa que hace pide permiso, para
/// leer una imagen, para todo». Y en la captura se ve lo peor — dos preguntas
/// seguidas de `Bash` con su «✔ Lo permitiste, y el resto de la sesión» encima,
/// y una tercera pidiendo lo mismo.
///
/// Medido contra el binario 2.1.258. Al conceder un `Bash`, el CLI ofrece tres
/// salidas:
///
/// ```json
/// {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch uno.txt"}],
///  "behavior":"allow","destination":"localSettings"}
/// {"type":"addDirectories","directories":["…"],"destination":"session"}
/// {"type":"setMode","mode":"acceptEdits","destination":"session"}
/// ```
///
/// Y ninguna de las tres hace lo que dice el botón:
///
/// - la primera es **ese comando literal** y además se escribe en tu
///   repositorio, así que se descarta —ver [LoQueSeContestaAlPermiso]—;
/// - `acceptEdits` concede **ediciones de archivo**, no Bash: es el modo que
///   Nexus ya recuerda, y por eso «permitir todo» sobre una escritura sí
///   funciona y sobre un comando no;
/// - y un `Read` fuera de la carpeta no lo cubre ninguna.
///
/// Así que el resto lo pone Nexus, que es quien hizo la promesa: **la
/// herramienta queda permitida en esta conversación** y las siguientes
/// peticiones suyas se contestan aquí, sin volver a preguntar.
///
/// **Por conversación y no por carpeta**, y no es lo cómodo: es lo que se
/// pulsó. Una conversación es un rato de trabajo con alguien delante; que un
/// «sí» de esta tarde valga mañana, en otra pestaña, es más de lo que dice el
/// botón — y para eso está la lista de comandos permitidos de la carpeta, que
/// se escribe a sabiendas y se ve.
abstract final class LoQueQuedaPermitido {
  /// Lo que **no se pregunta** cuando la carpeta dice «puede editar».
  ///
  /// 🔴 **Decidido por quien manda, y por el motivo correcto:** «es confuso que
  /// diga puede editar pero ande pidiendo permisos; si tiene el permiso de
  /// puede editar debería dejar lanzar bash sin solicitar permisos». Tenía
  /// razón: el interruptor decía una cosa y la pantalla hacía otra, y ese
  /// desajuste es lo que no se puede sostener — el permiso lo concedes una vez,
  /// donde se ve, y no doce veces en un chat.
  ///
  /// La línea que **sí** se mantiene es la que este repo ya tenía trazada en
  /// `McpPermissions`: «los del usuario suelen ser procesos locales y los
  /// conectores actúan sobre servicios de fuera; el riesgo de conceder de más
  /// está todo en los segundos». O sea:
  ///
  /// - lo que pasa **en tu máquina** —`Bash`, `Write`, `Edit`, `Read`— no
  ///   pregunta: es exactamente lo que concede «puede editar en esta carpeta»;
  /// - lo que **sale** de tu máquina —cualquier herramienta MCP: un correo, un
  ///   mensaje en un canal, un ticket— sigue preguntando, porque eso no lo
  ///   concede una carpeta y no se puede deshacer borrando un archivo.
  ///
  /// Y con la carpeta en solo lectura esto no se llega a mirar: ahí el CLI corre
  /// en `manual` y no hay nada que preguntar.
  static bool sinPreguntar({
    required bool puedeEditar,
    required PeticionDePermiso peticion,
  }) => puedeEditar && !esDeFuera(peticion);

  /// Si la herramienta actúa fuera de esta máquina.
  ///
  /// Por el prefijo del protocolo —`mcp__<servidor>__<herramienta>`— y no por
  /// una lista de servidores: una lista hay que mantenerla, y el día que
  /// alguien conecte un servidor nuevo el prefijo ya está ahí.
  static bool esDeFuera(PeticionDePermiso peticion) =>
      peticion.herramienta.startsWith('mcp__');

  /// La herramienta que queda permitida, o `null` si no queda ninguna.
  ///
  /// Solo con [DecisionDePermiso.concedidoTodo]: un «Permitir» a secas es esta
  /// vez y nada más, que es justo la diferencia entre los dos botones.
  static String? laHerramientaDe(
    DecisionDePermiso decision,
    PeticionDePermiso? peticion,
  ) {
    if (decision != DecisionDePermiso.concedidoTodo) return null;
    final herramienta = peticion?.herramienta;
    if (herramienta == null || herramienta.isEmpty) return null;
    return herramienta;
  }

  /// Si esta petición ya está contestada de antes.
  ///
  /// Se mira **por herramienta y no por argumentos**: la queja era «pide
  /// permiso para cada cosa», y responder solo al comando idéntico deja la
  /// queja igual — es lo que ya hace el `addRules` del CLI.
  static bool yaLoDijiste(PeticionDePermiso peticion, Set<String> permitidas) =>
      permitidas.contains(peticion.herramienta);

  /// Lo que se le contesta al CLI cuando ya estaba permitida.
  ///
  /// **Sin permisos nuevos**: el modo de la sesión no se toca aquí, que es de
  /// quien lo concedió; esto solo desatasca *esta* llamada. Y la entrada va tal
  /// cual llegó, como en cualquier concesión.
  static RespuestaDePermiso laRespuesta(PeticionDePermiso peticion) =>
      PermisoConcedido(peticion.entrada);
}

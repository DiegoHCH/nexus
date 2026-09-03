/// Claude quiere usar una herramienta y pide permiso para hacerlo.
///
/// **Esto solo existe porque hay alguien delante.** Un encargo desatendido —la
/// agenda, la cola de la carpeta— no puede recibir una de estas: no hay quien
/// conteste, y una petición sin respuesta cuelga el turno entero. Por eso el
/// puente solo abre este canal cuando le pasan a quién preguntar.
///
/// Llega por el protocolo de control del CLI, que se activa con
/// `--permission-prompt-tool stdio` y `--input-format stream-json`. El CLI lo
/// llama `can_use_tool`; aquí se traduce a algo que la interfaz pueda enseñar
/// sin saber nada de esa tubería.
class PeticionDePermiso {
  const PeticionDePermiso({
    required this.id,
    required this.herramienta,
    required this.nombreVisible,
    required this.entrada,
    this.descripcion,
    this.toolUseId,
    this.sugerencias = const [],
  });

  /// El `request_id` del CLI. **Es el dato que hay que devolver intacto**: sin
  /// él la respuesta no se empareja con la pregunta y el CLI sigue esperando.
  final String id;

  /// El nombre interno de la herramienta: `Write`, `Bash`, `Edit`.
  final String herramienta;

  /// Cómo llamarla delante de una persona. El CLI manda las dos porque no
  /// siempre coinciden —una herramienta MCP se enseña sin el prefijo—, y para
  /// preguntar sirve esta.
  final String nombreVisible;

  /// Los argumentos con los que la quiere usar, tal cual. Es la mitad que
  /// importa de la pregunta: «¿dejas que escriba?» no se puede contestar sin
  /// saber **qué** archivo y con qué contenido.
  final Map<String, dynamic> entrada;

  /// El resumen de una línea que manda el CLI, cuando lo manda.
  final String? descripcion;

  /// La llamada concreta a la que pertenece el permiso, para poder casarla con
  /// el paso que ya se está enseñando en la columna de actividad.
  final String? toolUseId;

  /// Las salidas que el propio CLI ofrece además de sí o no: hoy, «concede
  /// esto para el resto de la sesión».
  ///
  /// **Sin esto la pantalla es inusable, y está medido.** Preguntar por cada
  /// herramienta suena razonable hasta que se cuenta: un encargo que crea tres
  /// archivos pregunta **tres veces**, y uno que toca quince, quince. Eso es
  /// peor que el `acceptEdits` que había, no mejor.
  ///
  /// Se guardan tal cual llegan —son estructuras del CLI, no nuestras— y
  /// devolverlas es lo que corta la sangría: medido contra el binario, esas
  /// tres escrituras pasaron a **una sola pregunta**, con los tres archivos
  /// escritos igual.
  final List<Map<String, dynamic>> sugerencias;

  /// Si hay una salida de «no me lo vuelvas a preguntar» que ofrecer.
  bool get sePuedeConcederTodo => sugerencias.isNotEmpty;

  /// Si conceder esto toca el disco.
  ///
  /// Se mira por nombre y no por la entrada porque es lo único estable: el CLI
  /// no marca la herramienta como escritora, y adivinarlo por los argumentos
  /// —«tiene `content`, luego escribe»— falla con la primera herramienta MCP.
  /// Ante la duda **se dice que sí escribe**: exagerar el aviso es barato y
  /// quedarse corto es justo el fallo que no se puede permitir.
  bool get escribe => !const {
    'Read',
    'Glob',
    'Grep',
    'WebFetch',
    'WebSearch',
    'TodoWrite',
  }.contains(herramienta);

  /// La línea que resume qué se pide, ya recortada para caber.
  ///
  /// Se prefiere lo que el CLI manda —lo redacta él, sabe de qué habla— y solo
  /// cuando no manda nada se compone con los argumentos.
  String get resumen {
    final propia = descripcion?.trim();
    if (propia != null && propia.isNotEmpty) return propia;

    // El orden no es alfabético: es el de «qué querría leer alguien primero».
    // Un `Bash` se entiende por su comando y un `Write` por su ruta; enseñar
    // `content` de primero sería enseñar el archivo entero y nada de dónde va.
    for (final clave in const ['command', 'file_path', 'path', 'pattern']) {
      final valor = entrada[clave];
      if (valor is String && valor.trim().isNotEmpty) return valor.trim();
    }
    return entrada.keys.join(', ');
  }

  /// Lo que hace falta para volver a enseñar la pregunta mañana.
  ///
  /// **No se guarda entero, y la diferencia importa.** [sugerencias] y
  /// [toolUseId] existen para *contestar* —una devuelve permisos nuevos al CLI,
  /// la otra casa la pregunta con el paso de la columna de actividad— y una
  /// conversación releída del disco ya no puede contestar nada: el proceso que
  /// preguntaba murió con la sesión. Guardarlas sería guardar la promesa de un
  /// botón que no existe.
  Map<String, dynamic> toJson() => {
    'id': id,
    'herramienta': herramienta,
    'nombre': nombreVisible,
    'entrada': entrada,
    if (descripcion != null) 'descripcion': descripcion,
  };

  /// Nulo si no se puede leer, como los pasos: un registro escrito por una
  /// versión anterior no trae esta clave, y perder la pregunta vale menos que
  /// perder el turno entero.
  static PeticionDePermiso? fromJson(Object? crudo) {
    if (crudo is! Map<String, dynamic>) return null;
    final id = crudo['id'];
    final herramienta = crudo['herramienta'];
    if (id is! String || herramienta is! String) return null;
    return PeticionDePermiso(
      id: id,
      herramienta: herramienta,
      // El nombre visible cae al interno si falta: son iguales salvo en las
      // herramientas MCP, así que enseñar `Write` es peor que nada solo en el
      // caso en que ya no tenemos con qué mejorarlo.
      nombreVisible: crudo['nombre'] as String? ?? herramienta,
      entrada: crudo['entrada'] as Map<String, dynamic>? ?? const {},
      descripcion: crudo['descripcion'] as String?,
    );
  }
}

/// Lo que la persona contestó.
sealed class RespuestaDePermiso {
  const RespuestaDePermiso();
}

/// Adelante.
///
/// [entrada] es lo que la herramienta va a recibir de verdad. Se devuelve
/// entera —y no un simple «sí»— porque el protocolo permite corregirla al
/// aprobar; hoy se devuelve tal cual llegó, pero el hueco es del CLI y no
/// nuestro, así que se respeta.
final class PermisoConcedido extends RespuestaDePermiso {
  const PermisoConcedido(this.entrada, {this.permisosNuevos = const []});

  final Map<String, dynamic> entrada;

  /// Lo que además cambia de aquí en adelante. Vacío significa «solo esta
  /// vez»; con las sugerencias de la petición dentro, «y no me lo vuelvas a
  /// preguntar en esta sesión».
  final List<Map<String, dynamic>> permisosNuevos;
}

/// No.
///
/// [motivo] llega al modelo **como el resultado de la herramienta**, marcado
/// como error. O sea que no es un mensaje para el log: es lo que Claude va a
/// leer y sobre lo que va a decidir qué hacer después. Medido contra el CLI:
/// con «El humano dijo que no desde Nexus» la respuesta fue explicar que no
/// creó el archivo y ofrecerse a reintentarlo.
final class PermisoDenegado extends RespuestaDePermiso {
  const PermisoDenegado(this.motivo);

  final String motivo;
}

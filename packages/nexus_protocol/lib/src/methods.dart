/// Lo que el móvil puede pedir. Nada más.
///
/// Es un enum cerrado y no una cadena libre a propósito: en La Oficina el triaje
/// de qué exponer costó 59 handlers, y la lección que se trajo —ficha `lo5`— es que
/// **la superficie se fija cuando es pequeña**, no cuando ya creció. Con un `String`
/// como método, añadir uno es una línea y nadie revisa la lista; con un enum, cada
/// añadido pasa por aquí y por la prueba que compara esto con el documento.
///
/// Lo que se queda en el Mac está en [DeniedOnPurpose], porque una lista de lo que
/// **no** se hace vale tanto como la de lo que sí: sin ella, dentro de un año
/// alguien añade `pairFolder` sin saber que se decidió que no.
enum RemoteMethod {
  /// Mandar un encargo. El que necesita `clientMsgId` y confirmación explícita:
  /// sin eso, un reenvío al reconectar lo corre dos veces.
  sendErrand('mandar un encargo'),

  /// Detenerlo.
  stopErrand('detenerlo'),

  /// Las conversaciones abiertas.
  conversations('las conversaciones'),

  /// El historial de una, **paginado**: el teléfono no puede tragarse una sesión
  /// entera.
  history('su historial'),

  /// El estado del medidor de contexto.
  meter('el estado del medidor'),

  /// Y el permiso vigente — de lectura. Subirlo se confirma en el escritorio.
  permission('el permiso vigente');

  const RemoteMethod(this.enElDocumento);

  /// La frase de `docs/PROTOCOL.md` que autoriza este método.
  ///
  /// Está aquí para que una prueba pueda comprobar que el documento y el código
  /// dicen lo mismo. No es documentación duplicada: es el enlace entre los dos, y
  /// si alguien añade un método sin tocar el documento, la prueba lo dice.
  final String enElDocumento;

  static RemoteMethod? tryParse(String nombre) =>
      RemoteMethod.values.where((m) => m.name == nombre).firstOrNull;
}

/// Lo que **no** se expone, y la razón.
///
/// No es código muerto: es la decisión escrita donde se va a leer. La prueba
/// comprueba que ninguno de estos nombres aparece en [RemoteMethod].
enum DeniedOnPurpose {
  /// Es un selector de archivos local. Por red sería elegir a ciegas cualquier
  /// ruta del disco.
  pairFolder('emparejar carpetas'),

  /// Escribe en disco, y se administra desde el escritorio.
  createSkill('crear skills'),

  /// Se confirma en el escritorio, por la decisión 2.4 del documento.
  raisePermission('subir el permiso');

  const DeniedOnPurpose(this.enElDocumento);

  final String enElDocumento;
}

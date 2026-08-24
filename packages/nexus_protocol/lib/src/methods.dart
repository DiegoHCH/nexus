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

  /// Y el permiso vigente — de lectura.
  permission('el permiso vigente'),

  /// El archivo de conversaciones pasadas, para poder retomar una.
  ///
  /// Salió de usar el teléfono: **si en el Mac no hay ninguna conversación abierta, el
  /// móvil no puede hacer nada**. Eso convierte «mira cómo va lo que dejaste
  /// corriendo» en «solo sirve si te acordaste de dejarlo abierto», que es la mitad de
  /// lo que un mando a distancia tiene que poder.
  archive('el archivo de conversaciones'),

  /// Retomar una del archivo. Es lo mismo que hace `⌘H` en el escritorio.
  resumeConversation('retomar una del archivo'),

  /// Las carpetas que el Mac **ya tiene emparejadas**.
  ///
  /// No es emparejar: la lista la pone el Mac. La diferencia importa porque
  /// [DeniedOnPurpose.pairFolder] sigue fuera, y su motivo —elegir a ciegas cualquier
  /// ruta del disco— aquí no se cumple.
  folders('las carpetas emparejadas'),

  /// Abrir una conversación nueva sobre una de esas carpetas.
  openConversation('abrir una conversación sobre una carpeta ya emparejada'),

  /// Los documentos que Claude produjo.
  ///
  /// De lectura, y son el **resultado** del trabajo: poder mandar un encargo y no
  /// poder ver lo que produjo es medio canal.
  artifacts('los artifacts'),

  /// El contenido de uno.
  artifact('el contenido de un artifact'),

  /// Subirlo a escritura, **con la frase**.
  ///
  /// Estuvo en [DeniedOnPurpose] mientras la confirmación era del escritorio, y
  /// ahí es donde se vio el problema: si confirmar exige estar delante del Mac,
  /// editar en remoto es imposible justo cuando estás fuera. La frase de escritura
  /// —que el Mac verifica y el teléfono no guarda— es lo que permite abrirlo sin
  /// abrir la puerta a quien se lleve el teléfono.
  /// Ponerle nombre a una conversación, o quitárselo.
  ///
  /// **No pide la frase de escritura**, y conviene decir por qué: la frase existe para
  /// tocar los archivos del usuario, y un nombre es estado de Nexus sobre sus propias
  /// fichas. Es el mismo razonamiento que abrir una conversación sobre una carpeta ya
  /// emparejada — elegir entre lo que el Mac ya tiene no es lo que la frase protege.
  renameConversation('ponerle nombre a una conversación'),

  /// Cerrar una conversación.
  ///
  /// Cierra la ficha, no borra nada: lo dicho sigue en el archivo, y de ahí se retoma.
  /// Por eso no es destructivo aunque lo parezca — y por eso tampoco pide la frase.
  closeConversation('cerrar una conversación'),

  /// Abrir el micrófono del teléfono hacia el Mac, y cerrarlo.
  ///
  /// Dos métodos y no un interruptor con parámetro: **cerrar tiene que poder llegar
  /// aunque se haya perdido el que abrió**, y con un solo método idempotente eso
  /// obligaba a llevar la cuenta de quién manda. Los dos se reintentan con el mismo
  /// id: abrir dos veces es una sesión abierta, y cerrar lo cerrado es lo mismo.
  ///
  /// No piden la frase de escritura, y por el mismo motivo que abrir una conversación:
  /// hablar no escribe archivos. **Lo que se diga sí pasa por el permiso**, porque
  /// acaba en un encargo, y el encargo ya lo comprueba.
  startVoice('abrir el micrófono del teléfono'),

  /// Cerrarlo.
  stopVoice('cerrar el micrófono del teléfono'),

  unlockWrites('subir el permiso');

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
  pairFolder('emparejar una carpeta nueva'),

  /// Escribe en disco, y se administra desde el escritorio.
  createSkill('crear skills'),

  /// La llave del permiso. Pedirla por el mismo canal que la usa sería regalarla:
  /// quien ya está dentro no puede poder cambiarla.
  setWritePhrase('definir o cambiar la frase de escritura');

  const DeniedOnPurpose(this.enElDocumento);

  final String enElDocumento;
}

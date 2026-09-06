/// La sesión de Claude es **de la carpeta**, y eso se nota sin verse.
///
/// 🔴 **Dos chats sobre el mismo repo no son dos hilos, y lo parecen.** La
/// memoria va por carpeta y cuenta —es la regla del producto y está escrita como
/// tal—, así que cualquier conversación sobre esa carpeta reanuda la misma
/// sesión: comparten el contexto del modelo, lo pedido, el permiso concedido y
/// el turno. Lo que **no** comparten es lo que se ve: cada chat guarda su propia
/// transcripción. O sea dos historiales encima de una sola memoria, y la
/// interfaz enseñaba solo la mitad que no se comparte.
///
/// Se vio en vivo: el primer mensaje de un chat nuevo avisó «ojo que cambiaste
/// de rama», y ese dato no salía de ese chat — venía de la sesión del anterior.
/// Útil ahí, y confuso cuando son dos tareas distintas del mismo repo.
///
/// **La regla de fondo se queda**: la memoria por carpeta es lo que hace que el
/// trabajo siga donde lo dejó el encargo anterior. Lo que se arregla es la
/// sorpresa, no la continuidad.
abstract final class LaSesionQueSeComparte {
  /// Cuántas conversaciones abiertas hay sobre [carpeta].
  ///
  /// Se cuentan **todas**, también la que pregunta: es el número que se enseña
  /// —«compartida entre 2»— y decir «con 1 más» obligaría a sumar de cabeza
  /// para saber cuántas hay.
  static int cuantasComparten(Iterable<String> carpetas, String carpeta) =>
      carpetas.where((otra) => otra == carpeta).length;

  /// Si al abrir una conversación se está continuando un hilo que no se ve.
  ///
  /// La condición es que la carpeta **ya tenga sesión guardada**: entonces el
  /// primer encargo no empieza de cero aunque la pantalla esté vacía, y eso hay
  /// que decirlo con la salida a mano. Cerrar todos los chats no la suelta
  /// —comprobado en el código— así que la pantalla vacía no significa nada.
  static bool continuaSinVerse(String? sessionId) =>
      sessionId != null && sessionId.isNotEmpty;

  /// Si la sesión se quedó **sin dueño** y toca olvidarla.
  ///
  /// 🔴 **Cerrar no olvida, y eso tiene un motivo bueno que hay que respetar:
  /// el archivo.** Si cerrar tirara la sesión, retomar una conversación
  /// archivada volvería sin memoria — justo lo que fuiste a buscar al
  /// retomarla. Pero cuando no queda **ni un registro** de esa carpeta, ni
  /// abierto ni archivado, no hay nada que continuar: guardarla sería guardar un
  /// hilo sin dueño, y el siguiente chat sobre esa carpeta se acordaría de algo
  /// que ya nadie puede leer.
  ///
  /// **Si el archivo no se pudo leer, no se olvida.** Un fallo de disco no es
  /// una lista vacía, y tirar una sesión por no haber podido mirar es el error
  /// que no se puede deshacer.
  static bool seQuedoSinDueno({
    required bool quedanAbiertas,
    required bool quedanArchivadas,
    required bool seLeyoElArchivo,
  }) => seLeyoElArchivo && !quedanAbiertas && !quedanArchivadas;
}

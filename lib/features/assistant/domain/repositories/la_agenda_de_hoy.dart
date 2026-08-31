/// Consultar la agenda del día desde la conversación.
///
/// 🔴 **Existe para que preguntar «qué reuniones tengo» no vuelva a Claude.** La
/// app ya leyó el calendario para poder avisarte: mandar otro `claude -p` para
/// releer lo mismo cuesta un minuto de espera y tokens de tu suscripción, y
/// devuelve exactamente lo que ya está en memoria.
///
/// Es un puerto y no una llamada directa por lo de siempre: el dominio de la
/// conversación no puede conocer el de la agenda. Devuelve la respuesta ya
/// redactada porque quien la tiene es quien sabe si está vacía, si nunca se
/// leyó o si los avisos están apagados — y esas tres se cuentan distinto.
abstract class LaAgendaDeHoy {
  /// Lo que hay hoy, contado en una frase. `null` cuando esto no se puede
  /// contestar sin salir a preguntar —los avisos apagados, sin carpeta— y
  /// entonces quien pregunta decide si sigue por el camino largo.
  Future<String?> deHoy();
}

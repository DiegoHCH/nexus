/// Las herramientas que Nexus **no sabe enseñar**, así que no se le ofrecen.
///
/// 🔴 **Ofrecer una herramienta que no se pinta es peor que no tenerla.** El CLI
/// la llama, Nexus pide permiso por ella —y se concede, porque desde fuera
/// parece razonable—, y luego no aparece nada en pantalla. El turno se gasta, la
/// pregunta muere y el trabajo sigue **sin la respuesta**.
///
/// Medido en una conversación de verdad: se abrió un `AskUserQuestion` para
/// decidir por dónde resolver un `quoteId` que venía `String` donde se esperaba
/// `int`. El permiso se concedió, y el turno siguiente empezó así:
///
/// > «Quedó sin respuesta el diálogo; te lo dejo en texto por si no te llegó.»
///
/// Nadie contestó esa pregunta y el trabajo siguió sin ella. El modelo acabó
/// escribiéndola como texto, que es lo que **sí** funciona aquí — así que
/// negarla no le quita nada: le quita el camino que no lleva a ninguna parte.
///
/// **Se niega siempre**, escriba la carpeta o no: esto no es un permiso, es que
/// la interfaz no existe. El día que se pinte de verdad —con sus opciones, como
/// se pinta la petición de permiso— esta lista se queda vacía y se borra.
abstract final class LoQueNoSePuedePintar {
  static const herramientas = ['AskUserQuestion'];
}

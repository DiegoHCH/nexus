/// Lanzar una prueba desde la conversación, sin pasar por Claude.
///
/// **El camino corto de la cuña de la demo.** Hablar el suite ya funcionaba
/// antes de esto, pero con tres eslabones: el modelo de voz tenía que elegir la
/// herramienta de Claude, Claude tenía que elegir la del MCP de Maestro, y el
/// MCP tenía que estar vivo —el día que se comprobó, no lo estaba—. Cualquiera
/// de los tres se rompe delante de público, y el tercero ni siquiera es nuestro.
///
/// Por aquí no pasa ninguno: el lanzador es el de Nexus, el mismo del panel.
///
/// **Y no necesita permiso de escritura**, que era la mitad del argumento de esa
/// demo. No porque se lo saltemos: porque no hay nada que saltarse — esto no
/// llama a Claude, así que el modo de permisos no entra en juego.
///
/// Es un puerto y no una llamada directa porque el dominio de la conversación no
/// puede conocer el de las pruebas: recibe «lánzame esto» y devuelve la frase
/// que hay que contar en voz alta.
abstract class CorrerUnaPrueba {
  /// Lanza lo que se pidió y devuelve **lo que se dice en voz alta**: que se
  /// lanzó, cuál de varias se quiso decir, o que no hay ninguna así.
  ///
  /// Nunca lanza excepción y nunca devuelve vacío. Callarse dejaría al modelo
  /// esperando una respuesta que no llega, y la conversación muda para siempre
  /// — es la misma razón por la que una herramienta desconocida también
  /// contesta.
  Future<String> loQuePidieron(String pedido);
}

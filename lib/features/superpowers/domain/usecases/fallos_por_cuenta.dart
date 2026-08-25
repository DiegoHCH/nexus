/// Cómo se cuenta lo que falló cuando se instala en varias cuentas.
///
/// Instalar en tres y fallar en una es **un resultado distinto** de no instalar en
/// ninguna, y las dos cosas caben en un «no se pudo». Este es el sitio donde eso se
/// decide, y no en cada panel: con la regla escrita dos veces, una de ellas acabaría
/// diciendo otra cosa.
abstract final class FallosPorCuenta {
  /// El primero, para las pantallas que solo tienen sitio para un mensaje.
  ///
  /// Se queda con el texto del primero —el CLI dice cosas accionables, como «ya existe
  /// uno con ese nombre»— y **añade cuántas cuentas fallaron** cuando fue más de una.
  /// Sin ese número, «ya existe uno con ese nombre» hace pensar que el problema es de
  /// la cuenta que se está mirando.
  static String? primero(Map<String, String> fallos) {
    if (fallos.isEmpty) return null;
    final primero = fallos.values.first;
    if (fallos.length == 1) return primero;
    return '$primero  (${fallos.length} cuentas)';
  }
}

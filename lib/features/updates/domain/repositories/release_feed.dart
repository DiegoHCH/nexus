/// De dónde se sabe qué versión hay publicada.
///
/// Interfaz propia para poder probar la política de cuándo mirar sin salir a la
/// red: lo que se quiere fijar es **cada cuánto se pregunta**, y una prueba que
/// dependa de GitHub mide otra cosa —y falla el día que GitHub tosa—.
abstract class ReleaseFeed {
  /// La última etiqueta publicada y su enlace, o `null` si no se pudo saber.
  Future<({String tag, String url})?> latest();
}

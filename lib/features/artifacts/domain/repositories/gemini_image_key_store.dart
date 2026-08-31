/// Guarda la llave con la que se generan imágenes, cifrada en la máquina.
///
/// **Aparte de la de voz a propósito, y no por orden.** Son dos llaves de la
/// misma API, pero la de voz vive de la capa gratuita y la de imágenes **no
/// puede**: Gemini 2.5 Flash Image no está en el nivel gratuito, así que su
/// proyecto necesita facturación. Con una sola llave, encender las imágenes
/// empezaría a cobrar también las conversaciones —que hoy salen gratis— sin
/// que nadie lo hubiera pedido.
///
/// Separadas, cada una vive en el proyecto que le conviene.
abstract class GeminiImageKeyStore {
  Future<String?> read();

  Future<void> save(String key);

  Future<void> clear();
}

/// Guarda las llaves con las que se generan imágenes, cifradas en la máquina.
///
/// **Aparte de la de voz a propósito, y no por orden.** Son llaves de la misma
/// API, pero la de voz vive de la capa gratuita y la de imágenes **no puede**:
/// Gemini 2.5 Flash Image no está en el nivel gratuito, así que su proyecto
/// necesita facturación. Con una sola llave, encender las imágenes empezaría a
/// cobrar también las conversaciones —que hoy salen gratis— sin que nadie lo
/// hubiera pedido.
///
/// 🔴 **Y una por cuenta de Claude, no una para todo.** Cada carpeta emparejada
/// dice con qué cuenta trabaja —`work`, `private`—, y el gasto de las imágenes
/// sale de un bolsillo concreto: con una sola llave global, trabajar en una
/// carpeta del trabajo gastaría del saldo personal sin que se viera. Poner la
/// llave solo en `private` es una forma legítima de decir «esto no se usa
/// desde el trabajo», y sin esto no había forma de decirlo.
abstract class GeminiImageKeyStore {
  /// La de esa cuenta. `null` en [perfil] es la cuenta de siempre, la que no
  /// tiene nombre.
  Future<String?> read(String? perfil);

  Future<void> save(String? perfil, String key);

  Future<void> clear(String? perfil);
}

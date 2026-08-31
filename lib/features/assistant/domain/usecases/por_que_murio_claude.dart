/// Traduce la muerte del proceso a algo que se pueda hacer.
///
/// **Existe porque el peor fallo de la app no decía nada.** La sesión de una
/// cuenta caduca —pasa sola, sin tocar nada— y en pantalla salía «claude
/// terminó con código 1». El CLI sí lo cuenta, con estas palabras:
///
///     Failed to authenticate: OAuth session expired and could not be refreshed
///
/// Y ese mensaje llegaba hasta aquí. Lo que faltaba era reconocerlo y decir en
/// su lugar qué cuenta hay que reabrir, que es lo único accionable: quien lo
/// lee no sabe que sus carpetas usan cuentas distintas, así que «entra otra
/// vez» sin decir dónde tampoco resolvería nada.
///
/// No se puede prevenir mirando antes: `claude auth status` contesta
/// `"loggedIn": true` en la cuenta caducada —comprobado— porque solo mira si
/// hay credencial guardada, no si sigue sirviendo. La caducidad se descubre al
/// chocar con ella, y por eso el trabajo está aquí y no en un chequeo previo.
abstract final class PorQueMurioClaude {
  /// Lo que dice el CLI cuando la sesión de la cuenta ya no vale.
  ///
  /// Se buscan **dos señales y no la frase entera**: el texto exacto es suyo y
  /// cambia entre versiones, y quedarse sin reconocerlo devolvería el «código
  /// 1» pelado de antes. Con la autenticación y la caducidad juntas no hay
  /// falso positivo razonable —un fallo de red no habla de expiración, y una
  /// llave inválida no habla de caducar— y sobrevive a que le cambien la
  /// redacción alrededor.
  ///
  /// **Por la raíz y no por la palabra**: se escribió `authenticate` y lo cazó
  /// la prueba con «Authentication failed» —que no la contiene—. Media familia
  /// de la palabra se quedaba fuera por tres letras.
  static bool esSesionCaducada(String salida) {
    final texto = salida.toLowerCase();
    return texto.contains('authenticat') &&
        (texto.contains('expired') || texto.contains('log in again'));
  }
}

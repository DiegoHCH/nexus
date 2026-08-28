/// Lo que se le añade a un documento antes de pintarlo dentro de la app.
///
/// El HTML lo escribe Claude, y lo que Claude escribe puede venir influido por
/// lo que leyó en un repositorio. Pintarlo tal cual en un visor con la red
/// abierta convierte un documento en un canal de salida: basta un `fetch` a un
/// dominio cualquiera, o una imagen con la información en la URL.
///
/// En el Mac esto lo resuelve el motor por fuera —lista de bloqueo de WebKit—,
/// que es mejor porque no toca el archivo del usuario. En el teléfono no hay
/// archivo: el HTML llega por el canal **como texto**, así que se le puede poner
/// la muralla dentro sin tocar nada de nadie.
abstract final class HtmlDelVisor {
  /// `default-src 'none'` y se abre solo lo que un documento necesita de verdad
  /// para verse: sus estilos en línea y las imágenes que trae incrustadas.
  ///
  /// Lo que queda fuera es todo lo que sale de la máquina —`connect-src`,
  /// `script-src`, las imágenes por URL— y también `form-action` y `base-uri`,
  /// que son las dos formas de mandar datos fuera sin JavaScript que se suelen
  /// olvidar.
  static const csp =
      "default-src 'none'; "
      "img-src data: blob:; "
      "style-src 'unsafe-inline'; "
      "font-src data:; "
      "media-src data: blob:; "
      "base-uri 'none'; "
      "form-action 'none'";

  static const _meta =
      '<meta http-equiv="Content-Security-Policy" content="$csp">';

  /// El documento con la muralla puesta.
  ///
  /// La etiqueta entra lo antes posible dentro de la cabecera, porque una
  /// `Content-Security-Policy` solo gobierna lo que se parsea **después** de
  /// ella: ponerla al final sería ponerla de adorno.
  static String encerrado(String html) {
    final cabecera = RegExp(
      r'<head[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (cabecera != null) {
      return html.replaceRange(cabecera.end, cabecera.end, '\n$_meta');
    }

    // Sin `<head>` se abre uno. **Detrás del doctype si lo hay**: colar algo
    // delante lo invalida, y un documento sin doctype se pinta en modo quirks —
    // que es un mockup que de repente se ve mal por una medida de seguridad.
    final doctype = RegExp(
      r'^\s*<!doctype[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    final donde = doctype?.end ?? 0;
    return html.replaceRange(donde, donde, '\n<head>$_meta</head>');
  }
}

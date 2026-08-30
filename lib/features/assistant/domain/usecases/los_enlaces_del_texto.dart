/// Una URL sigue siendo una URL aunque venga entre comillas invertidas.
///
/// **El modelo las escribe así casi siempre** —`` `https://…` ``— y para
/// markdown eso es código: ni se pulsa, ni se resalta al arrastrar, ni avisa de
/// nada al hacerle clic. Desde fuera parece que la app tiene los enlaces rotos,
/// y lo que hay es un enlace que nunca lo fue.
///
/// Se quitan solo las comillas, no se inventa un enlace: lo que queda es la URL
/// suelta, y de ahí en adelante trabaja el autoenlace de markdown, que ya venía
/// activado. Así el estilo, el subrayado y el toque salen del mismo sitio que
/// los enlaces escritos bien.
abstract final class LosEnlacesDelTexto {
  /// Quita las comillas invertidas que envuelven **una URL y nada más**.
  ///
  /// Si dentro hay algo además de la URL no se toca: `` `curl -o x https://…` ``
  /// es un comando, y convertirlo en enlace rompería lo que se quería enseñar.
  static String sinComillas(String markdown) {
    final trozos = markdown.split('```');
    return [
      for (var i = 0; i < trozos.length; i++)
        // Los pares son texto normal; los impares, el interior de un bloque de
        // código. **Ahí no se entra**: un bloque se escribe para copiarlo tal
        // cual, y meterle un enlace cambiaría lo que se copia.
        if (i.isEven)
          trozos[i].replaceAllMapped(_urlEntreComillas, _soloLaUrl)
        else
          trozos[i],
    ].join('```');
  }

  /// Una comilla, una URL sin espacios, y la comilla de cierre. Nada más entre
  /// medias: eso es lo que separa una URL citada de un comando citado.
  static final _urlEntreComillas = RegExp(r'`(https?://[^\s`]+)`');

  /// Y con el punto final fuera, si lo había: `` `https://x.com/a.` `` pega el
  /// punto de la frase dentro de la URL, y el enlace se abre roto.
  static String _soloLaUrl(Match match) {
    final url = match.group(1)!;
    final limpia = url.replaceAll(RegExp(r'[.,;:]+$'), '');
    return limpia == url ? url : '$limpia${url.substring(limpia.length)}';
  }
}

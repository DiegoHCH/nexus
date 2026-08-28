/// Cuánto de una respuesta de Claude puede salir hacia el servicio de voz.
///
/// La respuesta de un encargo viaja a Google dentro del `toolResponse` para que
/// el modelo la narre: es el precio de hablar, está dicho en la pantalla de
/// salidas y no se puede evitar mientras sea Gemini quien pone la voz. Lo que sí
/// se puede evitar es que ese precio **no tenga techo**. Iba la respuesta entera,
/// del tamaño que fuera: un encargo que devuelve el contenido de veinte archivos
/// los mandaba enteros.
///
/// El tope no cuesta nada de lo que sirve. A ritmo de habla, 4.000 caracteres
/// son más de cuatro minutos seguidos: **una respuesta más larga que esto no se
/// narra en ningún caso**, se lee en la pantalla —donde sigue estando completa,
/// porque esto solo recorta lo que sale de la máquina, no lo que se ve—. Así que
/// lo que se recorta es exactamente lo que nadie iba a escuchar, y a cambio el
/// peor caso deja de ser «lo que ocupe» y pasa a ser un número.
abstract final class LoQueSaleHaciaLaVoz {
  /// Cuatro mil caracteres de respuesta.
  static const maxCaracteres = 4000;

  /// Hasta dónde se busca hacia atrás un sitio limpio por donde cortar.
  ///
  /// Sin este margen habría que elegir entre cortar a mitad de palabra —que se
  /// narra fatal— o buscar el punto anterior aunque esté a dos mil caracteres,
  /// que tiraría media respuesta útil por estética.
  static const _margenParaCortarBien = 400;

  /// Lo que se le añade al final para que el modelo no narre un trozo como si
  /// fuera todo.
  ///
  /// Va dentro de lo que se manda a propósito: si el aviso no viajara, el modelo
  /// recibiría una respuesta que termina a media frase y **se inventaría el
  /// cierre**, que es peor que decir que hay más.
  static const aviso =
      '\n\n[Corte: esto es solo el principio de la respuesta. El resto está en '
      'la pantalla. Cuenta lo que has recibido, di que hay más en pantalla y no '
      'te inventes el final.]';

  /// `true` si esta respuesta no cabe entera.
  static bool sobra(String respuesta) => respuesta.length > maxCaracteres;

  /// La respuesta tal cual si cabe; si no, su principio y el aviso.
  ///
  /// **El principio y no el final**, porque una respuesta de Claude empieza por
  /// la conclusión y sigue con el detalle: quedarse con el final sería quedarse
  /// con lo que menos se necesita oír.
  static String recortar(String respuesta) {
    if (!sobra(respuesta)) return respuesta;

    final crudo = respuesta.substring(0, maxCaracteres);
    final desde = maxCaracteres - _margenParaCortarBien;

    // Un salto de línea es mejor sitio que un punto: separa ideas enteras y no
    // deja media enumeración colgando.
    var corte = crudo.lastIndexOf('\n');
    if (corte < desde) corte = crudo.lastIndexOf('. ');
    if (corte < desde) corte = crudo.lastIndexOf(' ');
    if (corte < desde) corte = maxCaracteres;

    return '${crudo.substring(0, corte).trimRight()}$aviso';
  }
}

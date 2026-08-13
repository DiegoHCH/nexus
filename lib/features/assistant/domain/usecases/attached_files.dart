/// Cómo llegan los archivos adjuntos a lo que se le pide a Claude.
///
/// Adjuntar aquí es **señalar una ruta**, no subir nada: Claude trabaja en tu
/// disco y abre lo que le indiques, así que copiar el contenido dentro del
/// mensaje lo duplicaría, gastaría contexto y perdería el vínculo con el
/// original — el archivo puede cambiar mientras trabaja.
abstract final class AttachedFiles {
  /// Sin repetidos y conservando el orden en que se añadieron: arrastrar dos
  /// veces el mismo archivo es un accidente corriente, y lo que sale de él no
  /// debería ser pedirle a Claude que lo lea dos veces.
  static List<String> add(List<String> current, Iterable<String> incoming) {
    final result = [...current];
    for (final path in incoming) {
      if (!result.contains(path)) result.add(path);
    }
    return result;
  }

  /// El nombre que se enseña: el último tramo de la ruta.
  static String name(String path) =>
      path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? path;

  /// El encargo con sus adjuntos detrás.
  ///
  /// Cada ruta en su propia línea porque las hay con espacios, y en una lista
  /// separada por comas no habría forma de saber dónde acaba una. [label] llega
  /// de fuera para que la frase esté en el idioma de la interfaz sin que esto
  /// tenga que conocer los textos.
  static String instruction(
    String text,
    List<String> paths, {
    required String label,
  }) {
    if (paths.isEmpty) return text;
    final list = paths.map((path) => '- $path').join('\n');
    // Sin texto, la lista **es** la petición: soltar un archivo y dar a enviar
    // es un gesto legítimo, y quedarse callado ahí sería obligar a escribir
    // «mira esto» para decir lo que el gesto ya dijo.
    final body = text.trim();
    return body.isEmpty ? '$label\n$list' : '$body\n\n$label\n$list';
  }
}

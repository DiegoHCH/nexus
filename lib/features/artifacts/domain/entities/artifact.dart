/// Un documento que ha salido de una conversación: un mockup, un informe, una
/// hoja de cálculo.
class Artifact {
  const Artifact({required this.path, required this.name, required this.at});

  final String path;
  final String name;

  /// Cuándo se escribió por última vez. Ordena la lista, porque lo último que
  /// pediste es lo que vas a querer abrir.
  final DateTime at;

  /// Lo que el visor sabe pintar sin ayuda de nadie: `WKWebView` los abre
  /// todos. Un `.md` no está porque habría que interpretarlo, y un `.zip`
  /// tampoco porque no hay nada que enseñar.
  static const viewable = {
    '.html',
    '.htm',
    '.pdf',
    '.png',
    '.jpg',
    '.jpeg',
    '.svg',
    '.gif',
  };

  static bool isViewable(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return viewable.contains(path.substring(dot).toLowerCase());
  }
}

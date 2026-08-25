import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';

/// ¿Está instalado el binario que un servidor MCP necesita?
///
/// **Existe porque `claude mcp add` no lo comprueba.** Acepta cualquier comando y
/// lo guarda: el servidor no falla al instalarlo, falla la primera vez que
/// alguien lo usa —dentro de un encargo, en headless, donde el síntoma que llega
/// es «no puedo manejar el emulador» y no «falta un binario»—. Es la misma clase
/// de fallo ilegible que costó la tarde de los permisos MCP, y se paga igual de
/// caro: el interruptor parece puesto y no hace nada.
///
/// Los cuatro servidores del catálogo que arrancan con `npx` se instalan solos la
/// primera vez, así que para ellos esto solo confirma que hay Node. `maestro` no:
/// su instalador es aparte y hay que haberlo pasado antes.
abstract final class BinarioEnElPath {
  /// La ruta del binario, o `null` si el PATH dado no lo encuentra.
  ///
  /// **Se resuelve a mano y no lanzando el proceso.** Preguntarle al binario si
  /// existe obliga a elegirle un flag —`--version` no lo entiende todo el mundo—
  /// y a apostar a que ninguno se queda esperando en stdin. Aquí solo se busca un
  /// archivo, que es lo que hace el sistema al arrancarlo.
  ///
  /// [existe] entra como parámetro para poder probar esto sin tocar el disco: lo
  /// que puede romperse al editar aquí es el recorrido del PATH, no `File`.
  static String? resolver(
    String nombre, {
    required String path,
    required bool Function(String ruta) existe,
  }) {
    // Un nombre con barra ya es una ruta: el sistema no la busca en el PATH y
    // esto tampoco debe.
    if (nombre.contains('/')) return existe(nombre) ? nombre : null;

    for (final dir in path.split(':')) {
      if (dir.isEmpty) continue;
      final ruta = '$dir/$nombre';
      if (existe(ruta)) return ruta;
    }
    return null;
  }

  /// Lo mismo contra el PATH real con el que la app lanza procesos.
  ///
  /// Y ese es el punto: no vale preguntarle a la shell del usuario. Una app de
  /// escritorio no lee `.zshrc`, así que lo que encuentra una terminal y lo que
  /// encuentra Nexus son dos listas distintas — y la que importa es esta.
  static bool hay(String nombre) =>
      resolver(
        nombre,
        path: ClaudeEnvironment.forTools()['PATH'] ?? '',
        existe: (ruta) => File(ruta).existsSync(),
      ) !=
      null;
}

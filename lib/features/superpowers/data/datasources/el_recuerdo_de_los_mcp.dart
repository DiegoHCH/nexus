import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';
import 'package:path_provider/path_provider.dart';

/// Lo que el CLI contestó la última vez, guardado.
///
/// 🔴 **Existe porque los conectores de claude.ai no están en ningún archivo
/// del perfil.** Llegan con la sesión, así que la única forma de saber que
/// existen es preguntarle a `claude mcp list` — y eso tarda casi un minuto,
/// porque comprueba la salud de cada servidor uno por uno. Sin recordar la
/// respuesta, la pantalla tenía dos opciones malas: enseñar solo los del
/// archivo —cinco de veinte, que es lo que se reportó— o hacer esperar un
/// minuto cada vez que se abre Ajustes.
///
/// Es una **caché y no una fuente**: lo que manda es el archivo del perfil para
/// los tuyos y el CLI para los de la cuenta. Ver [LaListaDeMcp.junta], donde
/// está escrito qué gana a qué y por qué.
class ElRecuerdoDeLosMcp {
  const ElRecuerdoDeLosMcp({this.carpeta});

  /// Dónde vive. Inyectable para poder probarlo en una carpeta temporal en vez
  /// de escribir en el soporte de la app de verdad — igual que
  /// [RegistroDeLaApp].
  final Directory? carpeta;

  /// Sube cuando cambie lo que se guarda. Un recuerdo de otra versión no se
  /// intenta interpretar: se tira y se vuelve a preguntar, que cuesta un minuto
  /// una vez.
  static const version = 1;

  Future<File> _archivo(String configDir) async {
    final donde = carpeta ?? await getApplicationSupportDirectory();
    final dir = Directory('${donde.path}/mcp');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/${_slug(configDir)}.json');
  }

  /// Un nombre de archivo por perfil. El perfil es una ruta, así que se aplana:
  /// dos cuentas distintas no pueden compartir recuerdo.
  static String _slug(String configDir) => configDir
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  /// Lo recordado, o `null` si no hay nada de qué acordarse.
  ///
  /// No lanza nunca: un recuerdo ilegible es lo mismo que no tenerlo, y romper
  /// Ajustes por una caché sería cambiar un problema pequeño por uno grande.
  Future<({List<McpServer> servidores, DateTime cuando})?> leer(
    String configDir,
  ) async {
    try {
      final file = await _archivo(configDir);
      if (!file.existsSync()) return null;
      final leido = jsonDecode(await file.readAsString());
      if (leido is! Map) return null;
      if (leido['version'] != version) return null;
      final cuando = DateTime.tryParse('${leido['cuando']}');
      if (cuando == null) return null;
      final lista = leido['servidores'];
      if (lista is! List) return null;

      return (
        cuando: cuando,
        servidores: [
          for (final crudo in lista)
            if (crudo is Map)
              McpServer(
                name: '${crudo['nombre']}',
                spec: '${crudo['destino']}',
                status: McpStatus.values.firstWhere(
                  (estado) => estado.name == crudo['estado'],
                  orElse: () => McpStatus.unknown,
                ),
                fromAccount: crudo['deLaCuenta'] == true,
              ),
        ],
      );
    } on Object catch (error) {
      debugPrint('mcp · no se pudo leer lo recordado: $error');
      return null;
    }
  }

  Future<void> guardar(String configDir, List<McpServer> servidores) async {
    try {
      final file = await _archivo(configDir);
      await file.writeAsString(
        jsonEncode({
          'version': version,
          'cuando': DateTime.now().toIso8601String(),
          'servidores': [
            for (final server in servidores)
              {
                'nombre': server.name,
                'destino': server.spec,
                'estado': server.status.name,
                'deLaCuenta': server.fromAccount,
              },
          ],
        }),
      );
    } on Object catch (error) {
      debugPrint('mcp · no se pudo guardar lo recordado: $error');
    }
  }
}

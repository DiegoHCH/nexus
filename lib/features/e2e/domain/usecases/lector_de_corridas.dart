import 'dart:convert';

import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';

/// Leer lo que dejó una corrida de Maestro.
abstract final class LectorDeCorridas {
  /// El estado y las cuentas, sacados de su `commands.json`.
  ///
  /// **Se lee el archivo y no el nombre de la carpeta**, porque la carpeta solo
  /// dice cuándo. El estado está en cada paso: `metadata.status`, que es
  /// `COMPLETED` o no.
  ///
  /// Formato real, comprobado contra las corridas de esta máquina: una lista de
  /// objetos con `command` y `metadata`. El primer paso es siempre un
  /// `defineVariablesCommand` con el entorno de Maestro dentro, y de ahí sale el
  /// dispositivo.
  static ({int pasos, int bien, ComoAcabo como, String? dispositivo}) leer(
    String commandsJson,
  ) {
    final Object? leido;
    try {
      leido = jsonDecode(commandsJson);
    } on FormatException {
      return (
        pasos: 0,
        bien: 0,
        como: ComoAcabo.vayaUstedASaber,
        dispositivo: null,
      );
    }
    if (leido is! List || leido.isEmpty) {
      return (
        pasos: 0,
        bien: 0,
        como: ComoAcabo.vayaUstedASaber,
        dispositivo: null,
      );
    }

    var pasos = 0;
    var bien = 0;
    var alguienFallo = false;
    var alguienCorriendo = false;
    String? dispositivo;

    for (final entrada in leido) {
      if (entrada is! Map) continue;

      // El entorno viaja dentro del primer comando, no en la raíz.
      if (entrada['command'] case final Map orden) {
        if (orden['defineVariablesCommand'] case final Map definicion) {
          if (definicion['env'] case final Map entorno) {
            dispositivo ??= entorno['MAESTRO_DEVICE_UDID'] as String?;
          }
        }
      }

      final estado = switch (entrada['metadata']) {
        final Map metadatos => '${metadatos['status'] ?? ''}',
        _ => '',
      };

      // Los dos primeros pasos son andamiaje de Maestro —definir variables y
      // aplicar configuración— y no son pasos de la prueba. Contarlos haría que
      // «10 pasos» no coincidiera con las diez líneas del `.yaml`.
      final esAndamio =
          entrada['command'] is Map &&
          ((entrada['command'] as Map).containsKey('defineVariablesCommand') ||
              (entrada['command'] as Map).containsKey(
                'applyConfigurationCommand',
              ));
      if (!esAndamio) pasos++;

      switch (estado) {
        case 'COMPLETED':
          if (!esAndamio) bien++;
        case 'FAILED' || 'ERROR':
          alguienFallo = true;
        case 'RUNNING' || 'PENDING':
          alguienCorriendo = true;
      }
    }

    return (
      pasos: pasos,
      bien: bien,
      como: alguienFallo
          ? ComoAcabo.mal
          : alguienCorriendo
          ? ComoAcabo.enMarcha
          : ComoAcabo.bien,
      dispositivo: dispositivo,
    );
  }

  /// La fecha que lleva el nombre de una carpeta de Maestro:
  /// `2026-08-25_163001`.
  ///
  /// Se lee del nombre y no de la fecha del archivo porque copiar o mover la
  /// carpeta cambiaría la segunda, y la primera es la que Maestro puso.
  static DateTime? cuandoDe(String nombreDeCarpeta) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})$',
    ).firstMatch(nombreDeCarpeta);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  /// A qué proyecto pertenece una corrida que **no lanzó Nexus**, por el nombre
  /// de su flow.
  ///
  /// Es una heurística y hay que decirlo: si dos proyectos tienen un `login.yaml`
  /// —y es el nombre más probable del mundo— no hay forma de saber cuál fue.
  /// Coincidencia única se atribuye; varias, se deja sin atribuir con sus
  /// candidatos a la vista, en vez de adivinar. **Fallar del lado visible y no
  /// del cómodo**, que es lo que ya hace `McpPermissions` con los conectores que
  /// no conoce.
  static ({String? proyecto, List<String> candidatos}) atribuyePorNombre(
    String flow,
    Map<String, List<String>> pruebasPorProyecto,
  ) {
    final candidatos = [
      for (final entrada in pruebasPorProyecto.entries)
        if (entrada.value.contains(flow)) entrada.key,
    ];
    return candidatos.length == 1
        ? (proyecto: candidatos.single, candidatos: candidatos)
        : (proyecto: null, candidatos: candidatos);
  }
}

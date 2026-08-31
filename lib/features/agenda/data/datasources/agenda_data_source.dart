import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/agenda/domain/entities/reunion.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/domain/usecases/mcp_permissions.dart';

/// Le pregunta el calendario a Claude, con el conector de Calendar.
///
/// **No hay API propia y no hace falta**: el conector ya funciona desde Nexus y
/// está medido — el mismo `claude -p` con
/// `--allowedTools mcp__claude_ai_Google_Calendar` contesta las reuniones. Lo
/// que hace esto es pedirle la respuesta en JSON en vez de en prosa, porque
/// aquí no la lee una persona.
///
/// 🔴 **Se pregunta una vez y se cachea el día.** Preguntar cada pocos minutos
/// serían casi trescientos `claude -p` diarios, y eso son tokens de tu
/// suscripción para releer la misma agenda. El reloj que dispara los avisos es
/// local; a la cuenta solo se vuelve cuando el día cambia o se pide a mano.
class AgendaDataSource {
  const AgendaDataSource({this.cli = const ClaudeCliDataSource()});

  final ClaudeCliDataSource cli;

  static const conector = 'mcp__claude_ai_Google_Calendar';

  /// Las herramientas del conector que **escriben**, para negarlas.
  ///
  /// 🔴 Se pasan de verdad porque antes solo estaban prometidas en un
  /// comentario: `--allowedTools` autoriza el servidor **entero**, así que sin
  /// esto mover o borrar un evento sí entraba por aquí. Salen de la lista del
  /// canal en vez de repetirse a mano: una segunda copia se queda vieja el día
  /// que el conector estrene una escritura nueva.
  static List<String> get _loQueEscribe => [
    for (final herramienta in McpPermissions.escrituraDeFuera)
      if (herramienta.startsWith('${conector}__')) herramienta,
  ];

  /// La instrucción, escrita para que la conteste una máquina.
  ///
  /// Pide **solo lo que se va a decir** —título, hora, cuántos invitados— y no
  /// la descripción: lo que no se pide no puede acabar sonando por el altavoz
  /// con alguien delante.
  static String instruccionPara(DateTime dia) {
    final fecha = '${dia.year}-${_dos(dia.month)}-${_dos(dia.day)}';
    return 'Dame los eventos de mi calendario de hoy ($fecha) usando el conector '
        'de Google Calendar. Responde ÚNICAMENTE con un array JSON, sin texto '
        'alrededor y sin bloque de código. Cada elemento: {"id": el id del '
        'evento, "titulo": su título, "comienza": la hora de inicio en ISO 8601 '
        'con zona, "invitados": cuántas personas hay invitadas además de mí}. '
        'Si no hay eventos, responde [].';
  }

  Future<List<Reunion>> delDia(
    DateTime dia, {
    required String carpeta,
    String? configDir,
  }) async {
    final buffer = StringBuffer();
    try {
      await for (final evento in cli.run(
        instruccionPara(dia),
        workingDirectory: carpeta,
        // Leer un calendario no toca el disco. Y con el modo restrictivo, la
        // lista de negación del canal deja fuera las herramientas del conector
        // que escriben — mover o borrar un evento no entra por aquí ni por
        // accidente.
        permissionMode: 'manual',
        configDir: configDir,
        herramientasMcp: const [conector],
        disallowedTools: _loQueEscribe,
      )) {
        if (evento['type'] == 'result' && evento['result'] is String) {
          buffer.write(evento['result'] as String);
        }
      }
    } on Object catch (e) {
      // Que falle mirar la agenda no puede tumbar nada: se queda sin avisos
      // hasta la próxima consulta, que es infinitamente mejor que arrastrar el
      // fallo a la app entera por una lectura de fondo que nadie pidió.
      debugPrint('agenda · no se pudo leer el calendario: $e');
      return const [];
    }
    return leer(buffer.toString());
  }

  /// Saca las reuniones de lo que contestó.
  ///
  /// **Tolerante con el envoltorio a propósito.** Se le pide JSON pelado y aun
  /// así a veces llega dentro de un bloque de código o con una frase delante:
  /// negarse por eso dejaría sin avisos un día entero por una coletilla.
  static List<Reunion> leer(String respuesta) {
    final crudo = _elArray(respuesta);
    if (crudo == null) return const [];
    final Object? leido;
    try {
      leido = jsonDecode(crudo);
    } on FormatException {
      return const [];
    }
    if (leido is! List) return const [];
    return [for (final evento in leido) ?Reunion.deJson(evento)];
  }

  /// El primer `[...]` que haya dentro. Sin regex sobre el JSON entero: se
  /// buscan los extremos, que es lo único que hace falta para quitar el
  /// envoltorio.
  static String? _elArray(String texto) {
    final inicio = texto.indexOf('[');
    final fin = texto.lastIndexOf(']');
    if (inicio == -1 || fin <= inicio) return null;
    return texto.substring(inicio, fin + 1);
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}

import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Qué se le devuelve al CLI según lo que se eligió en pantalla.
///
/// Las cuatro salidas no son dos: **conceder y conceder para toda la sesión se
/// diferencian solo en un campo** —las sugerencias que el propio CLI ofreció—, y
/// perderlo convierte «no me lo vuelvas a preguntar» en «vale, solo esta vez».
/// Eso no falla: vuelve a preguntar, y quien lo sufre cree que el botón no hace
/// nada.
///
/// Pero **no todas se devuelven**: una de ellas escribe un permiso en tu
/// repositorio y el botón no promete eso. Ver [loQueDuraLaSesion], donde está la
/// medición.
///
/// Y denegar y cancelar se diferencian solo en el motivo, que **llega al modelo
/// como el resultado de la herramienta**: no es un texto de log, es sobre lo que
/// Claude decide qué hacer después.
abstract final class LoQueSeContestaAlPermiso {
  /// De las salidas que ofrece el CLI, **solo las que duran la sesión**.
  ///
  /// 🔴 **Medido contra el binario, y no era lo que parecía.** Al conceder un
  /// `Bash` el CLI ofrece tres cosas, y una de ellas escribe en tu
  /// repositorio:
  ///
  /// ```json
  /// {"type":"addRules",
  ///  "rules":[{"toolName":"Bash","ruleContent":"mkdir -p uno"}],
  ///  "behavior":"allow","destination":"localSettings"}
  /// ```
  ///
  /// Devolviéndola tal cual —que es lo que se hacía— el CLI escribe
  /// `Bash(mkdir -p uno)` en `<repo>/.claude/settings.local.json`. Comprobado:
  /// el archivo aparece con el permiso dentro. Y es **más** de lo que el botón
  /// promete: dice «y el resto de la sesión», no «y para siempre en este
  /// repositorio, en un archivo que no abriste».
  ///
  /// Peor todavía, **no sirve para lo que se pedía**: `ruleContent` es el
  /// comando literal, así que concede exactamente ese y el siguiente vuelve a
  /// preguntar. Medido en la misma corrida: con solo esa sugerencia devuelta,
  /// `mkdir -p uno` quedó permitido y `mkdir -p dos` preguntó igual. Lo que de
  /// verdad corta la sangría es `setMode`, que es de sesión y que Nexus ya
  /// recuerda —ver `FolderMemory.permissionMode`—.
  ///
  /// Así que el filtro no es una lista de tipos, que envejecería con el CLI: es
  /// **el destino**. Lo que dura la sesión pasa; lo que se escribe en disco, no.
  /// Si quieres que un comando quede permitido siempre, el sitio es la lista de
  /// la carpeta en Ajustes: es nuestra, se ve, y se quita igual de fácil.
  static bool loQueDuraLaSesion(Map<String, dynamic> sugerencia) =>
      sugerencia['destination'] == 'session';

  /// Y para quien mire el registro: qué se dejó fuera.
  static List<String> loQueSeDescarta(List<Map<String, dynamic>> sugerencias) =>
      [
        for (final una in sugerencias)
          if (!loQueDuraLaSesion(una)) '${una['type']} → ${una['destination']}',
      ];

  static RespuestaDePermiso de(
    DecisionDePermiso decision,
    PeticionDePermiso? peticion, {
    required String motivoDenegado,
    required String motivoCancelado,
  }) => switch (decision) {
    DecisionDePermiso.concedido => PermisoConcedido(peticion?.entrada ?? {}),
    DecisionDePermiso.concedidoTodo => PermisoConcedido(
      peticion?.entrada ?? {},
      permisosNuevos: [
        for (final una
            in peticion?.sugerencias ?? const <Map<String, dynamic>>[])
          if (loQueDuraLaSesion(una)) una,
      ],
    ),
    DecisionDePermiso.denegado => PermisoDenegado(motivoDenegado),
    DecisionDePermiso.cancelado => PermisoDenegado(motivoCancelado),
  };
}

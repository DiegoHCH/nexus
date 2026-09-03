import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Qué se le devuelve al CLI según lo que se eligió en pantalla.
///
/// Las cuatro salidas no son dos: **conceder y conceder para toda la sesión se
/// diferencian solo en un campo** —las sugerencias que el propio CLI ofreció—, y
/// perderlo convierte «no me lo vuelvas a preguntar» en «vale, solo esta vez».
/// Eso no falla: vuelve a preguntar, y quien lo sufre cree que el botón no hace
/// nada.
///
/// Y denegar y cancelar se diferencian solo en el motivo, que **llega al modelo
/// como el resultado de la herramienta**: no es un texto de log, es sobre lo que
/// Claude decide qué hacer después.
abstract final class LoQueSeContestaAlPermiso {
  static RespuestaDePermiso de(
    DecisionDePermiso decision,
    PeticionDePermiso? peticion, {
    required String motivoDenegado,
    required String motivoCancelado,
  }) => switch (decision) {
    DecisionDePermiso.concedido => PermisoConcedido(peticion?.entrada ?? {}),
    DecisionDePermiso.concedidoTodo => PermisoConcedido(
      peticion?.entrada ?? {},
      permisosNuevos: peticion?.sugerencias ?? const [],
    ),
    DecisionDePermiso.denegado => PermisoDenegado(motivoDenegado),
    DecisionDePermiso.cancelado => PermisoDenegado(motivoCancelado),
  };
}

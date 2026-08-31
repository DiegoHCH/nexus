import 'package:flutter/foundation.dart';

/// Una cosa del calendario que puede merecer un aviso.
@immutable
class Reunion {
  const Reunion({
    required this.id,
    required this.titulo,
    required this.comienza,
    this.invitados = 0,
  });

  /// El del propio calendario. Es lo que permite no avisar dos veces de lo
  /// mismo cuando el vigilante vuelve a mirar.
  final String id;

  final String titulo;
  final DateTime comienza;

  /// Cuántas personas hay además de ti.
  ///
  /// 🔴 **Es lo que separa una reunión de un bloque tuyo.** Un calendario lleva
  /// «comer», «foco» y cumpleaños, y avisar de todo eso es ruido — y el ruido
  /// enseña a ignorar el aviso, que es peor que no tenerlo.
  final int invitados;

  bool get esUnaReunion => invitados > 0;

  static Reunion? deJson(Object? crudo) {
    if (crudo is! Map<String, dynamic>) return null;
    final id = crudo['id'];
    final titulo = crudo['titulo'];
    final comienza = DateTime.tryParse(crudo['comienza'] as String? ?? '');
    if (id is! String || titulo is! String || comienza == null) return null;
    return Reunion(
      id: id,
      titulo: titulo.trim(),
      comienza: comienza.toLocal(),
      invitados: (crudo['invitados'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Reunion &&
      other.id == id &&
      other.titulo == titulo &&
      other.comienza == comienza &&
      other.invitados == invitados;

  @override
  int get hashCode => Object.hash(id, titulo, comienza, invitados);
}

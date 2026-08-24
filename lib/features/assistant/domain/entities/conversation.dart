import 'package:flutter/foundation.dart';

/// Una conversación viva: una carpeta y el hilo que se lleva con ella.
///
/// Puede haber varias a la vez —hasta [Conversations.max]— y **trabajan en
/// paralelo**: cada una lanza sus propios procesos de Claude. Lo que no se
/// multiplica es la voz: hay una boca y dos oídos, así que el micrófono sirve
/// a la que tenga el foco y las demás avanzan de fondo.
@immutable
class Conversation {
  const Conversation({required this.id, required this.folderPath});

  final String id;
  final String folderPath;

  Map<String, dynamic> toJson() => {'id': id, 'folderPath': folderPath};

  static Conversation? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final folderPath = json['folderPath'] as String?;
    if (id == null || id.isEmpty || folderPath == null || folderPath.isEmpty) {
      return null;
    }
    return Conversation(id: id, folderPath: folderPath);
  }
}

/// Las conversaciones abiertas y cuál tiene el foco.
@immutable
class Conversations {
  const Conversations({this.items = const [], this.focusedId});

  /// El tope no es técnico, es de atención. Estuvo en tres con ese argumento, y el
  /// uso lo corrigió: seis caben porque **no se siguen todas a la vez** — se dejan
  /// corriendo y se vuelve a ellas, que es justo para lo que sirve tener varias.
  ///
  /// Seis y no siete por la rejilla: se apilan en columnas de [porColumna], así que un
  /// número que no sea múltiplo deja una columna coja.
  static const max = 6;

  /// Cuántas fichas caben en una columna del muelle antes de empezar otra al lado.
  ///
  /// Tres es lo que cabe sin que la columna llegue al orbe grande, que es el centro de
  /// la pantalla y no se tapa.
  static const porColumna = 3;

  final List<Conversation> items;
  final String? focusedId;

  bool get isEmpty => items.isEmpty;
  bool get isFull => items.length >= max;

  Conversation? get focused {
    for (final item in items) {
      if (item.id == focusedId) return item;
    }
    return items.isEmpty ? null : items.first;
  }

  /// Una carpeta, una conversación. Dos hilos sobre el mismo repo compartirían
  /// la sesión de Claude y acabarían pisándose el contexto.
  bool hasFolder(String path) => items.any((item) => item.folderPath == path);

  Conversation? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Conversations copyWith({List<Conversation>? items, String? focusedId}) =>
      Conversations(
        items: items ?? this.items,
        focusedId: focusedId ?? this.focusedId,
      );
}

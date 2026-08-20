import 'package:flutter/foundation.dart';

/// Lo que el canal necesita de la app, y **nada más**.
///
/// Es la costura de la fase 4.1, y existe por una razón concreta: cuatro de los
/// seis métodos que el móvil puede pedir viven hoy en el controlador de
/// presentación —`submit`, `stopWork`, el medidor, los mensajes—. Si el canal los
/// leyera directamente pasarían dos cosas malas: la dependencia iría hacia fuera,
/// contra la regla del proyecto, y el protocolo quedaría atado a cómo está montada
/// la pantalla. El día que la pantalla se reorganice, se enteraría el teléfono.
///
/// Así que el canal declara qué necesita y no sabe de dónde sale. Quien lo
/// implementa vive donde sí puede leer providers, y la dependencia apunta hacia
/// dentro.
///
/// **Y habla en tipos propios, no en las entidades del asistente.** `Conversation`
/// ya tiene un `toJson`, y era tentador reutilizarlo — pero ese `toJson` es para
/// persistir, no para el cable. Compartirlos ata el formato que viaja al formato
/// que se guarda: cambiar uno rompería el otro en silencio, y el que se rompería
/// es el que ya está instalado en un teléfono.
abstract class RemoteSurface {
  Future<List<RemoteConversation>> conversations();

  /// Una página del historial. Paginado porque el teléfono no puede tragarse una
  /// sesión entera.
  Future<RemotePage<RemoteMessage>> history(
    String conversationId, {
    int cursor = 0,
    int limit = 50,
  });

  Future<RemoteMeter> meter(String conversationId);

  Future<RemotePermission> permission(String conversationId);

  /// Lanza un encargo. [allowWrites] es un **tope**: si es `false`, el encargo
  /// corre sin permiso de escritura aunque la carpeta lo conceda.
  Future<void> sendErrand(
    String conversationId,
    String text, {
    required bool allowWrites,
  });

  Future<void> stopErrand(String conversationId);
}

/// Se pidió algo de una conversación que no existe.
///
/// Con nombre propio y no un `null`: el teléfono guarda ids y una conversación se
/// puede cerrar en el Mac mientras el móvil la tenía en pantalla. Eso no es un
/// fallo del canal, es una respuesta — «vuelve a pedir la lista».
class UnknownConversation implements Exception {
  const UnknownConversation(this.id);

  final String id;

  @override
  String toString() => 'UnknownConversation($id)';
}

@immutable
class RemoteConversation {
  const RemoteConversation({
    required this.id,
    required this.folder,
    required this.focused,
  });

  /// Lo que el teléfono **manda**. Persiste entre arranques, así que sirve de
  /// nombre estable.
  final String id;

  /// Lo que el teléfono **muestra**: la ruta es lo que un humano reconoce, y un
  /// identificador no dice nada.
  final String folder;

  /// Cuál tiene el foco en el Mac. Importa porque la voz va con esa, así que el
  /// teléfono puede explicar por qué una responde hablando y las otras no.
  final bool focused;

  Map<String, Object?> toJson() => {
    'id': id,
    'folder': folder,
    if (focused) 'focused': true,
  };
}

@immutable
class RemoteMessage {
  const RemoteMessage({required this.mine, required this.text});

  /// De quién es. `mine` desde el punto de vista de quien usa la app, que es el
  /// mismo en el Mac y en el teléfono.
  final bool mine;
  final String text;

  Map<String, Object?> toJson() => {'mine': mine, 'text': text};
}

/// Una página, con por dónde seguir.
@immutable
class RemotePage<T> {
  const RemotePage({required this.items, this.nextCursor});

  final List<T> items;

  /// `null` cuando no queda más. **No un cursor que apunte al final**: un cursor
  /// siempre presente invita a pedir una página más para siempre.
  final int? nextCursor;
}

@immutable
class RemoteMeter {
  const RemoteMeter({this.model, this.contextTokens, this.contextWindow});

  final String? model;
  final int? contextTokens;
  final int? contextWindow;

  /// El porcentaje se manda **calculado**, no se deja al teléfono.
  ///
  /// Y hay una razón medida: el ancho de la ventana depende de la variante del
  /// modelo, y en esta app eso ya se calculó mal una vez —una sesión de un millón
  /// se enseñaba al 88 % porque se asumió 200k—. Que lo calcule el que tiene el
  /// dato evita repetir el error en el otro extremo.
  int? get percent {
    final usado = contextTokens;
    final ventana = contextWindow;
    if (usado == null || ventana == null || ventana <= 0 || usado <= 0) return null;
    return ((usado / ventana) * 100).round().clamp(0, 100);
  }

  Map<String, Object?> toJson() => {
    'model': ?model,
    'contextTokens': ?contextTokens,
    'contextWindow': ?contextWindow,
    'percent': ?percent,
  };
}

@immutable
class RemotePermission {
  const RemotePermission({
    required this.folderCanWrite,
    required this.remoteWriteUntil,
  });

  /// Lo que la carpeta concede en el Mac.
  final bool folderCanWrite;

  /// Hasta cuándo el canal tiene permiso de escritura, si lo tiene.
  final DateTime? remoteWriteUntil;

  /// Lo que de verdad puede hacer el teléfono ahora mismo: el AND de los dos.
  bool canWriteAt(DateTime ahora) =>
      folderCanWrite &&
      remoteWriteUntil != null &&
      ahora.isBefore(remoteWriteUntil!);

  Map<String, Object?> toJson() => {
    'folderCanWrite': folderCanWrite,
    'remoteWriteUntil': ?remoteWriteUntil?.toIso8601String(),
  };
}

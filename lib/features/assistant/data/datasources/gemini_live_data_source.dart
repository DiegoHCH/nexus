import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// El socket contra la Live API de Gemini, y nada más: manda y recibe mapas
/// JSON. No sabe qué significan — eso lo traduce el repositorio.
///
/// Sin paquete de por medio: el `WebSocket` de `dart:io` habla este protocolo
/// tal cual, como se comprobó en `tool/gemini_live_spike.dart`.
class GeminiLiveDataSource {
  const GeminiLiveDataSource();

  /// Confirmado en la doc el 12 ago 2026. Estos *preview* se renombran: si
  /// el `setup` empieza a fallar, sospechar de esto lo primero y volver a
  /// pasar el spike.
  static const model = 'gemini-3.1-flash-live-preview';

  static const _endpoint =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  /// La dirección del socket con la llave dentro.
  ///
  /// **Por `queryParameters`, no interpolada.** Que la llave viaje en la query es
  /// lo que documenta Google, así que ahí sigue; lo que faltaba es escaparla. Una
  /// llave pegada con un espacio o un salto de línea producía una URL rota y un
  /// error de conexión que no se parece en nada a «revisa la llave» — que es lo
  /// que de verdad había pasado.
  ///
  /// Aparte de [open] para poder mirarla: conectar de verdad no se puede probar,
  /// y lo que se rompe aquí es cómo se arma la dirección.
  static Uri urlPara(String apiKey) =>
      Uri.parse(_endpoint).replace(queryParameters: {'key': apiKey.trim()});

  Future<GeminiLiveConnection> open({
    required String apiKey,
    required Map<String, dynamic> setup,
  }) async {
    final socket = await WebSocket.connect(urlPara(apiKey).toString());
    final connection = GeminiLiveConnection._(socket);
    connection.send({'setup': setup});
    return connection;
  }
}

class GeminiLiveConnection {
  GeminiLiveConnection._(this._socket) {
    _subscription = _socket.listen(
      (dynamic frame) {
        final decoded = comoJson(frame);
        if (decoded != null) _messages.add(decoded);
      },
      onError: _messages.addError,
      onDone: _messages.close,
    );
  }

  /// Un marco del socket ya decodificado, o `null` si no se puede leer.
  ///
  /// 🔴 **Esto era un `jsonDecode` a pelo dentro del `onData`, y ahí no hay
  /// red.** Una excepción lanzada dentro del manejador de un `listen` **no
  /// llega al `onError`** de esa misma suscripción: sale a la zona, o sea a
  /// nadie. Un marco cortado se llevaba por delante la entrega y no se
  /// enteraba ni el log.
  ///
  /// Es el mismo fallo que ya tuvo el otro flujo del proyecto y que arregló
  /// [ClaudeCliDataSource.comoJson] —«una línea de texto plano se llevaba por
  /// delante el encargo entero»—; se resuelve igual, y público por el mismo
  /// motivo: la tolerancia se prueba sin abrir un socket.
  ///
  /// **Se descarta en vez de empujar el error al stream**, y es una decisión.
  /// Un `addError` aquí mata la sesión de voz por un marco corrupto, que es
  /// peor que perderlo: la conversación tiene sus propios plazos de
  /// inactividad y se recupera sola. Lo que sí se pierde de verdad es un
  /// `setupComplete` o un `toolCall` roto — por eso se deja dicho en el log y
  /// no en silencio.
  static Map<String, dynamic>? comoJson(dynamic frame) {
    try {
      // La API manda texto, pero un socket puede entregar binario: decodificar
      // los dos casos sale más barato que descubrirlo en producción. Y
      // `utf8.decode` revienta con bytes inválidos, así que entra en el `try`
      // igual que el `jsonDecode`.
      final raw = frame is String ? frame : utf8.decode(frame as List<int>);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      debugPrint('voz · marco descartado: no es un objeto JSON');
      return null;
    } on Object catch (error) {
      debugPrint('voz · marco ilegible, se descarta: $error');
      return null;
    }
  }

  final WebSocket _socket;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  late final StreamSubscription<dynamic> _subscription;

  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Código y motivo con los que el servidor cerró, si ya cerró. Es lo único
  /// que explica un corte del lado de Google — el stream se acaba sin más.
  int? get closeCode => _socket.closeCode;
  String? get closeReason => _socket.closeReason;

  void send(Map<String, dynamic> message) {
    if (_socket.readyState != WebSocket.open) return;
    _socket.add(jsonEncode(message));
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
    await _messages.close();
  }
}

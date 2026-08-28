import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
        // La API manda texto, pero un socket puede entregar binario: decodificar
        // los dos casos sale más barato que descubrirlo en producción.
        final raw = frame is String ? frame : utf8.decode(frame as List<int>);
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) _messages.add(decoded);
      },
      onError: _messages.addError,
      onDone: _messages.close,
    );
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

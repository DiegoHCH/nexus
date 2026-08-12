import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nexus/features/assistant/data/datasources/gemini_live_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';

/// Abre sesiones de voz contra Gemini Live y traduce su JSON a [VoiceEvent].
class GeminiVoiceGateway implements VoiceGateway {
  const GeminiVoiceGateway(this._dataSource, this._readApiKey);

  /// La llave se pide en el momento de conectar, no se guarda aquí: así una
  /// llave cambiada en Ajustes vale desde la siguiente sesión sin reconstruir
  /// nada, y no queda una copia viva en memoria más tiempo del necesario.
  final Future<String?> Function() _readApiKey;
  final GeminiLiveDataSource _dataSource;

  @override
  Future<VoiceSession> connect() async {
    final apiKey = await _readApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('No hay llave de Gemini guardada.');
    }

    final connection = await _dataSource.open(apiKey: apiKey, setup: _setup);
    return _GeminiVoiceSession(connection);
  }

  static Map<String, dynamic> get _setup => {
    'model': 'models/${GeminiLiveDataSource.model}',
    'generationConfig': {
      'responseModalities': ['AUDIO'],
    },
    // Sin esto no hay texto de la conversación, y la franja de subtítulos
    // tendría que transcribir por su cuenta. Con esto llega hecho.
    'inputAudioTranscription': <String, dynamic>{},
    'outputAudioTranscription': <String, dynamic>{},
    'systemInstruction': {
      'parts': [
        {
          'text':
              'Eres Nexus, un asistente de voz que vive en el Mac de quien te habla. '
              'Respondes en español, en frases cortas: esto se escucha, no se lee. '
              'Todavía no puedes tocar archivos ni ejecutar nada — si te piden algo '
              'así, dilo en una frase en vez de inventarte el resultado.',
        },
      ],
    },
  };
}

class _GeminiVoiceSession implements VoiceSession {
  _GeminiVoiceSession(this._connection) {
    _subscription = _connection.messages.listen(
      _translate,
      onError: (Object error) => _events.add(VoiceSessionFailed('$error')),
      onDone: () {
        // Un cierre del lado de Google no llega como error, solo se acaba el
        // stream: sin esto, la interfaz se quedaría esperando para siempre.
        final code = _connection.closeCode;
        if (code != null && code != 1000) {
          _events.add(VoiceSessionFailed('El servicio cerró la sesión ($code ${_connection.closeReason ?? ''})'.trim()));
        }
        _events.close();
      },
    );
  }

  final GeminiLiveConnection _connection;
  final _events = StreamController<VoiceEvent>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  void _translate(Map<String, dynamic> message) {
    if (message.containsKey('setupComplete')) {
      _events.add(const VoiceSessionReady());
      return;
    }

    final server = message['serverContent'] as Map<String, dynamic>?;
    if (server == null) return;

    final userText = (server['inputTranscription'] as Map<String, dynamic>?)?['text'] as String?;
    if (userText != null && userText.isNotEmpty) _events.add(VoiceUserTranscript(userText));

    final replyText = (server['outputTranscription'] as Map<String, dynamic>?)?['text'] as String?;
    if (replyText != null && replyText.isNotEmpty) _events.add(VoiceReplyTranscript(replyText));

    final parts = (server['modelTurn'] as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
    for (final part in parts ?? const []) {
      final inline = (part as Map<String, dynamic>)['inlineData'] as Map<String, dynamic>?;
      final data = inline?['data'] as String?;
      if (data != null) _events.add(VoiceReplyAudio(base64Decode(data)));
    }

    // El orden importa: `interrupted` antes que `turnComplete`, porque quien
    // escuche tiene que tirar la cola antes de dar el turno por cerrado.
    if (server['interrupted'] == true) _events.add(const VoiceInterrupted());
    if (server['turnComplete'] == true) _events.add(const VoiceTurnCompleted());
  }

  @override
  void sendAudio(Uint8List pcm) {
    _connection.send({
      'realtimeInput': {
        'audio': {
          'data': base64Encode(pcm),
          'mimeType': 'audio/pcm;rate=${VoiceSessionFormat.inputSampleRate}',
        },
      },
    });
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _connection.close();
    if (!_events.isClosed) await _events.close();
  }
}

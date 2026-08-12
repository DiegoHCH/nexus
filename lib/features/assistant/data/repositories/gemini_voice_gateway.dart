import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nexus/features/assistant/data/datasources/gemini_live_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';

/// Abre sesiones de voz contra Gemini Live y traduce su JSON a [VoiceEvent].
class GeminiVoiceGateway implements VoiceGateway {
  GeminiVoiceGateway(this._dataSource, this._readApiKey, this._readVoiceName);

  /// La llave se pide en el momento de conectar, no se guarda aquí: así una
  /// llave cambiada en Ajustes vale desde la siguiente sesión sin reconstruir
  /// nada, y no queda una copia viva en memoria más tiempo del necesario.
  final Future<String?> Function() _readApiKey;

  /// Se consulta al conectar, no se guarda: así una voz cambiada en Ajustes
  /// vale desde la siguiente sesión sin reconstruir nada.
  final String Function() _readVoiceName;

  final GeminiLiveDataSource _dataSource;

  /// Lo último que el servicio dio para poder reengancharse. Vive aquí —y no
  /// en el dominio— porque es un detalle de este servicio: el dominio solo
  /// sabe que una conversación se puede continuar.
  String? _resumptionHandle;

  @override
  Future<VoiceSession> connect() {
    // Conversación nueva: se tira el asa vieja, o el modelo arrancaría
    // recordando una charla de hace una hora que el usuario ya cerró.
    _resumptionHandle = null;
    return _open();
  }

  @override
  Future<VoiceSession> resume() {
    if (_resumptionHandle == null) {
      throw StateError('La conversación anterior ya no se puede recuperar.');
    }
    return _open();
  }

  Future<VoiceSession> _open() async {
    final apiKey = await _readApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('No hay llave de Gemini guardada.');
    }

    final connection = await _dataSource.open(
      apiKey: apiKey,
      setup: _buildSetup(),
    );
    return _GeminiVoiceSession(
      connection,
      onResumptionHandle: (handle) => _resumptionHandle = handle,
    );
  }

  Map<String, dynamic> _buildSetup() => {
    ..._setup,
    // `speechConfig` va **dentro de `generationConfig`**, no en la raíz del
    // setup: ahí el servicio corta la conexión con un 1007 «Unknown name
    // speechConfig». Los SDK lo aplanan en su configuración y por eso la doc
    // lo enseña suelto; el protocolo crudo no.
    'generationConfig': {
      ...(_setup['generationConfig']! as Map<String, dynamic>),
      'speechConfig': {
        'voiceConfig': {
          'prebuiltVoiceConfig': {'voiceName': _readVoiceName()},
        },
      },
    },

    // Con el asa a `null` se pide igual: es la forma de decirle al servicio
    // que queremos poder reengancharnos, y él va mandando asas nuevas.
    'sessionResumption': {'handle': _resumptionHandle},
  };

  static Map<String, dynamic> get _setup => {
    'model': 'models/${GeminiLiveDataSource.model}',
    'generationConfig': {
      'responseModalities': ['AUDIO'],
    },
    // Sin esto no hay texto de la conversación, y la franja de subtítulos
    // tendría que transcribir por su cuenta. Con esto llega hecho.
    'inputAudioTranscription': <String, dynamic>{},
    'outputAudioTranscription': <String, dynamic>{},
    // Una sesión de solo audio caduca a los 15 minutos; con la ventana
    // deslizante deja de caducar, a cambio de ir soltando lo más viejo de la
    // conversación. Para hablar es el intercambio correcto: nadie espera que
    // recuerde literalmente lo de hace veinte minutos, y sí que no se muera.
    'contextWindowCompression': {'slidingWindow': <String, dynamic>{}},
    // El detector de voz del servicio, alargado a propósito. Por defecto corta
    // el turno con una pausa muy corta, y una instrucción larga tiene pausas
    // naturales —para pensar, para respirar—: el efecto era que se quedaba con
    // media frase y contestaba a eso. Se paga con algo más de espera antes de
    // que responda, que es el intercambio correcto: mejor esperar medio
    // segundo más que contestar a una pregunta que no terminaste.
    'realtimeInputConfig': {
      'automaticActivityDetection': {
        'endOfSpeechSensitivity': 'END_SENSITIVITY_LOW',
        'silenceDurationMs': 1200,
        // Sin esto se come el principio de la primera palabra.
        'prefixPaddingMs': 300,
      },
    },
    'systemInstruction': {
      'parts': [
        {
          'text':
              'Eres Nexus, un asistente de voz que vive en el Mac de quien te habla. '
              'Respondes en español, en frases cortas: esto se escucha, no se lee.\n'
              'REGLA PRINCIPAL: absolutamente todo lo que te pidan —cualquier '
              'pregunta, consulta, tarea o encargo, sea de código o no— se lo pasas a '
              'Claude llamando a pedir_a_claude, y después cuentas lo que devolvió. '
              'NO respondas de memoria aunque sepas la respuesta: tú pones la voz, '
              'Claude pone el trabajo.\n'
              'Solo contestas tú, sin llamar a nadie, a lo que no es un encargo: '
              'saludos, agradecimientos, "para", "espera", o cuando te pidan repetir '
              'algo que acabas de decir.\n'
              'Antes de llamar a una herramienta di en tres o cuatro palabras qué vas '
              'a hacer, para que no haya un silencio largo mientras se trabaja.\n'
              'SKILLS: si al resolver algo detectas que faltaba conocimiento que se va '
              'a volver a necesitar —un procedimiento del proyecto, una convención, una '
              'tarea que ya se ha repetido— ofrécele crear una skill con crear_skill, '
              'en una frase y sin insistir. Ofrécelo **después** de resolver lo que te '
              'pidieron, nunca en vez de resolverlo, y solo si él acepta.',
        },
      ],
    },
    'tools': [
      {
        'functionDeclarations': [
          {
            'name': toolName,
            'description':
                'Le pasa a Claude Code cualquier encargo: responder una pregunta, '
                'leer o editar archivos, mirar el estado de git, ejecutar comandos. '
                'Es la vía por defecto para todo lo que te pidan, no solo para '
                'tareas de programación. Todavía no hay carpeta emparejada, así que '
                'trabaja sobre el directorio donde corre la app y no sobre un '
                'proyecto concreto.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'instruccion': {
                  'type': 'STRING',
                  'description':
                      'La tarea, en español, tal como se le diría a un programador.',
                },
              },
              'required': ['instruccion'],
            },
          },
          {
            'name': skillToolName,
            'description':
                'Crea una skill nueva para Claude Code: una carpeta con su '
                'SKILL.md dentro del proyecto, que queda disponible para '
                'siempre. Úsala cuando detectes que falta conocimiento que se '
                'va a volver a necesitar —un procedimiento del proyecto, una '
                'convención, una tarea repetitiva— en vez de repetir la '
                'explicación cada vez. Requiere que el interruptor de permisos '
                'esté en «puede editar»: si está en solo lectura, dilo en vez '
                'de intentarlo.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'nombre': {
                  'type': 'STRING',
                  'description':
                      'Identificador corto en minúsculas y con guiones, como nombre de carpeta.',
                },
                'para_que': {
                  'type': 'STRING',
                  'description':
                      'Qué debe saber hacer la skill y cuándo hay que usarla, con detalle.',
                },
              },
              'required': ['nombre', 'para_que'],
            },
          },
        ],
      },
    ],
  };

  /// Los nombres viven aquí y no sueltos en el JSON porque el caso de uso
  /// tiene que reconocerlos cuando el modelo los llama.
  static const toolName = 'pedir_a_claude';
  static const skillToolName = 'crear_skill';
}

class _GeminiVoiceSession implements VoiceSession {
  _GeminiVoiceSession(this._connection, {required this.onResumptionHandle}) {
    _subscription = _connection.messages.listen(
      _translate,
      onError: (Object error) => _events.add(VoiceSessionFailed('$error')),
      onDone: () {
        // Aquí no se juzga: se anota el motivo y se cierra el stream. Google
        // corta la conexión cada pocos minutos —a veces con `goAway` y a
        // veces sin despedirse, con un 1006 seco, comprobado— y llamar a eso
        // un fallo mataría la conversación en vez de reengancharla.
        final code = _connection.closeCode;
        if (code != null && code != 1000) {
          final reason = _connection.closeReason;
          endReason =
              'el servicio cortó la conexión ($code${reason == null || reason.isEmpty ? '' : ' $reason'})';
        }
        _events.close();
      },
    );
  }

  final GeminiLiveConnection _connection;

  /// Se llama con cada asa nueva. El gateway la guarda para reengancharse.
  final void Function(String handle) onResumptionHandle;

  final _events = StreamController<VoiceEvent>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  String? endReason;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  void _translate(Map<String, dynamic> message) {
    if (message.containsKey('setupComplete')) {
      _events.add(const VoiceSessionReady());
      return;
    }

    // El asa se renueva sola durante la conversación; hay que quedarse con la
    // última, no con la primera.
    final resumption =
        message['sessionResumptionUpdate'] as Map<String, dynamic>?;
    if (resumption != null) {
      final handle = resumption['newHandle'] as String?;
      if (resumption['resumable'] == true && handle != null) {
        onResumptionHandle(handle);
      }
      return;
    }

    // Aviso de que esta conexión se acaba. No hace falta hacer nada: el corte
    // se atiende igual cuando llega, con aviso o sin él —a veces no lo hay—,
    // y el reenganche es asunto del caso de uso.
    if (message.containsKey('goAway')) return;

    final toolCall = message['toolCall'] as Map<String, dynamic>?;
    if (toolCall != null) {
      _translateToolCall(toolCall);
      return;
    }

    final server = message['serverContent'] as Map<String, dynamic>?;
    if (server == null) return;

    final userText =
        (server['inputTranscription'] as Map<String, dynamic>?)?['text']
            as String?;
    if (userText != null && userText.isNotEmpty) {
      _events.add(VoiceUserTranscript(userText));
    }

    final replyText =
        (server['outputTranscription'] as Map<String, dynamic>?)?['text']
            as String?;
    if (replyText != null && replyText.isNotEmpty) {
      _events.add(VoiceReplyTranscript(replyText));
    }

    final parts =
        (server['modelTurn'] as Map<String, dynamic>?)?['parts']
            as List<dynamic>?;
    for (final part in parts ?? const []) {
      final inline =
          (part as Map<String, dynamic>)['inlineData'] as Map<String, dynamic>?;
      final data = inline?['data'] as String?;
      if (data != null) _events.add(VoiceReplyAudio(base64Decode(data)));
    }

    // El orden importa: `interrupted` antes que `turnComplete`, porque quien
    // escuche tiene que tirar la cola antes de dar el turno por cerrado.
    if (server['interrupted'] == true) _events.add(const VoiceInterrupted());
    if (server['turnComplete'] == true) _events.add(const VoiceTurnCompleted());
  }

  void _translateToolCall(Map<String, dynamic> toolCall) {
    final calls = toolCall['functionCalls'] as List<dynamic>? ?? const [];
    for (final call in calls) {
      final function = call as Map<String, dynamic>;
      final id = function['id'] as String?;
      final name = function['name'] as String?;
      if (id == null || name == null) continue;

      final args = function['args'] as Map<String, dynamic>? ?? const {};
      _events.add(VoiceToolRequested(callId: id, name: name, arguments: args));
    }
  }

  @override
  void sendToolResult({
    required String callId,
    required String name,
    required String result,
  }) {
    _connection.send({
      'toolResponse': {
        'functionResponses': [
          {
            'id': callId,
            'name': name,
            'response': {'result': result},
          },
        ],
      },
    });
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

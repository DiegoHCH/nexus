// Spike 2.1 — ¿se puede hablar el protocolo Live de Gemini desde Dart?
//
// Se conserva en el repo, y no como script de usar y tirar, porque estos
// modelos *preview* se renombran y la doc se mueve: cuando algo deje de
// funcionar, esto dice en un minuto si el problema es el nombre del modelo, la
// llave, el formato de audio o la costura de la herramienta.
//
//   fvm dart run tool/gemini_live_spike.dart
//
// La llave la lee del llavero el propio proceso —la misma que guarda la
// pantalla de configuración inicial—, para que no pase por la línea de
// comandos ni quede en el historial de ningún shell.
//
// Comprueba tres cosas, en este orden, porque cada una vale por sí sola:
//   1. turno de texto → responde con audio (la sesión existe y el modelo vive)
//   2. turno de voz   → transcribe y contesta (entra audio en el formato del micro)
//   3. `pedir_a_claude` → la llama sola y narra el resultado (la decisión c2)
//
// ignore_for_file: avoid_print — es una herramienta de línea de comandos: la
// salida por consola es su interfaz, no un resto de depuración.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Confirmado en la doc el 12 ago 2026. Si el spike empieza a fallar en el
/// `setup`, sospechar de esto lo primero.
const _model = 'gemini-3.1-flash-live-preview';
const _endpoint =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

/// Formato de entrada que pide la Live API, y el mismo que entrega el micro.
const _inputSampleRate = 16000;

/// El audio de vuelta siempre llega a 24 kHz, lo pidas como lo pidas.
const _outputSampleRate = 24000;

void main() async {
  final key = await _readKeyFromKeychain();
  print('llave leída del llavero: ${key.length} caracteres');

  final session = await _LiveSession.connect(key);
  print('socket abierto · setup enviado (modelo $_model)\n');

  print('--- 1. TURNO DE TEXTO ---');
  session.sendText('Saluda y di en qué puedes ayudar. Una frase.');
  await session.waitForTurn();
  print('dijo  : "${session.takeOutputTranscript()}"');
  print(
    'audio : ${session.audioSeconds.toStringAsFixed(2)} s a $_outputSampleRate Hz\n',
  );

  print('--- 2. TURNO DE VOZ ---');
  await session.sendSpeech('Hola, ¿me escuchas bien?');
  await session.waitForTurn();
  print('oyó   : "${session.takeInputTranscript()}"');
  print('dijo  : "${session.takeOutputTranscript()}"\n');

  print('--- 3. LA COSTURA pedir_a_claude ---');
  await session.sendSpeech(
    'Revisa qué cambios tengo sin commitear en el proyecto.',
  );
  final call = await session.waitForToolCall();
  if (call == null) {
    print('!! no llamó a la herramienta — la decisión c2 habría que revisarla');
  } else {
    print('oyó   : "${session.takeInputTranscript()}"');
    print('llamó : ${call['name']} con ${jsonEncode(call['args'])}');
    session.sendToolResponse(
      call,
      'Hay 4 archivos modificados sin commitear: dos en la capa de voz, uno en '
      'onboarding y el proyecto de Xcode.',
    );
    await session.waitForTurn();
    print('narró : "${session.takeOutputTranscript()}"');
  }

  // A temporales, no al repo: es un residuo de la prueba, no un artefacto.
  final wav = File('${Directory.systemTemp.path}/nexus_gemini_live_spike.wav');
  await wav.writeAsBytes(session.toWav());
  print('\naudio completo en ${wav.absolute.path}  ·  afplay para oírlo');
  await session.close();
  exit(0);
}

/// La sesión Live, con lo justo para que el spike se lea de arriba abajo.
class _LiveSession {
  _LiveSession._(this._socket);

  final WebSocket _socket;
  final _audio = BytesBuilder();
  final _inputTranscript = StringBuffer();
  final _outputTranscript = StringBuffer();
  Completer<void> _turn = Completer<void>();
  Completer<Map<String, dynamic>?> _toolCall =
      Completer<Map<String, dynamic>?>();

  double get audioSeconds => _audio.length / (_outputSampleRate * 2);

  static Future<_LiveSession> connect(String key) async {
    final socket = await WebSocket.connect('$_endpoint?key=$key');
    final session = _LiveSession._(socket);
    socket.listen(session._onMessage, onDone: session._onDone);
    socket.add(
      jsonEncode({
        'setup': {
          'model': 'models/$_model',
          'generationConfig': {
            'responseModalities': ['AUDIO'],
          },
          // Sin esto no hay texto de lo hablado: con esto, la franja de
          // subtítulos no tiene que transcribir nada por su cuenta.
          'inputAudioTranscription': <String, dynamic>{},
          'outputAudioTranscription': <String, dynamic>{},
          'systemInstruction': {
            'parts': [
              {
                'text':
                    'Eres Nexus, un asistente de voz en un Mac. Responde en español y '
                    'breve. Para cualquier cosa sobre código, archivos, git o el estado '
                    'del proyecto NO respondas de memoria: llama a la herramienta '
                    'pedir_a_claude con la instrucción, y luego cuenta el resultado.',
              },
            ],
          },
          'tools': [
            {
              'functionDeclarations': [
                {
                  'name': 'pedir_a_claude',
                  'description':
                      'Le encarga a Claude Code una tarea real sobre el Mac: leer '
                      'o editar archivos, mirar el estado de git, ejecutar comandos.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': {
                      'instruccion': {
                        'type': 'STRING',
                        'description':
                            'La tarea, tal como se le diría a un programador.',
                      },
                    },
                    'required': ['instruccion'],
                  },
                },
              ],
            },
          ],
        },
      }),
    );
    return session;
  }

  void _onMessage(dynamic frame) {
    final raw = frame is String ? frame : utf8.decode(frame as List<int>);
    final message = jsonDecode(raw) as Map<String, dynamic>;

    final server = message['serverContent'] as Map<String, dynamic>?;
    if (server != null) {
      final input = server['inputTranscription'] as Map<String, dynamic>?;
      if (input != null) _inputTranscript.write(input['text']);
      final output = server['outputTranscription'] as Map<String, dynamic>?;
      if (output != null) _outputTranscript.write(output['text']);

      final parts =
          (server['modelTurn'] as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      for (final part in parts ?? const []) {
        final inline =
            (part as Map<String, dynamic>)['inlineData']
                as Map<String, dynamic>?;
        if (inline != null) _audio.add(base64Decode(inline['data'] as String));
      }
      if (server['interrupted'] == true) print('← interrupted');
      if (server['turnComplete'] == true && !_turn.isCompleted)
        _turn.complete();
    }

    final toolCall = message['toolCall'] as Map<String, dynamic>?;
    if (toolCall != null && !_toolCall.isCompleted) {
      final calls = toolCall['functionCalls'] as List<dynamic>? ?? const [];
      _toolCall.complete(
        calls.isEmpty ? null : calls.first as Map<String, dynamic>,
      );
    }

    if (message['goAway'] != null)
      print('← goAway ${jsonEncode(message['goAway'])}');
    if (message['error'] != null)
      print('!! error ${jsonEncode(message['error'])}');
  }

  void _onDone() {
    print(
      'socket cerrado · code=${_socket.closeCode} reason=${_socket.closeReason}',
    );
    if (!_turn.isCompleted) _turn.complete();
    if (!_toolCall.isCompleted) _toolCall.complete(null);
  }

  void sendText(String text) {
    _turn = Completer<void>();
    _socket.add(
      jsonEncode({
        'clientContent': {
          'turns': [
            {
              'role': 'user',
              'parts': [
                {'text': text},
              ],
            },
          ],
          'turnComplete': true,
        },
      }),
    );
  }

  /// Habla [text] con la voz del sistema y lo empuja por el socket en trozos de
  /// 100 ms, que es el ritmo al que los entregaría el micrófono en vivo.
  Future<void> sendSpeech(String text) async {
    _turn = Completer<void>();
    final pcm = await _synthesize(text);
    print(
      'dije  : "$text"  (${(pcm.length / (_inputSampleRate * 2)).toStringAsFixed(2)} s)',
    );

    const chunkBytes = 3200;
    for (var i = 0; i < pcm.length; i += chunkBytes) {
      final end = (i + chunkBytes < pcm.length) ? i + chunkBytes : pcm.length;
      _socket.add(
        jsonEncode({
          'realtimeInput': {
            'audio': {
              'data': base64Encode(Uint8List.sublistView(pcm, i, end)),
              'mimeType': 'audio/pcm;rate=$_inputSampleRate',
            },
          },
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _socket.add(
      jsonEncode({
        'realtimeInput': {'audioStreamEnd': true},
      }),
    );
  }

  void sendToolResponse(Map<String, dynamic> call, String result) {
    _turn = Completer<void>();
    _socket.add(
      jsonEncode({
        'toolResponse': {
          'functionResponses': [
            {
              'id': call['id'],
              'name': call['name'],
              'response': {'result': result},
            },
          ],
        },
      }),
    );
  }

  Future<void> waitForTurn() => _turn.future.timeout(
    const Duration(seconds: 45),
    onTimeout: () => print('!! sin turnComplete en 45 s'),
  );

  Future<Map<String, dynamic>?> waitForToolCall() {
    _toolCall = Completer<Map<String, dynamic>?>();
    return _toolCall.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => null,
    );
  }

  String takeInputTranscript() {
    final text = _inputTranscript.toString().trim();
    _inputTranscript.clear();
    return text;
  }

  String takeOutputTranscript() {
    final text = _outputTranscript.toString().trim();
    _outputTranscript.clear();
    return text;
  }

  List<int> toWav() => _wavHeader(_audio.length) + _audio.toBytes();

  Future<void> close() => _socket.close();
}

Future<String> _readKeyFromKeychain() async {
  final result = await Process.run('security', [
    'find-generic-password',
    '-s',
    'flutter_secure_storage_service',
    '-a',
    'gemini_api_key',
    '-w',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'No hay llave de Gemini en el llavero. Arranca la app y pásala por la '
      'pantalla de configuración inicial.',
    );
  }
  return (result.stdout as String).trim();
}

/// Voz del sistema en PCM 16 kHz mono: el mismo formato exacto que entrega el
/// micrófono, así que lo que prueba esto es lo que va a pasar en vivo.
Future<Uint8List> _synthesize(String text) async {
  final file = File('${Directory.systemTemp.path}/nexus_spike_say.wav');
  var result = await Process.run('say', [
    '-v',
    'Mónica',
    '--data-format=LEI16@$_inputSampleRate',
    '-o',
    file.path,
    text,
  ]);
  if (result.exitCode != 0) {
    // La voz en español puede no estar instalada; con la del sistema basta.
    result = await Process.run('say', [
      '--data-format=LEI16@$_inputSampleRate',
      '-o',
      file.path,
      text,
    ]);
    if (result.exitCode != 0) throw StateError('say falló: ${result.stderr}');
  }
  return _pcmFromWav(file.readAsBytesSync());
}

/// Busca el trozo `data` recorriendo las cabeceras RIFF. `say` no siempre
/// escribe una cabecera de 44 bytes, así que asumirlo se rompe en silencio.
Uint8List _pcmFromWav(Uint8List wav) {
  final view = ByteData.sublistView(wav);
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    if (id == 'data')
      return Uint8List.sublistView(wav, offset + 8, offset + 8 + size);
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('No se encontró el trozo data en el WAV de say');
}

List<int> _wavHeader(int dataLength) {
  final header = ByteData(44);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, _outputSampleRate, Endian.little);
  header.setUint32(28, _outputSampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataLength, Endian.little);
  return header.buffer.asUint8List();
}

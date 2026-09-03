import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/data/datasources/gemini_live_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';

/// Abre sesiones de voz contra Gemini Live y traduce su JSON a [VoiceEvent].
/// Lo que un marco del servicio de voz significa: los eventos que produce y las
/// dos cosas que no son eventos.
class LoQueDiceElMarco {
  const LoQueDiceElMarco({
    this.eventos = const [],
    this.asaNueva,
    this.sinReconocer = false,
  });

  final List<VoiceEvent> eventos;

  /// El asa con la que reenganchar, si el servicio mandó una nueva.
  final String? asaNueva;

  /// No se supo qué era. Se anota —claves, no contenido— en vez de tirarlo.
  final bool sinReconocer;
}

class GeminiVoiceGateway implements VoiceGateway {
  GeminiVoiceGateway(
    this._dataSource,
    this._readApiKey,
    this._readVoiceName,
    this._readLanguage,
    this._readNames,
    this._readAgentName,
  );

  /// La llave se pide en el momento de conectar, no se guarda aquí: así una
  /// llave cambiada en Ajustes vale desde la siguiente sesión sin reconstruir
  /// nada, y no queda una copia viva en memoria más tiempo del necesario.
  final Future<String?> Function() _readApiKey;

  /// Se consulta al conectar, no se guarda: así una voz cambiada en Ajustes
  /// vale desde la siguiente sesión sin reconstruir nada.
  final String Function() _readVoiceName;

  /// El idioma elegido en Ajustes. Se consulta al conectar, como la voz: una
  /// app en inglés con una voz que responde en español sería lo peor de los dos
  /// mundos.
  final String Function() _readLanguage;

  /// Los nombres elegidos en Ajustes, ya redactados para el prompt, o `null`
  /// si no se ha puesto ninguno.
  ///
  /// **Faltaba, y era el agujero.** Los nombres llegaban al prompt de Claude y
  /// a la etiqueta del chat, pero aquí la instrucción decía «Eres Nexus» a
  /// pelo: le ponías nombre a la voz y la voz no lo sabía, ni sabía cómo
  /// llamarte. Se reportó hablándole por su nombre y viendo que contestaba sin
  /// usar el de quien preguntaba.
  final String? Function() _readNames;

  /// Cómo se llama quien contesta, o `null` para el de la app.
  ///
  /// Va aparte de [_readNames] a propósito. Lo primero que escribí sacaba el
  /// nombre de la frase redactada con una expresión regular, y eso se rompe en
  /// cuanto cambie la redacción o la app esté en inglés: leer un dato de
  /// vuelta de un texto que se escribió para un modelo es adivinar, no saber.
  final String? Function() _readAgentName;

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

  /// La instrucción de sistema de la voz.
  ///
  /// Pública y pura para poder comprobarla: aquí es donde se decide cómo se
  /// llama quien contesta y cómo llama a quien pregunta, y eso llevaba
  /// **cableado a «Nexus»** aunque hubiera un nombre elegido en Ajustes. Sin
  /// una costura como esta no había forma de medirlo — ninguna prueba
  /// construye el gateway, porque para construirlo hace falta un socket.
  static String instruccionDelSistema({
    required String? agente,
    required String idioma,
    required String nombres,
  }) =>
      'Eres ${agente ?? 'Nexus'}, un asistente de voz que vive en el '
      'Mac de quien te habla. '
      'Respondes en $idioma, en frases cortas: esto se escucha, '
      'no se lee.\n'
      '$nombres'
      'REGLA PRINCIPAL: absolutamente todo lo que te pidan —cualquier '
      'pregunta, consulta, tarea o encargo, sea de código o no— se lo pasas a '
      'Claude llamando a pedir_a_claude, y después cuentas lo que devolvió. '
      'NO respondas de memoria aunque sepas la respuesta: tú pones la voz, '
      'Claude pone el trabajo.\n'
      'Solo contestas tú, sin llamar a nadie, a lo que no es un encargo: '
      'saludos, agradecimientos, "para", "espera", o cuando te pidan repetir '
      'algo que acabas de decir. Esa lista es completa: no la amplíes — y la '
      'app la comprueba, así que si contestas de memoria otra cosa, se lo '
      'preguntará a Claude igual y tendrás que rectificar en voz alta.\n'
      'ZONA GRIS, medida: preguntas como "¿qué opinas de Riverpod?", "¿qué '
      'hora es?", "¿cuánto ocupa este repo?" o "¿qué versión tengo instalada?" '
      'SÍ son encargos y van a Claude, aunque creas saber la respuesta: la '
      'tuya sale de tu memoria y la de Claude sale de esta máquina. Ante la '
      'duda, llama a la herramienta — equivocarse llamando cuesta unos '
      'segundos, y equivocarse contestando de memoria cuesta un dato falso '
      'dicho con seguridad.\n'
      'Antes de llamar a una herramienta di en tres o cuatro palabras qué vas '
      'a hacer, para que no haya un silencio largo mientras se trabaja.\n'
      'Si el sistema te entrega una respuesta de Claude, cuéntala tal cual y '
      'sigue la conversación sin disculparte ni explicar por qué llega.\n'
      'EL PARTE: «dame el daily», «el parte», «el standup» o «qué hice ayer» '
      'no son un encargo suelto para Claude: llama a pedir_el_parte, que trae '
      'el material del día ya reunido. Cuando vuelva, resúmelo en dos o tres '
      'frases —no lo leas entero, que es largo— y di que queda en pantalla '
      'con el botón para mandarlo a Slack.\n'
      'SKILLS: si al resolver algo detectas que faltaba conocimiento que se va '
      'a volver a necesitar —un procedimiento del proyecto, una convención, una '
      'tarea que ya se ha repetido— ofrécele crear una skill con crear_skill, '
      'en una frase y sin insistir. Ofrécelo **después** de resolver lo que te '
      'pidieron, nunca en vez de resolverlo, y solo si él acepta.';

  /// Los nombres, con su salto de línea, o vacío.
  ///
  /// Vacío y no `null` para que la instrucción se concatene sin un `if` en
  /// medio de una cadena de veinte líneas.
  String _losNombres() {
    final linea = _readNames();
    return linea == null ? '' : '$linea\n';
  }

  /// Dejó de ser `static` al meter el idioma: la instrucción de sistema ya no
  /// es la misma siempre, depende de en qué idioma se responde.
  Map<String, dynamic> get _setup => {
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
          'text': instruccionDelSistema(
            agente: _readAgentName(),
            idioma: _readLanguage(),
            nombres: _losNombres(),
          ),
        },
      ],
    },
    'tools': [
      {'functionDeclarations': lasHerramientas},
    ],
  };

  /// Lo que el modelo lee para decidir a quién llamar y con qué.
  ///
  /// 🔴 **Aparte del setup, y estático, para poder fijarlo en una prueba.**
  /// Aquí vivió durante semanas una frase que decía «todavía no hay carpeta
  /// emparejada, así que trabaja sobre el directorio donde corre la app» —
  /// incondicional, y falsa desde que emparejar carpetas es el eje del
  /// producto. No la pilló nadie porque esto es **interfaz hacia un modelo**:
  /// no tiene tipos que fallen ni pantalla donde se vea mal. Se rompe en
  /// silencio y se paga en cómo enruta cada encargo.
  static final List<Map<String, dynamic>> lasHerramientas = [
    {
      'name': toolName,
      'description':
          'Le pasa a Claude Code cualquier encargo: responder una pregunta, '
          'leer o editar archivos, mirar el estado de git, ejecutar comandos. '
          'Es la vía por defecto para todo lo que te pidan, no solo para '
          'tareas de programación. El encargo corre en la carpeta de esta '
          'conversación, con su cuenta, su modelo y sus permisos: no tienes '
          'que decir la ruta ni buscarla, y si no hubiera ninguna emparejada '
          'te lo dirá la respuesta.',
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
    {
      'name': testToolName,
      'description':
          'Lanza una prueba de Maestro del proyecto y la enseña en '
          'pantalla, paso a paso. Úsala **siempre** que te pidan correr, '
          'lanzar o ejecutar una prueba, un flow o el suite, en vez de '
          'pedírselo a Claude: la lanza Nexus directamente, así que '
          'funciona con el permiso en solo lectura y sin depender de nada '
          'más. Si lo que dijeron encaja en varias pruebas te lo diré, y '
          'entonces pregunta cuál en vez de elegir tú.',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'prueba': {
            'type': 'STRING',
            'description':
                'El nombre de la prueba tal como lo dijeron, sin '
                'inventarse la extensión ni la ruta.',
          },
        },
        'required': ['prueba'],
      },
    },
    {
      'name': parteToolName,
      'description':
          'Redacta el parte del día: lo que se hizo el último día con '
          'trabajo, y lo deja en pantalla con un botón para mandarlo a '
          'Slack. Úsala cuando pidan «el daily», «el parte», «el '
          'standup», «qué hice ayer» o «cuéntame lo de ayer», en vez de '
          'pasárselo a Claude como un encargo suelto: por aquí sale con '
          'el material del día ya reunido, y es el mismo parte que sale '
          'por el menú. No lleva parámetros: el día lo elige la app, que '
          'es la que sabe cuál fue el último con trabajo.',
      'parameters': {'type': 'OBJECT', 'properties': <String, Object?>{}},
    },
    {
      'name': agendaToolName,
      'description':
          'Dice qué reuniones hay hoy. Úsala cuando pregunten «qué '
          'reuniones tengo», «qué tengo hoy», «cómo está mi agenda» o '
          'parecido, en vez de pasárselo a Claude: la app ya leyó el '
          'calendario para poder avisar, así que por aquí contesta al '
          'momento y sin gastar un encargo. No lleva parámetros: siempre '
          'es hoy.',
      'parameters': {'type': 'OBJECT', 'properties': <String, Object?>{}},
    },
  ];

  /// Los nombres viven aquí y no sueltos en el JSON porque el caso de uso
  /// tiene que reconocerlos cuando el modelo los llama.
  static const toolName = 'pedir_a_claude';
  static const skillToolName = 'crear_skill';
  static const testToolName = 'correr_prueba';
  static const parteToolName = 'pedir_el_parte';
  static const agendaToolName = 'consultar_agenda';

  /// Qué significa un marco del servicio.
  ///
  /// 🔴 **Pura y aparte porque es todo el adaptador del protocolo, y no lo
  /// cubría nada.** Lo que se le manda al modelo sí tiene prueba —ver
  /// [lasHerramientas]— pero lo que se lee de vuelta no la tenía, y es la mitad
  /// que no controlamos: **el formato lo decide Google**. Si cambia la forma de
  /// un marco esto no da error; simplemente deja de emitir ese evento, y la
  /// conversación se queda esperando algo que ya pasó. Sin excepción, sin log y
  /// sin nada que mirar.
  ///
  /// Es el mismo motivo por el que la capa `data` fija los formatos que lee de
  /// fuera, y el mismo precedente que [loQueMandoElServicio] y
  /// [GeminiLiveConnection.comoJson]: público para poder probarlo sin abrir un
  /// socket.
  static LoQueDiceElMarco leerElMarco(Map<String, dynamic> marco) {
    if (marco.containsKey('setupComplete')) {
      return const LoQueDiceElMarco(eventos: [VoiceSessionReady()]);
    }

    // El asa se renueva sola durante la conversación; hay que quedarse con la
    // última, no con la primera.
    if (marco['sessionResumptionUpdate'] case final Map<String, dynamic> r) {
      final asa = r['newHandle'] as String?;
      return LoQueDiceElMarco(asaNueva: r['resumable'] == true ? asa : null);
    }

    // Aviso de que esta conexión se acaba. No hace falta hacer nada: el corte
    // se atiende igual cuando llega, con aviso o sin él —a veces no lo hay—, y
    // el reenganche es asunto del caso de uso.
    if (marco.containsKey('goAway')) return const LoQueDiceElMarco();

    if (marco['toolCall'] case final Map<String, dynamic> llamada) {
      return LoQueDiceElMarco(eventos: _lasLlamadas(llamada));
    }

    final server = marco['serverContent'] as Map<String, dynamic>?;
    if (server == null) return const LoQueDiceElMarco(sinReconocer: true);

    return LoQueDiceElMarco(eventos: _loDelTurno(server));
  }

  static List<VoiceEvent> _lasLlamadas(Map<String, dynamic> toolCall) => [
    for (final call in toolCall['functionCalls'] as List<dynamic>? ?? const [])
      if (call is Map<String, dynamic>)
        if (call['id'] case final String id)
          if (call['name'] case final String name)
            VoiceToolRequested(
              callId: id,
              name: name,
              arguments: call['args'] as Map<String, dynamic>? ?? const {},
            ),
  ];

  static List<VoiceEvent> _loDelTurno(Map<String, dynamic> server) {
    final eventos = <VoiceEvent>[];

    final loQueDijo =
        (server['inputTranscription'] as Map<String, dynamic>?)?['text']
            as String?;
    if (loQueDijo != null && loQueDijo.isNotEmpty) {
      eventos.add(VoiceUserTranscript(loQueDijo));
    }

    final loQueContesta =
        (server['outputTranscription'] as Map<String, dynamic>?)?['text']
            as String?;
    if (loQueContesta != null && loQueContesta.isNotEmpty) {
      eventos.add(VoiceReplyTranscript(loQueContesta));
    }

    final partes =
        (server['modelTurn'] as Map<String, dynamic>?)?['parts']
            as List<dynamic>?;
    for (final parte in partes ?? const []) {
      if (parte is! Map<String, dynamic>) continue;
      final dentro = parte['inlineData'] as Map<String, dynamic>?;
      if (dentro?['data'] case final String audio) {
        eventos.add(VoiceReplyAudio(base64Decode(audio)));
      }
    }

    // 🔴 **El orden importa: `interrupted` antes que `turnComplete`**, porque
    // quien escuche tiene que tirar la cola del altavoz antes de dar el turno
    // por cerrado. Al revés se oye la coleta de lo que se acaba de interrumpir.
    if (server['interrupted'] == true) eventos.add(const VoiceInterrupted());
    if (server['turnComplete'] == true) {
      eventos.add(const VoiceTurnCompleted());
    }
    return eventos;
  }

  /// Qué anotar cuando el servicio manda un marco que no se entiende.
  ///
  /// 🔴 **Las claves sí, el contenido no.** Por este socket viaja lo que dices y
  /// lo que Claude leyó de tu carpeta, y este registro acaba en los informes de
  /// fallo: volcar el marco entero sería sacar de la máquina —por una puerta que
  /// nadie mira— exactamente lo que la app promete no sacar.
  ///
  /// Los nombres de las claves bastan para saber qué llegó. Y si dentro hay un
  /// error, su mensaje se saca aparte: ahí está la respuesta que se vino a
  /// buscar, y un código de cuota o un modelo retirado no son datos de nadie.
  ///
  /// Pura y pública para poder probar justo eso: que el contenido no aparece.
  static String loQueMandoElServicio(Map<String, dynamic> marco) {
    final claves = marco.keys.join(', ');
    final error = marco['error'];
    final detalle = switch (error) {
      final Map<String, Object?> e => ' · ${e['message'] ?? e['status'] ?? ''}',
      null => '',
      _ => ' · $error',
    };
    return 'voz · el servicio mandó algo que no se entiende: $claves$detalle';
  }
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

  /// Deja en el registro qué mandó el servicio cuando no se entiende. La línea
  /// la compone [GeminiVoiceGateway.loQueMandoElServicio], que es pura para
  /// poder probar lo que **no** lleva dentro.
  void _anotaLoDesconocido(Map<String, dynamic> message) =>
      debugPrint(GeminiVoiceGateway.loQueMandoElServicio(message));

  void _translate(Map<String, dynamic> message) {
    final dice = GeminiVoiceGateway.leerElMarco(message);
    for (final evento in dice.eventos) {
      _events.add(evento);
    }
    if (dice.asaNueva case final asa?) onResumptionHandle(asa);
    // 🔴 **Lo que no se reconoce se anota, no se tira.**
    //
    // Aquí había un `return` seco, y con él se perdía **lo único que el
    // servicio tenía que decir** cuando algo iba mal. Medido en el registro de
    // la app: cinco sesiones seguidas con «203 trozos del micro, 203 enviados,
    // 1 eventos recibidos · primera señal del servicio en todavía nada». Ese
    // «1 evento» era el `setupComplete`; si además hubiera llegado un marco de
    // error —cuota, modelo retirado, petición rechazada— habría entrado por
    // aquí y habría desaparecido igual.
    //
    // Para quien usa la app eso es silencio: el orbe escucha, se calla y vuelve
    // a dormir sin decir nada.
    if (dice.sinReconocer) _anotaLoDesconocido(message);
  }

  @override
  void sendSystemNote(String text) {
    // `clientContent` con el turno cerrado: es lo mismo que enviaría un
    // teclado, y el modelo responde a ello como a cualquier otra cosa.
    _connection.send({
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
    });
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

  /// El campo que el servicio entiende como «este flujo de audio terminó».
  ///
  /// Se manda en vez de rellenar con silencio a mano, que era la otra salida: 1,2 s de
  /// ceros funcionarían igual, pero serían 38 KB de nada por cada turno y dejarían la
  /// duración del silencio duplicada —aquí y en la configuración del detector— con dos
  /// sitios donde puede desincronizarse.
  @override
  void endAudio() {
    _connection.send({
      'realtimeInput': {'audioStreamEnd': true},
    });
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _connection.close();
    if (!_events.isClosed) await _events.close();
  }
}

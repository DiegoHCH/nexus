import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';
import 'package:nexus/features/assistant/domain/repositories/correr_una_prueba.dart';
import 'package:nexus/features/assistant/domain/repositories/el_parte_del_dia.dart';
import 'package:nexus/features/assistant/domain/usecases/claude_errand.dart';
import 'package:nexus/features/assistant/domain/usecases/hold_voice_conversation.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_sale_hacia_la_voz.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';

/// El micrófono, callado: esta prueba va de lo que llega del servicio.
class _Mic implements VoiceInput {
  final _frames = StreamController<AudioFrame>();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<AudioFrame> listen() => _frames.stream;

  final _pausas = StreamController<void>.broadcast();

  @override
  Stream<void> get pausas => _pausas.stream;

  /// El micrófono se cierra. Es lo que hace el del teléfono al tocar el botón, y lo que
  /// el del Mac **no** hace mientras la sesión vive: **corta sin terminar el flujo**.
  void cortar() => _pausas.add(null);

  /// Y esto es el flujo terminándose, que es otra cosa.
  Future<void> cerrar() => _frames.close();
}

/// La sesión de voz, movida a mano desde la prueba.
class _Session implements VoiceSession {
  final events_ = StreamController<VoiceEvent>.broadcast();
  final notes = <String>[];

  void emit(VoiceEvent event) => events_.add(event);

  @override
  Stream<VoiceEvent> get events => events_.stream;

  @override
  String? endReason;

  @override
  void sendAudio(Uint8List pcm) {}

  /// Cuántas veces se dijo que el audio terminó. Es lo que hace que el servicio cierre
  /// el turno cuando el micrófono se cierra de golpe, como hace el del teléfono.
  var avisosDeFin = 0;

  @override
  void endAudio() => avisosDeFin++;

  @override
  void sendSystemNote(String text) => notes.add(text);

  /// Lo que se le entregó al servicio de voz como respuesta de una herramienta.
  /// Era un método vacío: sin guardarlo no había forma de comprobar **qué** sale
  /// de la máquina, solo que salía algo.
  final toolResults = <String>[];

  @override
  void sendToolResult({
    required String callId,
    required String name,
    required String result,
  }) => toolResults.add(result);

  @override
  Future<void> close() async {
    if (!events_.isClosed) await events_.close();
  }
}

class _Gateway implements VoiceGateway {
  _Gateway(this.session);
  final _Session session;

  @override
  Future<VoiceSession> connect() async => session;

  @override
  Future<VoiceSession> resume() async => session;
}

class _Speaker implements AudioOutput {
  @override
  Future<void> start() async {}
  @override
  void enqueue(Uint8List pcm) {}
  @override
  Future<void> discard() async {}
  @override
  Future<Duration> pending() async => Duration.zero;
  @override
  Future<void> stop() async {}
}

/// Anota el encargo que le llega. Es el testigo de la prueba: lo que Claude
/// recibe es lo que el usuario dijo, o no lo es.
///
/// Se guarda **sin la coletilla del idioma** que `AskClaude` le pega detrás:
/// aquí se mira qué se pidió, no cómo se envuelve.
class _Bridge implements ClaudeBridge {
  _Bridge({this.tarda = Duration.zero, this.respuesta});

  /// Lo que contesta Claude, cuando a la prueba le importa. `null` deja la
  /// respuesta de siempre, que repite lo que se pidió.
  final String? respuesta;

  /// Lo que tarda Claude en contestar. Con `Duration.zero` el encargo va y
  /// vuelve dentro del mismo turno; alargándolo se reproduce lo que pasa de
  /// verdad — que la respuesta buena llega cuando ya estás hablando de otra
  /// cosa.
  final Duration tarda;

  final _raw = <String>[];

  List<String> get asked => [
    for (final instruction in _raw) instruction.split('\n\n').first,
  ];

  @override
  Stream<ClaudeEvent> ask(
    String instruction, {
    required String workingDirectory,
    required bool canEdit,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? claudeProfile,
    String? model,
    String? effort,
    String? artifactsFolder,
    String? carpetaDePruebas,
    List<String> disallowedTools = const [],
    List<String> comandosPermitidos = const [],
    String? constraintsNotice,
    String? language,
  }) async* {
    _raw.add(instruction);
    if (tarda > Duration.zero) await Future<void>.delayed(tarda);
    yield ClaudeTurnCompleted(
      result: respuesta ?? 'lo de «${instruction.split('\n\n').first}»',
    );
  }
}

class _Memory implements ConversationMemory {
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory(sessionId: null, prompts: []);
  @override
  Future<void> rememberSession(
    String folderPath,
    String id, {
    String? claudeProfile,
  }) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> forget(String folderPath) async {}
}

class _Awake implements StaysAwake {
  @override
  Future<void Function()> hold(String reason) async => () {};
}

/// Un doble de `HoldVoiceConversation` con todo cableado menos lo que la
/// prueba quiera mirar.
HoldVoiceConversation _conversation(
  _Session session,
  _Bridge bridge, {
  void Function(String)? log,
  _Lanzador? lanzador,
  _Parte? parte,
}) => HoldVoiceConversation(
  _Mic(),
  _Gateway(session),
  _Speaker(),
  _askClaude(bridge),
  log ?? (_) {},
  lanzador ?? _Lanzador(),
  parte ?? _Parte(),
);

/// El lanzador de pruebas, que apunta lo que se le pidió. Su gracia en estas
/// pruebas es la de al lado: comprobar que ese camino **no pasa por Claude**.
class _Lanzador implements CorrerUnaPrueba {
  _Lanzador();

  /// Lo que contesta. Fijo: lo que estas pruebas miran es **quién**
  /// atiende la herramienta, no qué dice.
  final dice = 'Lanzada «login».';
  final pedidos = <String>[];

  @override
  Future<String> loQuePidieron(String pedido) async {
    pedidos.add(pedido);
    return dice;
  }
}

/// El parte del día. Apunta si se le pidió el material y qué texto se le
/// devolvió ya escrito: eso es lo que estas pruebas miran —que hablando el
/// parte **acaba en la conversación** y no solo en la narración.
class _Parte implements ElParteDelDia {
  _Parte({this.hay = 'cuenta lo del día 12'});

  /// Lo que devuelve como material, o `null` para el día sin trabajo.
  final String? hay;
  var seLoPidieron = 0;
  final escritos = <String>[];

  @override
  Future<String?> instruccion() async {
    seLoPidieron++;
    return hay;
  }

  @override
  void yaEstaEscrito(String parte) => escritos.add(parte);
}

AskClaude _askClaude2(ClaudeBridge bridge) => _armar(bridge);

AskClaude _askClaude(_Bridge bridge) => _armar(bridge);

AskClaude _armar(ClaudeBridge bridge) => AskClaude(
  bridge,
  (_) async => (
    workingDirectory: '/repo',
    canEdit: false,
    extraDirectories: const <String>[],
    language: 'español',
    claudeProfile: null,
    model: null,
    effort: null,
    artifactsFolder: null,
    carpetaDePruebas: null,
    disallowedTools: const <String>[],
    comandosPermitidos: const <String>[],
    constraintsNotice: null,
  ),
  _Memory(),
  FolderErrandQueue(),
  _Awake(),
);

/// Un puente que **anuncia el modelo**, como hace el CLI en su evento `init`.
///
/// El `_Bridge` de arriba solo emite el fin de turno, y por eso ninguna prueba
/// veía que el modelo se estaba tirando: el evento que lo trae no existía en las
/// pruebas.
class _BridgeQueDiceElModelo implements ClaudeBridge {
  _BridgeQueDiceElModelo(this.model);

  final String model;

  @override
  Stream<ClaudeEvent> ask(
    String instruction, {
    required String workingDirectory,
    required bool canEdit,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? claudeProfile,
    String? model,
    String? effort,
    String? artifactsFolder,
    String? carpetaDePruebas,
    List<String> disallowedTools = const [],
    List<String> comandosPermitidos = const [],
    String? constraintsNotice,
    String? language,
  }) async* {
    // El orden es el de verdad: primero el `init` con el modelo, y el fin de
    // turno con las cifras al final.
    yield ClaudeSessionStarted(sessionId: 'ses-1', model: this.model);
    yield const ClaudeTurnCompleted(
      result: 'hecho',
      turnTokens: 1200,
      contextTokens: 175922,
    );
  }
}

void main() {
  test(
    'una frase larga llega en pedazos y va a Claude entera, no su cola (b11)',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
        _Lanzador(),
        _Parte(),
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      // Así llega de verdad: la transcripción de lo que dices viene por
      // trozos, no frase a frase. Lo dice el propio evento.
      for (final trozo in [
        'mira el repositorio ',
        'de nexus y dime ',
        'cuántos tests hay',
      ]) {
        session.emit(VoiceUserTranscript(trozo));
      }
      // El modelo contestó de memoria, sin llamar a la herramienta: aquí es
      // donde este código corrige y manda el encargo a Claude.
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, hasLength(1));
      expect(
        bridge.asked.single,
        'mira el repositorio de nexus y dime cuántos tests hay',
        reason:
            'antes se guardaba solo el último trozo, así que a Claude le '
            'llegaba «cuántos tests hay» — la frase cortada a mitad',
      );

      await subscription.cancel();
    },
  );

  test(
    'el turno cierra la frase: la siguiente no arrastra la anterior',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
        _Lanzador(),
        _Parte(),
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('corre los tests'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      session.emit(const VoiceUserTranscript('y ahora mira el historial'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, ['corre los tests', 'y ahora mira el historial']);

      await subscription.cancel();
    },
  );

  test(
    'una corrección que llega tarde no interrumpe: ya hablabas de otra cosa',
    () async {
      final session = _Session();
      // Claude tarda: para cuando contesta lo primero, el usuario ya preguntó
      // otra cosa. Es la sesión real del 13 ago, donde dos correcciones se
      // pisaron y la segunda dejó a la primera a medias.
      final bridge = _Bridge(tarda: const Duration(milliseconds: 120));
      final registro = <String>[];
      final conversation = _conversation(session, bridge, log: registro.add);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      // Turno 1: se pide algo que tenía que ir a Claude, y el modelo contesta
      // de memoria — así que arranca la corrección, que tardará.
      session.emit(const VoiceUserTranscript('dame un resumen de gitflow'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Turno 2: el usuario no espera y pregunta otra cosa.
      session.emit(const VoiceUserTranscript('enséñame cómo es un flujo'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        session.notes,
        isEmpty,
        reason:
            'la respuesta del turno 1 llegó cuando ya se hablaba del 2: '
            'entregarla hace que el modelo abandone lo que está diciendo',
      );
      expect(
        registro.where((l) => l.contains('descartada por vieja')),
        hasLength(1),
        reason: 'y se cuenta, para saber cuántas veces pasa de verdad',
      );

      await subscription.cancel();
    },
  );

  test(
    'la corrección sí entra si sigues callado: no se pierde por ir lenta',
    () async {
      final session = _Session();
      final bridge = _Bridge(tarda: const Duration(milliseconds: 120));
      final conversation = _conversation(session, bridge);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('dame un resumen de gitflow'));
      session.emit(const VoiceTurnCompleted());
      // Nadie habla encima: el turno sigue siendo el mismo cuando Claude vuelve.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(session.notes, hasLength(1));
      expect(session.notes.single, contains('dame un resumen de gitflow'));

      await subscription.cancel();
    },
  );

  test(
    'un saludo suelto sigue sin ir a Claude, aunque ahora se acumule',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
        _Lanzador(),
        _Parte(),
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('hola'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, isEmpty);

      await subscription.cancel();
    },
  );

  test('antes de la primera señal se espera más de los 6 s de siempre (b11)', () {
    // La carrera, medida en una sesión real: el `setupComplete` llegó a los
    // 2453 ms —y como es un evento, reinició la cuenta— y la primera señal de
    // que el servicio te oía, a los 7251 ms. Con el plazo corto la sesión moría
    // a los 8453: se salvó por 1,2 s, y las que fallaban perdían esa carrera.
    //
    // Se mira **el registro** y no el cierre del stream: la cadena de apagado
    // no se asienta bajo `fakeAsync`, así que esperar al `onDone` daba una
    // prueba que pasaba con el plazo viejo y con el nuevo — o sea, ninguna.
    // La línea de cierre, en cambio, se emite en cuanto vence el plazo.
    fakeAsync((async) {
      final session = _Session();
      final registro = <String>[];
      final conversation = _conversation(session, _Bridge(), log: registro.add);
      conversation().listen((_) {});
      async.flushMicrotasks();

      session.emit(const VoiceSessionReady());
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 7))
        ..flushMicrotasks();

      expect(
        registro.where((l) => l.contains('cierre por inactividad')),
        isEmpty,
        reason: 'a los 7 s se cerraba, justo antes de que el servicio hablara',
      );

      // Y sigue siendo un plazo: sin señal, el micrófono no queda abierto para
      // siempre.
      async
        ..elapse(const Duration(seconds: 15))
        ..flushMicrotasks();
      expect(
        registro.where((l) => l.contains('cierre por inactividad')),
        hasLength(1),
      );
    });
  });

  test('hablando, el fin del encargo lleva el modelo y no solo los tokens', () async {
    // La prueba que faltaba, y que se echó en falta de la peor manera: el arreglo
    // se dio por hecho con el cableado muerto. Las pruebas de entonces miraban el
    // medidor y la entidad —los dos correctos— mientras el evento que trae el
    // modelo seguía descartándose con un `break`.
    //
    // Sin el modelo, `contextWindow` da por hecha una ventana de 200k: los 175.922
    // tokens de una sesión de un millón salían como 88 % en vez de 18 %.
    final session = _Session();
    final conversation = HoldVoiceConversation(
      _Mic(),
      _Gateway(session),
      _Speaker(),
      _askClaude2(_BridgeQueDiceElModelo('claude-opus-5[1m]')),
      (_) {},
      _Lanzador(),
      _Parte(),
    );

    final vistos = <VoiceEvent>[];
    final subscription = conversation().listen(vistos.add);
    await Future<void>.delayed(Duration.zero);

    session.emit(const VoiceUserTranscript('corre los tests'));
    session.emit(const VoiceTurnCompleted());
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final fin = vistos.whereType<VoiceToolFinished>().singleOrNull;
    expect(fin, isNotNull, reason: 'el encargo tiene que terminar');
    expect(
      fin!.model,
      'claude-opus-5[1m]',
      reason:
          'el modelo del `init` tiene que viajar con el fin del encargo: sin '
          'él el medidor asume 200k y el porcentaje sale por cinco',
    );
    expect(fin.contextTokens, 175922);

    // Y aplicado como lo aplica el controlador, la ventana sale bien.
    final medidor = const SessionMeter().copyWith(
      model: fin.model,
      contextTokens: fin.contextTokens,
    );
    expect(medidor.contextWindow, 1000000);
    expect(medidor.contextPercent, 18);

    await subscription.cancel();
  });

  group('lo que sale hacia el servicio de voz tiene tope', () {
    // El precio de hablar es que la respuesta de Claude viaje a Google para que
    // la narren. Lo que no puede ser es que ese precio no tenga techo: iba la
    // respuesta entera, del tamaño que fuera.
    test('una respuesta enorme no sale entera', () async {
      final session = _Session();
      final gigante = List.filled(400, 'una linea de relleno.').join('\n');
      final bridge = _Bridge(respuesta: gigante);
      final registro = <String>[];
      final conversation = _conversation(session, bridge, log: registro.add);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: '1',
          name: ClaudeErrand.askTool,
          arguments: {'instruccion': 'lee todo el repo'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(session.toolResults, hasLength(1));
      final salio = session.toolResults.single;

      expect(gigante.length, greaterThan(LoQueSaleHaciaLaVoz.maxCaracteres));
      expect(
        salio.length,
        lessThanOrEqualTo(
          LoQueSaleHaciaLaVoz.maxCaracteres + LoQueSaleHaciaLaVoz.aviso.length,
        ),
      );
      // Y el aviso viaja dentro: sin él el modelo recibiría algo que acaba a
      // media frase y se inventaría el cierre, que es peor que decir que falta.
      expect(salio, endsWith(LoQueSaleHaciaLaVoz.aviso));

      // Queda anotado, porque «por qué no contó todo» es una pregunta que
      // alguien va a hacer y el registro es donde se contesta.
      expect(
        registro.where((l) => l.contains('se queda en la pantalla')),
        hasLength(1),
      );

      await subscription.cancel();
    });

    test('una normal sale tal cual, sin coletillas', () async {
      final session = _Session();
      final bridge = _Bridge(respuesta: 'son tres archivos y ninguno falla');
      final conversation = _conversation(session, bridge);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: '1',
          name: ClaudeErrand.askTool,
          arguments: {'instruccion': 'como va eso'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(session.toolResults.single, 'son tres archivos y ninguno falla');

      await subscription.cancel();
    });
  });

  group('correr una prueba no pasa por Claude', () {
    // El motivo entero de la herramienta. Antes, hablar el suite era: el modelo
    // elige la herramienta de Claude, Claude elige la del MCP de Maestro, y el
    // MCP tiene que estar vivo — tres eslabones, y el último ni siquiera es
    // nuestro. Aquí no hay ninguno.
    test('va al lanzador, y Claude no se entera', () async {
      final session = _Session();
      final bridge = _Bridge();
      final lanzador = _Lanzador();
      final conversation = _conversation(session, bridge, lanzador: lanzador);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: '1',
          name: ClaudeErrand.testTool,
          arguments: {'prueba': 'el login'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(lanzador.pedidos, ['el login']);
      // Y esto es lo que hace cierta la frase de la demo: sin encargo a Claude,
      // el modo de permisos no entra en juego. No es que se lo salte — es que
      // no lo toca.
      expect(bridge.asked, isEmpty);

      // Lo que el lanzador contesta es lo que se le entrega al modelo para que
      // lo narre: si no volviera nada, la conversación se quedaría muda
      // esperando una respuesta que no llega.
      expect(session.toolResults.single, lanzador.dice);

      await subscription.cancel();
    });

    test('sin nombre se contesta igual, no se lanza a ciegas', () async {
      final session = _Session();
      final lanzador = _Lanzador();
      final conversation = _conversation(
        session,
        _Bridge(),
        lanzador: lanzador,
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: '1',
          name: ClaudeErrand.testTool,
          arguments: {},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Llega vacío y se deja decidir al lanzador, que sabe qué pruebas hay y
      // puede enumerarlas. Cortarlo aquí sería contestar «falta el nombre»
      // cuando lo útil es decir cuáles son.
      expect(lanzador.pedidos, ['']);
      expect(session.toolResults, hasLength(1));

      await subscription.cancel();
    });
  });

  group('el parte del día, dicho hablando', () {
    // El encargo no se escribe en la conversación —hay que ir a mirar qué se
    // hizo y en qué carpetas— pero sí acaba en Claude, que es quien lo redacta.
    // Las dos mitades tienen que encajar: material del puerto, redacción de
    // Claude.
    test('el material lo pone el puerto y la redacción, Claude', () async {
      final session = _Session();
      final bridge = _Bridge(respuesta: 'Ayer: tres PRs y una release.');
      final parte = _Parte();
      final conversation = _conversation(session, bridge, parte: parte);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: '1',
          name: ClaudeErrand.parteTool,
          arguments: {},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(parte.seLoPidieron, 1);
      expect(bridge.asked, [parte.hay]);

      // Y lo que Claude escribió vuelve **a la conversación escrita**, no solo
      // al modelo para que lo cuente. Sin esto el parte se oiría y no quedaría
      // en ninguna parte: ni el texto, ni el botón para mandarlo a Slack.
      expect(parte.escritos, ['Ayer: tres PRs y una release.']);
      expect(session.toolResults.single, 'Ayer: tres PRs y una release.');

      await subscription.cancel();
    });

    // Sin día que contar no se le pide a Claude «invéntate el daily»: se dice
    // que no hay. Un parte de la nada es peor que ningún parte — se lee igual
    // de convincente.
    test('un día sin trabajo no llega a Claude, y se contesta igual', () async {
      final session = _Session();
      final bridge = _Bridge();
      final parte = _Parte(hay: null);
      final conversation = _conversation(session, bridge, parte: parte);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: '1',
          name: ClaudeErrand.parteTool,
          arguments: {},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(bridge.asked, isEmpty);
      expect(parte.escritos, isEmpty);
      // Callarse dejaría al modelo esperando una respuesta que no llega, y la
      // conversación muda para siempre.
      expect(session.toolResults, hasLength(1));

      await subscription.cancel();
    });
  });

  test('al cerrarse el microfono se le dice al servicio que el audio termino', () async {
    // El detector de turno es automatico y mira el audio: espera ver silencio para
    // decidir que terminaste. El microfono del Mac se lo da siempre —sigue mandando
    // aunque calles— pero el del telefono deja de mandar de golpe, asi que sin este
    // aviso el servicio esperaba un silencio que ya no llegaba y la sesion moria por
    // inactividad **con cero turnos**. Medido: 65 trozos entrando, un solo evento.
    final micro = _Mic();
    final session = _Session();
    final conversation = HoldVoiceConversation(
      micro,
      _Gateway(session),
      _Speaker(),
      _askClaude(_Bridge()),
      (_) {},
      _Lanzador(),
      _Parte(),
    );

    final sub = conversation().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(session.avisosDeFin, 0);

    micro.cortar();
    await Future<void>.delayed(Duration.zero);

    expect(
      session.avisosDeFin,
      1,
      reason: 'el turno se queda abierto para siempre',
    );
    await sub.cancel();
  });
}

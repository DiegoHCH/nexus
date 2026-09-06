import 'package:nexus/features/assistant/domain/repositories/la_agenda_de_hoy.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexus/features/assistant/domain/repositories/el_despacho_de_carpeta.dart';

import 'support/despacho.dart';

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
import 'package:nexus/features/assistant/domain/usecases/voice_routing.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_sale_hacia_la_voz.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Un despacho que siempre se lleva el encargo a otra parte.
class _SeLoLleva implements ElDespachoDeCarpeta {
  const _SeLoLleva(this.carpeta);

  final String carpeta;

  @override
  Future<LoQueQuedaPorHacer> despachar(
    String frase, {
    required String? carpetaDeAqui,
    required String loQueSeVe,
    required bool allowWrites,
    required List<String> attachments,
    bool elFocoSigue = true,
  }) async => YaSeFue(carpeta);
}

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
  Future<VoiceSession> connect({
    PerfilDeVoz perfil = const ComoUnaConversacion(),
  }) async => session;

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

  /// Con qué `canEdit` llegó cada encargo. Es lo que dice si el tope de
  /// escritura se aplicó.
  final conEdicion = <bool>[];

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
    String? nombres,
    String? modoConcedido,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    _raw.add(instruction);
    conEdicion.add(canEdit);
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
  Future<void> rememberPermissionMode(
    String f,
    String mode, {
    String? claudeProfile,
  }) async {}

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
  _Agenda? agenda,
  Duration? graciaDeLaRuta,
  ElDespachoDeCarpeta? despacho,
  String? carpeta,
  bool puedeEscribir = true,
  bool laCarpetaDeja = false,
}) => HoldVoiceConversation(
  _Mic(),
  _Gateway(session),
  _Speaker(),
  _askClaude(bridge, canEdit: laCarpetaDeja),
  log ?? (_) {},
  lanzador ?? _Lanzador(),
  parte ?? _Parte(),
  agenda ?? _Agenda(),
  despacho ?? const SinEnrutar(),
  () => carpeta,
  () => puedeEscribir,
  // 🔴 **Cero por defecto, y con motivo.** Cuando el modelo contesta de
  // memoria, primero se le pide que lo pase él y solo al vencer este plazo se
  // hace por él. Las pruebas de esta clase van de **qué llega a Claude**, no de
  // los diez segundos; dejándolas esperar de verdad serían pruebas del reloj.
  // Quien mide el plazo lo dice pasándolo.
  graciaDeLaRuta: graciaDeLaRuta ?? Duration.zero,
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

AskClaude _askClaude(_Bridge bridge, {bool canEdit = false}) =>
    _armar(bridge, canEdit: canEdit);

AskClaude _armar(ClaudeBridge bridge, {bool canEdit = false}) => AskClaude(
  bridge,
  (_) async => (
    workingDirectory: '/repo',
    canEdit: canEdit,
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
    nombres: null,
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
    String? nombres,
    String? modoConcedido,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
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
        _Agenda(),
        graciaDeLaRuta: Duration.zero,
        const SinEnrutar(),
        () => null,
        () => true,
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
      // Va dentro del encargo y no como el encargo entero: desde que la
      // transcripción se manda **marcada como transcripción**, lo que viaja
      // lleva delante de dónde salió. Lo que esta prueba mira sigue siendo lo
      // mismo — que dentro esté la frase completa.
      expect(
        bridge.asked.single,
        contains('mira el repositorio de nexus y dime cuántos tests hay'),
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
        _Agenda(),
        graciaDeLaRuta: Duration.zero,
        const SinEnrutar(),
        () => null,
        () => true,
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('corre los tests'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      session.emit(const VoiceUserTranscript('y ahora mira el historial'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, hasLength(2));
      expect(bridge.asked.first, contains('corre los tests'));
      expect(
        bridge.asked.last,
        contains('y ahora mira el historial'),
        reason: 'y sin arrastrar la anterior, que es lo que mira esta prueba',
      );
      expect(bridge.asked.last, isNot(contains('corre los tests')));

      await subscription.cancel();
    },
  );

  // Cuando el modelo contesta de memoria, la instrucción para Claude **se le
  // pide a él**, no se saca de la transcripción.
  //
  // 🔴 Nace de una sesión real: se preguntó «¿qué reuniones tengo para hoy?» y
  // el servicio de voz lo transcribió como «Este akeroniano es tengo para hoy».
  // El modelo había entendido bien —contestó las cinco reuniones correctas—: lo
  // que llegaba roto era el texto, que es lo que se le mandaba a Claude como
  // encargo. No se puede arreglar por configuración: en un modelo de audio
  // nativo el idioma se autodetecta y fijar un código no está soportado.
  group('lo que contestó de memoria se reencamina sin la transcripción', () {
    test('primero se le pide a él, y a Claude no le llega nada', () {
      fakeAsync((async) {
        final session = _Session();
        final bridge = _Bridge();
        final conversation = _conversation(
          session,
          bridge,
          graciaDeLaRuta: const Duration(seconds: 10),
        );
        conversation().listen((_) {});
        async.flushMicrotasks();

        session.emit(
          const VoiceUserTranscript('Este akeroniano es tengo para hoy'),
        );
        session.emit(const VoiceTurnCompleted());
        async
          ..elapse(const Duration(seconds: 2))
          ..flushMicrotasks();

        expect(session.notes.single, VoiceRouting.pasaloTu);
        expect(
          bridge.asked,
          isEmpty,
          reason: 'mandar la transcripción es mandar una frase que nadie dijo',
        );
      });
    });

    test('si lo pasa, la transcripción no llega nunca', () {
      fakeAsync((async) {
        final session = _Session();
        final bridge = _Bridge();
        final registro = <String>[];
        final conversation = _conversation(
          session,
          bridge,
          log: registro.add,
          graciaDeLaRuta: const Duration(seconds: 10),
        );
        conversation().listen((_) {});
        async.flushMicrotasks();

        session.emit(
          const VoiceUserTranscript('Este akeroniano es tengo para hoy'),
        );
        session.emit(const VoiceTurnCompleted());
        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();

        // Hace caso: llama a la herramienta con **su** instrucción, la que
        // redactó oyendo el audio.
        session.emit(
          const VoiceToolRequested(
            callId: 'c1',
            name: ClaudeErrand.askTool,
            arguments: <String, Object?>{
              'instruccion': 'dime qué reuniones tengo hoy',
            },
          ),
        );
        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();

        expect(
          bridge.asked.single,
          contains('dime qué reuniones tengo hoy'),
          reason: 'la instrucción es la que él redactó, no la del transcriptor',
        );
        expect(
          bridge.asked.single,
          isNot(contains('akeroniano')),
          reason:
              'y pasado el plazo tampoco va por detrás: hacer las dos cosas '
              'sería preguntar dos veces y pagarlo dos veces',
        );
        expect(registro.where((l) => l.contains('lo pasó')), hasLength(1));
      });
    });

    test('y si no lo pasa, va la transcripción pero marcada como tal', () {
      fakeAsync((async) {
        final session = _Session();
        final bridge = _Bridge();
        final registro = <String>[];
        final conversation = _conversation(
          session,
          bridge,
          log: registro.add,
          graciaDeLaRuta: const Duration(seconds: 10),
        );
        conversation().listen((_) {});
        async.flushMicrotasks();

        session.emit(
          const VoiceUserTranscript('Este akeroniano es tengo para hoy'),
        );
        session.emit(const VoiceTurnCompleted());
        async
          ..elapse(const Duration(seconds: 11))
          ..flushMicrotasks();

        expect(
          bridge.asked.single,
          contains('transcripción automática'),
          reason:
              'sin decirle de dónde salió, «akeroniano» es una pregunta '
              'absurda; con la marca es una frase mal oída que se interpreta',
        );
        expect(
          bridge.asked.single,
          contains('Este akeroniano es tengo para hoy'),
        );
        expect(
          registro.where((l) => l.contains('no lo pasó ni pidiéndoselo')),
          hasLength(1),
          reason: 'y se cuenta, para saber si pedírselo sirve de algo',
        );
      });
    });
  });

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

      // 🔴 Se filtran las notas: ahora la primera cosa que se le manda es
      // «pásalo tú», y esa **sí** tiene que estar. Lo que no puede llegar es la
      // corrección con la respuesta de Claude, que es la que interrumpe.
      expect(
        session.notes.where((nota) => nota.contains('Esto lo ha respondido')),
        isEmpty,
        reason:
            'la respuesta del turno 1 llegó cuando ya se hablaba del 2: '
            'entregarla hace que el modelo abandone lo que está diciendo',
      );
      expect(
        session.notes.where((nota) => nota == VoiceRouting.pasaloTu),
        hasLength(1),
        reason: 'y antes de nada se le pidió a él, que es quien te oyó',
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

      // Dos notas y en este orden: primero se le pide que lo pase él, y solo
      // al no hacerlo llega la corrección con lo que dijo Claude.
      expect(session.notes.first, VoiceRouting.pasaloTu);
      expect(session.notes.last, contains('dame un resumen de gitflow'));
      expect(session.notes, hasLength(2));

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
        _Agenda(),
        graciaDeLaRuta: Duration.zero,
        const SinEnrutar(),
        () => null,
        () => true,
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
      _Agenda(),
      graciaDeLaRuta: Duration.zero,
      const SinEnrutar(),
      () => null,
      () => true,
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
      _Agenda(),
      const SinEnrutar(),
      () => null,
      () => true,
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

  // 🔴 «¿Qué reuniones tengo hoy?» **no vuelve a Claude.** La app ya leyó el
  // calendario para poder avisar, así que mandar un encargo para releer lo
  // mismo cuesta un minuto de espera y tokens, y devuelve lo que ya está en
  // memoria.
  group('la agenda se contesta de memoria', () {
    /// 🔴 **Contestar de memoria no puede matar la sesión.**
    ///
    /// Se vio pidiendo la agenda por voz: dijo «consulto tu agenda, Argonauta»
    /// y se quedó ahí. La lectura es instantánea y no pasa por `runErrand`, así
    /// que ni `abortErrand` ni los eventos de Claude tocaban el reloj de
    /// inactividad — **nada lo reiniciaba**. Y al modelo todavía le quedaba lo
    /// que más tarda: generar la respuesta hablada, medido entre 5 y 11 s en
    /// esta máquina. El plazo ganaba la carrera y la sesión se cerraba con la
    /// respuesta a medio generar.
    test('y contestarla reinicia el reloj, o la respuesta muere sin nacer', () {
      fakeAsync((async) {
        final session = _Session();
        final registro = <String>[];
        final agenda = _Agenda(
          'Hoy tienes una reunión:\n- 10:00 · Refinamiento',
        );
        final conversation = _conversation(
          session,
          _Bridge(),
          agenda: agenda,
          log: registro.add,
        );
        conversation().listen((_) {});
        async.flushMicrotasks();

        // El servicio ya habló —anunció que iba a consultar— así que el plazo
        // corto está en marcha desde este momento.
        session.emit(const VoiceSessionReady());
        session.emit(const VoiceReplyTranscript('consulto tu agenda'));
        async.flushMicrotasks();

        session.emit(
          const VoiceToolRequested(
            callId: 'c1',
            name: ClaudeErrand.agendaTool,
            arguments: <String, Object?>{},
          ),
        );
        async.flushMicrotasks();

        // Los 10 s que el modelo puede tardar en empezar a narrarla. El plazo
        // corto son 6, así que aquí se ve la diferencia: con él la sesión ya
        // está cerrada y no se oye nada.
        async
          ..elapse(const Duration(seconds: 10))
          ..flushMicrotasks();

        expect(agenda.seLaPidieron, 1);
        expect(
          registro.where((l) => l.contains('cierre por inactividad')),
          isEmpty,
          reason: 'se cerró mientras el modelo generaba la respuesta hablada',
        );

        // Y sigue siendo un plazo: si el modelo no narra nunca, la sesión no
        // se queda abierta con el micrófono puesto.
        async
          ..elapse(const Duration(seconds: 15))
          ..flushMicrotasks();
        expect(
          registro.where((l) => l.contains('cierre por inactividad')),
          hasLength(1),
        );
      });
    });

    /// 🔴 **Y tampoco puede matarla mientras se contesta, no solo mientras se
    /// narra.**
    ///
    /// La lectura no siempre está hecha: si la del arranque va en vuelo,
    /// `deHoy()` espera a que acabe, y esa es un `claude -p` con el conector de
    /// Calendar —32 s medidos—. Pasó a los 34 s de abrir la app: dijo «consulto
    /// tu agenda de hoy» y se quedó ahí. Reiniciar el reloj **al contestar** no
    /// alcanza para esto, porque para cuando hay algo que contestar la sesión
    /// lleva dieciocho segundos cerrada y el resultado se entrega a nadie.
    test('aunque la lectura tarde más que el plazo entero', () {
      fakeAsync((async) {
        final session = _Session();
        final registro = <String>[];
        final agenda = _Agenda(
          'Hoy tienes una reunión:\n- 10:00 · Refinamiento',
          const Duration(seconds: 32),
        );
        final conversation = _conversation(
          session,
          _Bridge(),
          agenda: agenda,
          log: registro.add,
        );
        conversation().listen((_) {});
        async.flushMicrotasks();

        session.emit(const VoiceSessionReady());
        session.emit(const VoiceReplyTranscript('consulto tu agenda de hoy'));
        async.flushMicrotasks();

        session.emit(
          const VoiceToolRequested(
            callId: 'c1',
            name: ClaudeErrand.agendaTool,
            arguments: <String, Object?>{},
          ),
        );
        async
          ..elapse(const Duration(seconds: 32))
          ..flushMicrotasks();

        expect(
          registro.where((l) => l.contains('cierre por inactividad')),
          isEmpty,
          reason: 'se cerró mientras se leía lo que ella misma había pedido',
        );
        expect(
          session.toolResults.single,
          contains('Refinamiento'),
          reason:
              'la agenda llegó a una sesión ya cerrada, y no la narró nadie',
        );

        // Y después de contestar sigue mandando el plazo: lo que queda es la
        // narración, no una sesión abierta para siempre.
        async
          ..elapse(const Duration(seconds: 25))
          ..flushMicrotasks();
        expect(
          registro.where((l) => l.contains('cierre por inactividad')),
          hasLength(1),
        );
      });
    });

    /// 🔴 **Y se anuncia como lo que es, no como un encargo.**
    ///
    /// Con la pareja de eventos de un encargo, quien escucha corre la cola de
    /// después de uno: releer la rama, buscar el documento que salió, comprimir
    /// el contexto, avisar de que ya está. Nada de eso aplica a una lectura de
    /// memoria — y «buscar el documento que salió» colgó un resumen viejo de la
    /// respuesta a «¿qué reuniones tengo hoy?», porque la marca de qué había
    /// antes se toma sin esperarla y la agenda contesta antes de que esté.
    ///
    /// Aquí se fija la causa, y aquí es determinista: lo que se mide es **qué
    /// evento sale**, no quién gana una carrera.
    test('y se anuncia como una lectura, no como un encargo', () async {
      final session = _Session();
      final vistos = <VoiceEvent>[];
      final conversation = _conversation(
        session,
        _Bridge(),
        agenda: _Agenda('Hoy tienes cinco reuniones.'),
      );

      final sub = conversation().listen(vistos.add);
      await Future<void>.delayed(Duration.zero);
      session.emit(
        const VoiceToolRequested(
          callId: 'c1',
          name: ClaudeErrand.agendaTool,
          arguments: <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        vistos.whereType<VoiceLookupStarted>().single.headline,
        'La agenda de hoy',
        reason: 'sin titular, treinta segundos de espera no se explican solos',
      );
      expect(
        vistos.whereType<VoiceToolStarted>(),
        isEmpty,
        reason:
            'anunciarlo como encargo arrastra toda la cola de después de '
            'uno, y esto no toca el repositorio ni produce documentos',
      );
      expect(vistos.whereType<VoiceToolFinished>(), isEmpty);
      await sub.cancel();
    });

    test('preguntarla no manda ningún encargo a Claude', () async {
      final session = _Session();
      final bridge = _Bridge();
      final agenda = _Agenda('Hoy tienes una reunión:\n- 10:00 · Refinamiento');
      final conversation = _conversation(session, bridge, agenda: agenda);

      final sub = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      session.emit(
        const VoiceToolRequested(
          callId: 'c1',
          name: ClaudeErrand.agendaTool,
          arguments: <String, Object?>{},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(agenda.seLaPidieron, 1);
      expect(
        bridge.asked,
        isEmpty,
        reason: 'releer lo que ya está en memoria cuesta tokens y un minuto',
      );
      expect(session.toolResults.single, contains('Refinamiento'));
      await sub.cancel();
    });

    // Sin agenda que mirar se dice tal cual: contestar «no tienes nada» cuando
    // en realidad no se ha mirado sería mentir con cara de dato.
    test(
      'sin avisos configurados lo dice, en vez de decir que no hay nada',
      () async {
        final session = _Session();
        final conversation = _conversation(
          session,
          _Bridge(),
          agenda: _Agenda(),
        );

        final sub = conversation().listen((_) {});
        await Future<void>.delayed(Duration.zero);
        session.emit(
          const VoiceToolRequested(
            callId: 'c1',
            name: ClaudeErrand.agendaTool,
            arguments: <String, Object?>{},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(session.toolResults.single, contains('Ajustes'));
        await sub.cancel();
      },
    );
  });
  // 🔴 **El enrutado por voz, que es de donde salió la idea.**
  //
  // Se cableó primero dentro de `submit`, y hablando **no se pasa por
  // `submit`**: esta clase llama al puente de Claude directamente. Resultado:
  // «en el front mobile, arregla el login» funcionaba escribiendo y no
  // hablando. Ahora el despacho entra por el constructor.
  group('a qué carpeta va lo que se dice', () {
    test('lo que no nombra carpeta se atiende aquí, tal cual', () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = _conversation(session, bridge);
      final events = conversation().listen((_) {});
      addTearDown(events.cancel);
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: 'c1',
          name: ClaudeErrand.askTool,
          arguments: <String, Object?>{'instruccion': 'arregla el login'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bridge.asked.single, contains('arregla el login'));
    });

    test('nombrar otra carpeta se lo lleva, y no se trabaja aquí', () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = _conversation(
        session,
        bridge,
        despacho: const _SeLoLleva('front-mobile-b2c'),
      );
      final events = conversation().listen((_) {});
      addTearDown(events.cancel);
      await Future<void>.delayed(Duration.zero);

      session.emit(
        const VoiceToolRequested(
          callId: 'c1',
          name: ClaudeErrand.askTool,
          arguments: <String, Object?>{
            'instruccion': 'en el front mobile b2c, arregla el login',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        bridge.asked,
        isEmpty,
        reason: 'el trabajo es de la otra conversación, no de esta',
      );
      // Y se le dice al modelo, que si no la voz se queda callada y parece que
      // no pasó nada.
      expect(session.toolResults.single, contains('front-mobile-b2c'));
    });
  });
  // 🔴 **La frase de escritura también sujeta hablando.**
  //
  // El canal aplica su mitad del permiso en `sendErrand` —lo que se escribe
  // desde el teléfono— pero el móvil también puede **abrir la voz del Mac** con
  // `startVoice`. Por ahí el encargo llegaba a Claude sin tope, con el valor por
  // defecto: `true`. O sea que un teléfono en solo lectura conseguía que Claude
  // escribiera **hablando en vez de escribiendo**, que es exactamente lo que esa
  // frase existe para impedir.
  group('el tope de escritura, hablando', () {
    Future<void> pedir(_Session session) async {
      await Future<void>.delayed(Duration.zero);
      session.emit(
        const VoiceToolRequested(
          callId: 'c1',
          name: ClaudeErrand.askTool,
          arguments: <String, Object?>{'instruccion': 'escribe el archivo'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    test('con la frase abierta, la carpeta manda', () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = _conversation(
        session,
        bridge,
        laCarpetaDeja: true,
        puedeEscribir: true,
      );
      final events = conversation().listen((_) {});
      addTearDown(events.cancel);

      await pedir(session);

      expect(bridge.conEdicion, [true]);
    });

    test('sin la frase, no se escribe aunque la carpeta deje', () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = _conversation(
        session,
        bridge,
        laCarpetaDeja: true,
        puedeEscribir: false,
      );
      final events = conversation().listen((_) {});
      addTearDown(events.cancel);

      await pedir(session);

      expect(
        bridge.conEdicion,
        [false],
        reason:
            'es un tope: baja lo que la carpeta concede, y hablando tiene que '
            'bajar igual que escribiendo',
      );
    });
  });
}

/// La agenda ya leída: es lo que hace que preguntarla no vuelva a Claude.
class _Agenda implements LaAgendaDeHoy {
  _Agenda([this.respuesta, this.tarda = Duration.zero]);

  /// `null` es «no hay agenda que mirar»: avisos apagados o sin carpeta.
  final String? respuesta;

  /// Lo que cuesta contestar.
  ///
  /// 🔴 Contestar al momento era **el único caso que se estaba probando**, y es
  /// el que no falla. Cuando la lectura del día está en vuelo, `deHoy()` espera
  /// a que acabe — y esa es un `claude -p` con el conector de Calendar.
  final Duration tarda;

  var seLaPidieron = 0;

  @override
  Future<String?> deHoy() async {
    seLaPidieron++;
    if (tarda > Duration.zero) await Future<void>.delayed(tarda);
    return respuesta;
  }
}

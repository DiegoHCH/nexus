import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

/// El socket, detrás de una interfaz.
///
/// Existe para poder probar el enlace **sin red**: lo que hay que ejercitar aquí es
/// la reconexión y el resync, y provocarlos de verdad significaría cortar el wifi a
/// mano en cada prueba. Con esto, «se cayó la conexión» es una línea.
abstract class ChannelSocket {
  Stream<String> get entrantes;
  void enviar(String texto);
  Future<void> close();
}

/// El socket de verdad.
class WebSocketChannelSocket implements ChannelSocket {
  WebSocketChannelSocket(this._ws);

  /// Abre con el token **en la cabecera**, nunca en la URL: las URLs acaban en
  /// registros —decisión 2.1 del contrato— y la cabecera estándar es la que los
  /// proxies y los registros ya saben redactar.
  static Future<ChannelSocket> conectar({
    required Uri url,
    required String token,
    Duration plazo = const Duration(seconds: 10),
  }) async {
    try {
      final ws = await WebSocket.connect(
        url.toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      ).timeout(plazo);
      return WebSocketChannelSocket(ws);
    } on WebSocketException {
      // **Algo contestó y no aceptó el upgrade.** Eso ya distingue lo importante: la
      // red llega, así que el problema es el portero.
      //
      // Y el código de estado no viene en la excepción —`dart:io` lanza un
      // `WebSocketException` con un mensaje que no lo incluye— así que se pregunta
      // otra vez con una petición normal. Es una petición de más **solo cuando ya
      // falló**, y es lo que convierte «reconectando» en «vuelve a copiar el token».
      throw ChannelRefused(await _porQue(url, token, plazo));
    } on SocketException {
      // No se pudo abrir el socket: no hay ruta. En este canal casi siempre significa
      // que falta Tailscale en este aparato — que es el precio escrito de escuchar
      // solo ahí, y lo que ninguna pantalla decía.
      throw const ChannelUnreachable();
    } on TimeoutException {
      throw const ChannelUnreachable();
    }
  }

  /// Pregunta el estado con una petición normal, para poder decir por qué.
  static Future<int?> _porQue(Uri url, String token, Duration plazo) async {
    final cliente = HttpClient()..connectionTimeout = plazo;
    try {
      final peticion = await cliente.getUrl(
        url.replace(scheme: url.scheme == 'wss' ? 'https' : 'http'),
      );
      peticion.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final respuesta = await peticion.close().timeout(plazo);
      await respuesta.drain<void>();
      return respuesta.statusCode;
    } on Object {
      // Si esto también falla, se contesta sin código: se sabe que algo hay al otro
      // lado —el upgrade obtuvo respuesta— y no se sabe qué dijo. Mejor eso que
      // inventarse un motivo.
      return null;
    } finally {
      cliente.close(force: true);
    }
  }

  final WebSocket _ws;

  @override
  Stream<String> get entrantes =>
      _ws.where((dynamic d) => d is String).cast<String>();

  @override
  void enviar(String texto) => _ws.add(texto);

  @override
  Future<void> close() async {
    try {
      await _ws.close();
    } on Object {
      // Cerrar lo que ya está cerrado no es un problema que nadie deba atender.
    }
  }
}

/// El Mac contestó y no dejó entrar.
///
/// Con el código, cuando se pudo averiguar: un 403 es el portero —token o dirección—
/// y un 426 es «autenticado pero esto no es un WebSocket», que solo pasa con un
/// cliente mal escrito.
class ChannelRefused implements Exception {
  const ChannelRefused(this.status);

  final int? status;

  @override
  String toString() => 'ChannelRefused(${status ?? "sin código"})';
}

/// No se llegó al Mac.
class ChannelUnreachable implements Exception {
  const ChannelUnreachable();
}

/// En qué anda el enlace. Son los cuatro estados que pide la ficha `lo6`, más el
/// final del que no se sale reintentando.
enum LinkState {
  sinConexion,
  conectando,
  conectado,

  /// Se cayó y se está volviendo a intentar.
  reconectando,

  /// Conectado y pidiendo lo que se perdió.
  resincronizando,

  /// Uno de los dos extremos es demasiado viejo. **Terminal**: reintentar no lo
  /// arregla, y reintentar en bucle es lo que convierte un mensaje claro en una app
  /// que parece colgada.
  hayQueActualizar,

  /// El Mac contestó y no dejó entrar. Casi siempre: el token no es, o la dirección
  /// no es la que el portero espera.
  ///
  /// **No es terminal**, y esa fue la decisión difícil: el portero contesta el mismo
  /// 403 cuando el token está mal y cuando se gastó el límite de intentos, así que
  /// darse por vencido dejaría clavado a un teléfono que solo tenía que esperar. Se
  /// sigue reintentando **despacio** y se dice qué comprobar.
  rechazado,

  /// No se llegó. En este canal casi siempre es que falta Tailscale en el teléfono.
  noSeLlega,
}

/// Por qué falló una petición.
enum LinkFailure {
  /// No llegó el `ack`. **La petición pudo no llegar**, así que reintentarla es
  /// seguro — y con el mismo `clientMsgId` si muta algo.
  sinConfirmacion,

  /// Llegó el `ack` y nunca el resultado. Reintentar **no** sirve: ya está en el
  /// Mac, y el deduplicador contestaría «duplicada» sin volver a ejecutarla.
  sinRespuesta,

  /// El Mac contestó que no. El motivo va en [LinkError.code].
  rechazada,

  /// No hay enlace.
  desconectado,
}

class LinkError implements Exception {
  const LinkError(this.failure, {this.code, this.message});

  final LinkFailure failure;

  /// El código del contrato —`unknownConversation`, `wrongPhrase`…— cuando el Mac
  /// contestó. `null` cuando el fallo fue del enlace.
  final String? code;
  final String? message;

  @override
  String toString() =>
      'LinkError(${failure.name}${code == null ? '' : ' · $code'})';
}

/// El lado del teléfono: saluda, pide, escucha y se recupera.
///
/// **Todo lo de aquí es Dart puro**, sin un widget ni un provider, y eso es a
/// propósito: lo que puede romperse en esta pieza son los tiempos y el orden —qué
/// pasa si el `ack` no llega, si llega dos veces, si vuelve la conexión con un hueco
/// en la numeración— y esas cosas no se prueban tocando una pantalla.
class ChannelLink {
  ChannelLink({
    required this.abrir,
    required this.appVersion,
    this.protocolo = ProtocolRange.mine,
    this.plazoDelSaludo = const Duration(seconds: 10),
    this.plazoDelAck = const Duration(seconds: 5),
    this.plazoDeLaRespuesta = const Duration(seconds: 30),
    List<Duration>? esperas,
    Future<void> Function(Duration)? dormir,
    String Function()? idNuevo,
  }) : esperas = esperas ?? _esperasPorDefecto,
       _dormir = dormir ?? Future<void>.delayed,
       _idNuevo = idNuevo ?? _idPorDefecto;

  /// Cómo se abre un socket. Inyectable por lo mismo que [ChannelSocket].
  final Future<ChannelSocket> Function() abrir;

  final String appVersion;
  final ProtocolRange protocolo;

  final Duration plazoDelSaludo;

  /// Cuánto se espera la confirmación. **Corto**, porque el `ack` sale del Mac
  /// antes de ejecutar nada: si tarda, no es que el encargo sea largo, es que el
  /// mensaje no llegó.
  final Duration plazoDelAck;

  /// Y cuánto la respuesta. Largo, porque hay métodos que leen del disco.
  final Duration plazoDeLaRespuesta;

  /// Cuánto esperar entre reintentos de conexión.
  ///
  /// Creciente y **con tope**: un móvil que sale del metro tiene que reconectar
  /// rápido, y uno con el Mac apagado no puede estar despertando la radio cada
  /// segundo — eso es la batería.
  final List<Duration> esperas;

  static const _esperasPorDefecto = [
    Duration(milliseconds: 500),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  final Future<void> Function(Duration) _dormir;
  final String Function() _idNuevo;

  static var _contador = 0;
  static String _idPorDefecto() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_contador++}';

  final _estado = StreamController<LinkState>.broadcast();
  final _eventos = StreamController<Event>.broadcast();
  final _fotos = StreamController<Snapshot>.broadcast();

  /// En qué anda.
  Stream<LinkState> get estado => _estado.stream;

  /// Lo que va pasando en el Mac.
  Stream<Event> get eventos => _eventos.stream;

  /// El estado entero, cuando el resync no se pudo hacer con eventos.
  Stream<Snapshot> get fotos => _fotos.stream;

  LinkState _ahora = LinkState.sinConexion;
  LinkState get ahora => _ahora;

  /// El último evento visto. De aquí sale el `Resume` al reconectar.
  int _ultimoSeq = 0;
  int get ultimoSeq => _ultimoSeq;

  /// El código con el que el Mac rechazó, si lo hubo. Para poder decirlo.
  int? ultimoRechazo;

  final _acento = StreamController<int>.broadcast();

  /// El acento que eligió el Mac, cada vez que se saluda.
  ///
  /// Un `Stream` y no un valor porque **llega en cada conexión**: cambiar el acento en
  /// el escritorio tiene que alcanzar al teléfono en su siguiente saludo, sin que
  /// nadie lo pida.
  Stream<int> get acento => _acento.stream;

  ChannelSocket? _socket;
  StreamSubscription<String>? _escucha;

  /// Las peticiones en vuelo, por su id.
  final _enVuelo = <String, _Pendiente>{};

  Completer<void>? _saludo;
  var _quiereEstarConectado = false;
  var _cerrado = false;

  Future<void> conectar() async {
    if (_cerrado) throw StateError('el enlace ya se cerró');
    _quiereEstarConectado = true;
    await _intentar(desdeCero: true);
  }

  /// Se desconecta **y deja de reintentar**. Lo segundo importa: sin eso, cerrar la
  /// pantalla dejaría un bucle de reconexión vivo gastando radio.
  Future<void> desconectar() async {
    _quiereEstarConectado = false;
    await _tirarSocket();
    _pasarA(LinkState.sinConexion);
  }

  Future<void> cerrar() async {
    _cerrado = true;
    await desconectar();
    for (final p in _enVuelo.values) {
      p.fallar(const LinkError(LinkFailure.desconectado));
    }
    _enVuelo.clear();
    await _estado.close();
    await _eventos.close();
    await _fotos.close();
    await _acento.close();
  }

  /// Pide algo y espera la respuesta.
  ///
  /// [clientMsgId] se pasa **cuando se reintenta algo que muta**: es lo que hace que
  /// el Mac lo reconozca como reenvío y no lo ejecute dos veces. Para una lectura no
  /// se reusa —ver [reintentable]— porque el deduplicador protege efectos, no
  /// respuestas.
  Future<Map<String, Object?>> pedir(
    RemoteMethod metodo, {
    Map<String, Object?> params = const {},
    String? clientMsgId,
  }) {
    final socket = _socket;
    if (socket == null || _ahora != LinkState.conectado) {
      return Future.error(const LinkError(LinkFailure.desconectado));
    }

    final id = clientMsgId ?? _idNuevo();
    final pendiente = _Pendiente(id: id, metodo: metodo);
    _enVuelo[id] = pendiente;

    socket.enviar(Call(id: id, method: metodo.name, params: params).encode());

    // Dos plazos y no uno, y la diferencia es lo único que dice si se puede
    // reintentar. Sin `ack` la petición pudo no llegar; con `ack` y sin respuesta,
    // llegó — y reintentarla solo conseguiría un «duplicada».
    pendiente.armarPlazoDelAck(plazoDelAck, () {
      _enVuelo.remove(id);
      pendiente.fallar(const LinkError(LinkFailure.sinConfirmacion));
    });
    pendiente.plazoTotal = Timer(plazoDeLaRespuesta, () {
      _enVuelo.remove(id);
      pendiente.fallar(const LinkError(LinkFailure.sinRespuesta));
    });

    return pendiente.futuro;
  }

  /// Si reintentar con **el mismo** id es lo correcto.
  ///
  /// Solo para lo que muta. El deduplicador del Mac protege **efectos**, no
  /// respuestas: reenviar una lectura con el mismo id devuelve «duplicada» y ninguna
  /// respuesta, así que una consulta perdida se vuelve a pedir con id nuevo. Meterlas
  /// en el mismo saco es la forma de que consultar deje de funcionar tras un corte.
  static bool reintentable(RemoteMethod metodo) => switch (metodo) {
    // Lo que **cambia algo en el Mac**: el mismo id lo protege de correr dos veces.
    // Abrir y retomar una conversación entran aquí porque crean estado — reenviarlas
    // con id nuevo abriría dos conversaciones sobre la misma carpeta.
    RemoteMethod.sendErrand ||
    RemoteMethod.stopErrand ||
    RemoteMethod.unlockWrites ||
    RemoteMethod.openConversation ||
    RemoteMethod.resumeConversation => true,
    // Lo que solo **lee**: una consulta perdida se vuelve a pedir con id nuevo,
    // porque el deduplicador protege efectos y no respuestas.
    RemoteMethod.conversations ||
    RemoteMethod.history ||
    RemoteMethod.meter ||
    RemoteMethod.permission ||
    RemoteMethod.archive ||
    RemoteMethod.folders ||
    RemoteMethod.artifacts ||
    RemoteMethod.artifact => false,
  };

  // ──────────────────────────── por dentro ────────────────────────────

  Future<void> _intentar({bool desdeCero = false}) async {
    var intento = 0;
    while (_quiereEstarConectado && !_cerrado) {
      _pasarA(
        desdeCero && intento == 0
            ? LinkState.conectando
            : LinkState.reconectando,
      );
      try {
        final socket = await abrir();
        _socket = socket;
        _escucha = socket.entrantes.listen(
          _recibir,
          onDone: _seCayo,
          onError: (Object _) => _seCayo(),
          cancelOnError: true,
        );
        await _saludar(socket);
        return;
      } on _VersionIncompatible {
        // Terminal: no se reintenta. Reintentar aquí sería pedirle a la red que
        // arregle un problema de versiones.
        _pasarA(LinkState.hayQueActualizar);
        await _tirarSocket();
        return;
      } on Object catch (error) {
        debugPrint('el enlace no pudo conectar: $error');
        await _tirarSocket();
        if (!_quiereEstarConectado || _cerrado) return;

        // **Aquí está el arreglo.** Antes todo fallo era el mismo «reconectando», y
        // «no tengo Tailscale» y «el token no es» pedían cosas distintas: una es
        // instalar algo y la otra volver a emparejar. Sin distinguirlas, la pantalla
        // no podía decir ninguna de las dos.
        _pasarA(switch (error) {
          ChannelRefused() => LinkState.rechazado,
          ChannelUnreachable() => LinkState.noSeLlega,
          _ => LinkState.reconectando,
        });
        ultimoRechazo = error is ChannelRefused ? error.status : null;

        // Un rechazo se reintenta **por el final de la escalera**: el portero limita
        // intentos por IP, así que insistir rápido con un token malo es la forma de
        // gastarse el cupo y quedarse fuera también cuando el token se arregle.
        final espera = error is ChannelRefused
            ? esperas.last
            : esperas[intento.clamp(0, esperas.length - 1)];
        await _dormir(espera);
        intento++;
      }
    }
  }

  Future<void> _saludar(ChannelSocket socket) async {
    final espera = _saludo = Completer<void>();
    socket.enviar(
      Hello(
        protocol: protocolo,
        peer: Peer.mobile,
        appVersion: appVersion,
      ).encode(),
    );
    await espera.future.timeout(
      plazoDelSaludo,
      onTimeout: () => throw TimeoutException('el Mac no saludó'),
    );
  }

  void _recibir(String crudo) {
    final Frame marco;
    try {
      marco = Frame.decode(crudo);
    } on FormatException catch (error) {
      // Un mensaje roto no tira el enlace: se anota y se sigue. Lo que sí cerraría
      // la conexión es dejar de leer.
      debugPrint('mensaje roto del Mac: ${error.message}');
      return;
    }

    switch (marco) {
      case Welcome(:final seq, :final accent):
        if (accent != null && !_acento.isClosed) _acento.add(accent);
        // **El `seq` de la bienvenida dice si vamos al día sin pedir nada.** Si
        // coincide con lo último visto, no hay resync que hacer; si no, se pide.
        _pasarA(LinkState.conectado);
        _saludo?.complete();
        _saludo = null;
        if (seq != _ultimoSeq) _pedirLoQueFalta();

      case UpgradeRequired():
        _saludo?.completeError(const _VersionIncompatible());
        _saludo = null;

      case Ack(:final id, :final duplicate):
        final pendiente = _enVuelo[id];
        if (pendiente == null) return;
        pendiente.confirmado = true;
        pendiente.cancelarPlazoDelAck();
        if (duplicate) {
          // El Mac ya la tenía, así que **no va a llegar resultado**. Se resuelve
          // ahora en vez de esperar el plazo largo: quedarse esperando algo que no
          // viene es lo que se ve como «no responde».
          _enVuelo.remove(id);
          pendiente.resolver(const {'duplicate': true});
        }

      case Result(:final id, :final data):
        _enVuelo.remove(id)?.resolver(data);

      case Failure(:final id, :final code, :final message):
        if (id == null) {
          debugPrint('el Mac rechazó algo sin decir qué: $code');
          return;
        }
        _enVuelo
            .remove(id)
            ?.fallar(
              LinkError(LinkFailure.rechazada, code: code, message: message),
            );

      case Event():
        _recibirEvento(marco);

      case Snapshot(:final seq):
        _ultimoSeq = seq;
        _fotos.add(marco);
        _pasarA(LinkState.conectado);

      case Hello() || Call() || Resume():
        // Cosas que manda el teléfono, no el Mac. Si llegan, es un Mac mal escrito.
        debugPrint('el Mac mandó algo que no le toca: ${marco.runtimeType}');

      case UnknownFrame(:final type):
        // Un mensaje de una versión más nueva. **Se ignora y no se cae**: es lo que
        // permite que el Mac se actualice sin romper este teléfono.
        debugPrint('marco desconocido del Mac: $type');
    }
  }

  void _recibirEvento(Event evento) {
    if (evento.seq <= _ultimoSeq) {
      // Ya visto. Pasa al reconectar: el `Resume` puede solaparse con lo que ya
      // llegó, y aplicarlo dos veces duplicaría texto en la pantalla.
      return;
    }
    if (evento.seq > _ultimoSeq + 1) {
      // **Hueco.** Falta algo en medio, así que aplicar este evento dejaría la
      // pantalla con un agujero silencioso — y silencioso es lo peor, porque nadie
      // lo va a mirar. Se pide lo que falta y este se descarta: volverá en el
      // resync, en orden.
      _pedirLoQueFalta();
      return;
    }
    _ultimoSeq = evento.seq;
    _eventos.add(evento);
  }

  void _pedirLoQueFalta() {
    final socket = _socket;
    if (socket == null) return;
    _pasarA(LinkState.resincronizando);
    socket.enviar(Resume(lastSeq: _ultimoSeq).encode());
  }

  void _seCayo() {
    _socket = null;
    _escucha = null;

    // Las que estaban en vuelo se cierran **según hubieran sido confirmadas o no**,
    // que es la información que necesita quien las lanzó para decidir si reintenta.
    for (final pendiente in [..._enVuelo.values]) {
      _enVuelo.remove(pendiente.id);
      pendiente.fallar(
        LinkError(
          pendiente.confirmado
              ? LinkFailure.sinRespuesta
              : LinkFailure.sinConfirmacion,
        ),
      );
    }

    if (!_quiereEstarConectado || _cerrado) return;
    _pasarA(LinkState.reconectando);
    unawaited(_intentar());
  }

  Future<void> _tirarSocket() async {
    final escucha = _escucha;
    final socket = _socket;
    _escucha = null;
    _socket = null;
    await escucha?.cancel();
    await socket?.close();
  }

  void _pasarA(LinkState nuevo) {
    if (_ahora == nuevo || _estado.isClosed) return;
    _ahora = nuevo;
    _estado.add(nuevo);
  }
}

class _VersionIncompatible implements Exception {
  const _VersionIncompatible();
}

/// Una petición esperando respuesta.
class _Pendiente {
  _Pendiente({required this.id, required this.metodo});

  final String id;
  final RemoteMethod metodo;
  final _completer = Completer<Map<String, Object?>>();

  /// Si llegó el `ack`. Es lo que distingue «pudo no llegar» de «llegó y no
  /// contestó», y de eso depende si reintentar es seguro.
  var confirmado = false;

  Timer? _plazoDelAck;
  Timer? plazoTotal;

  Future<Map<String, Object?>> get futuro => _completer.future;

  void armarPlazoDelAck(Duration cuanto, void Function() alPasarse) {
    _plazoDelAck = Timer(cuanto, () {
      if (confirmado) return;
      alPasarse();
    });
  }

  void cancelarPlazoDelAck() {
    _plazoDelAck?.cancel();
    _plazoDelAck = null;
  }

  void resolver(Map<String, Object?> datos) {
    _cancelar();
    if (!_completer.isCompleted) _completer.complete(datos);
  }

  void fallar(LinkError error) {
    _cancelar();
    if (!_completer.isCompleted) _completer.completeError(error);
  }

  void _cancelar() {
    cancelarPlazoDelAck();
    plazoTotal?.cancel();
    plazoTotal = null;
  }
}

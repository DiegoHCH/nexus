import 'dart:async';
import 'dart:convert';
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

  /// La respuesta hablada, cuando la pregunta salió de este teléfono.
  ///
  /// Un `Stream` de bytes y no de marcos: lo que hay al otro lado es un altavoz, y
  /// darle el marco entero sería hacerle saber de transporte para nada.
  final _audio = StreamController<Uint8List>.broadcast();

  /// Trozos de la respuesta. Llegan **sin confirmación y sin número que sirva**: uno que
  /// llega tarde es peor que un hueco, porque mete en la frase medio segundo de hace un
  /// rato.
  Stream<Uint8List> get audio => _audio.stream;

  /// «Tira lo que te quede por sonar.» Llega cuando alguien interrumpe.
  final _descartar = StreamController<void>.broadcast();
  Stream<void> get descartar => _descartar.stream;

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
  ///
  /// 🔴 **Y despierta la espera en curso, que es la mitad que faltaba.** El bucle
  /// duerme entre reintentos hasta 30 segundos —el final de la escalera— y
  /// mientras duerme **tiene el guardia puesto**: apagar la bandera no lo saca de
  /// ahí, así que la siguiente llamada a [conectar] se encontraba el guardia y
  /// volvía en silencio sin abrir nada. Salía en desemparejar y emparejar otra
  /// vez con mala cobertura: media hora de «reconectando» que en realidad era
  /// medio minuto de nadie intentando nada, sin forma de acelerarlo.
  ///
  /// Despertándola, el bucle mira la bandera, ve que ya no se quiere estar
  /// conectado, sale y suelta el guardia — que es lo que deja volver a intentar.
  Future<void> desconectar() async {
    _quiereEstarConectado = false;
    _despierta();
    await _tirarSocket();
    _pasarA(LinkState.sinConexion);
  }

  /// Corta la espera entre reintentos, si hay alguna. Ver [reintentarYa].
  void _despierta() {
    final espera = _despertar;
    if (espera != null && !espera.isCompleted) espera.complete();
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
    await _audio.close();
    await _descartar.close();
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

  /// Manda un trozo de micrófono. **Sin esperar nada.**
  ///
  /// No pasa por `pedir` a propósito: eso registra la petición, arma dos plazos y
  /// espera confirmación, y aquí no hay nada que confirmar —el contrato del marco de
  /// audio dice que un trozo tarde es peor que un hueco—. Si no hay socket, el trozo se
  /// tira: es exactamente lo que hay que hacer con audio sin conexión.
  ///
  /// Devuelve si salió, para que quien captura pueda darse cuenta de que está hablando
  /// contra una pared.
  bool mandarAudio(Audio marco) {
    final socket = _socket;
    if (socket == null || ahora != LinkState.conectado) return false;
    socket.enviar(marco.encode());
    return true;
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
    // Callar es un efecto y se reintenta con el mismo id: callar dos veces es lo mismo
    // que callar una, y perder el aviso deja al Mac mandando audio que nadie oye.
    RemoteMethod.silenceReply ||
    RemoteMethod.unlockWrites ||
    RemoteMethod.openConversation ||
    RemoteMethod.resumeConversation ||
    // Renombrar y cerrar también cambian algo. Los dos son **idempotentes** —el mismo
    // nombre dos veces es el mismo nombre, y cerrar lo ya cerrado deja lo mismo— así
    // que reintentar con el mismo id es seguro y además correcto: con id nuevo, un
    // cierre perdido se quedaría sin hacer.
    RemoteMethod.renameConversation ||
    RemoteMethod.closeConversation ||
    // Abrir y cerrar el micrófono cambian algo en el Mac, y los dos son idempotentes:
    // abrir dos veces es una sesión, cerrar lo cerrado es lo mismo. Con id nuevo, **un
    // cierre perdido dejaría el micrófono abierto**, que es el peor final de esta lista.
    RemoteMethod.startVoice ||
    RemoteMethod.stopVoice => true,
    // **Terminar de sonar es un hecho, no un efecto**, y por eso va abajo con las
    // lecturas aunque no lea nada: reintentado con el mismo id volvería «duplicada» y
    // ninguna respuesta, y el Mac se quedaría esperando un aviso que ya no se manda.
    // Con id nuevo el segundo intento sí le llega, y decirlo dos veces es inofensivo
    // porque lo único que provoca es dejar de esperar.
    // Lo que solo **lee**: una consulta perdida se vuelve a pedir con id nuevo,
    // porque el deduplicador protege efectos y no respuestas.
    RemoteMethod.playbackFinished ||
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

  /// Si ya hay un bucle de conexión corriendo.
  ///
  /// **Uno y solo uno.** Con dos, los dos escriben en `_socket`, en `_escucha` y en
  /// `_saludo`, y el último gana: el `Welcome` del socket que sí saludó le llega a un
  /// oyente que ya fue reemplazado, así que nadie pasa el estado a «conectado» y la
  /// pantalla se queda en «reconectando» **con la conexión funcionando**. Medido en el
  /// registro del Mac: una conexión pidiendo cosas y otra tirada a los 10 s por no
  /// saludar.
  ///
  /// Pasa al volver del fondo: el sistema corta el socket, `_seCayo` arranca un bucle,
  /// y lo que traiga a la app por delante —un reintento a mano, reabrirla— arranca
  /// otro.
  var _intentando = false;

  Future<void> _intentar({bool desdeCero = false}) async {
    // Ya hay un bucle: no se abre otro. Y **no se acorta su espera desde aquí**,
    // aunque la tentación es grande: probado, y lo que consigue es que el bucle
    // que ya estaba siga adelante con la bandera recién puesta y se coma otro
    // plazo del saludo entero. Para «inténtalo ya» está [reintentarYa], que es
    // lo que llama la app al volver del fondo.
    if (_intentando) return;
    _intentando = true;
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
        _intentando = false;
        return;
      } on _VersionIncompatible {
        // Terminal: no se reintenta. Reintentar aquí sería pedirle a la red que
        // arregle un problema de versiones.
        _pasarA(LinkState.hayQueActualizar);
        await _tirarSocket();
        _intentando = false;
        return;
      } on Object catch (error) {
        debugPrint('el enlace no pudo conectar: $error');
        await _tirarSocket();
        if (!_quiereEstarConectado || _cerrado) {
          _intentando = false;
          return;
        }

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

        // **Se puede acortar la espera desde fuera.** Volver del fondo a la app cae
        // casi siempre en medio de una espera larga —la escalera acaba en 30 s— y
        // quedarse mirando «reconectando» medio minuto se lee como colgado. Quien
        // sabe que hemos vuelto es la app, no el enlace, así que despierta a este.
        _despertar = Completer<void>();

        // Un rechazo se reintenta **por el final de la escalera**: el portero limita
        // intentos por IP, así que insistir rápido con un token malo es la forma de
        // gastarse el cupo y quedarse fuera también cuando el token se arregle.
        final espera = error is ChannelRefused
            ? esperas.last
            : esperas[intento.clamp(0, esperas.length - 1)];
        // Lo que ocurra primero: que pase la espera o que alguien nos despierte.
        await Future.any([_dormir(espera), _despertar!.future]);
        _despertar = null;
        intento++;
      }
      // Y al salir del `while` —ya no se quiere estar conectado, o se cerró— el
      // guardia se suelta igual: si no, no habría forma de volver a intentarlo.
      _intentando = false;
    }
  }

  /// Espera en curso entre reintentos, si hay alguna.
  Completer<void>? _despertar;

  /// **Reintenta ahora**, sin esperar a que acabe la escalera.
  ///
  /// Lo llama la app al volver del fondo: el sistema puede haber cortado el socket
  /// mientras estaba en segundo plano y, al volver, el enlace estaba casi siempre
  /// dormido en la espera de 30 segundos. Lo que se veía era «reconectando» clavado, y
  /// la única salida a mano era cancelar — que hasta ahora además desemparejaba.
  ///
  /// No fuerza nada si ya está conectado: acortar una espera que no existe no hace
  /// daño, pero tirar una conexión buena sí.
  void reintentarYa() {
    if (_cerrado || ahora == LinkState.conectado) return;
    if (_despertar != null && !_despertar!.isCompleted) {
      _despierta();
      return;
    }
    // Sin espera en curso: o está conectando —y entonces no hay nada que acortar— o
    // nadie lo intentó todavía.
    if (!_quiereEstarConectado) unawaited(conectar());
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
        //
        // Y `conectado` **solo se anuncia si no hay resync**. Antes se anunciaba
        // siempre y en la línea siguiente se pasaba a `resincronizando`: el aviso
        // duraba cero fotogramas, pero quien lo escucha —el espejo pide la lista al
        // conectar— actuaba justo cuando `pedir` ya rechazaba por no estar conectado.
        // Lo que se veía era «no pude preguntarle al Mac» con el Mac contestando
        // perfectamente. Un estado que se anuncia y se desmiente en el mismo bloque
        // no es un estado: es ruido con nombre.
        final alDia = seq == _ultimoSeq;
        if (alDia) _pasarA(LinkState.conectado);
        _saludo?.complete();
        _saludo = null;
        if (!alDia) _pedirLoQueFalta();

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

      case Audio(:final pcmBase64):
        // **El audio baja cuando la pregunta vino de aquí.** Antes se rechazaba, con el
        // motivo de que un teléfono que reprodujera sería «una segunda boca»; eso se
        // cae con la regla que lo sustituye —suena donde se preguntó, así que nunca
        // suenan los dos— y la prohibición era además más ancha que la `lo8` que
        // citaba: reproducir lo que manda el Mac no le da al teléfono ni una llave ni
        // una sesión propia.
        //
        // El base64 se deshace aquí y no en el altavoz, por lo mismo que al subir: el
        // altavoz recibe bytes y no sabe de transporte.
        if (!_audio.isClosed) _audio.add(base64Decode(pcmBase64));

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

    // **El resync servido con eventos también termina aquí.** `_pedirLoQueFalta` deja
    // el estado en `resincronizando`, y el Mac puede contestar de dos maneras: con un
    // `Snapshot` —que sí volvía a `conectado`— o con los eventos que faltan, que no
    // volvían de ninguna. El teléfono se quedaba en `resincronizando` para siempre:
    // la pantalla decía «buscando tu Mac» con el socket vivo y el saludo hecho, y
    // `pedir` y `mandarAudio` —que exigen `conectado`— rechazaban todo en silencio.
    //
    // Solo se veía con atraso: un teléfono al día no pide resync y se quedaba
    // conectado, así que el fallo esperaba a la primera reconexión con eventos
    // pendientes. Recibir un evento en orden **es** la prueba de que el canal
    // funciona, así que es aquí donde se dice.
    if (_ahora == LinkState.resincronizando) _pasarA(LinkState.conectado);

    // **El acento no es de ninguna conversación**, así que no va al espejo: el espejo
    // descarta lo que no lleva `conversation` y el cambio se perdería en silencio. Va
    // al mismo sitio que el del saludo, que es quien ya sabe pintarlo.
    //
    // Se cuenta en el `seq` igual que los demás —de ahí que esto vaya después de
    // apuntarlo— para que un teléfono que se reincorpora lo reciba en su resync en vez
    // de necesitar un camino aparte.
    // Una orden de reproducción, no un trozo de estado: **no va al espejo**, igual que
    // el acento. El espejo descarta lo que no lleva `conversation` y esto se perdería en
    // silencio — y además no describe cómo está nada, dice qué hacer ahora.
    if (evento.kind == 'playback') {
      if (evento.data['action'] == 'discard' && !_descartar.isClosed) {
        _descartar.add(null);
      }
      return;
    }

    if (evento.kind == 'accent') {
      final argb = evento.data['argb'];
      if (argb is int && !_acento.isClosed) _acento.add(argb);
      return;
    }

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
    // 🔴 **Y se corta el saludo que estuviera esperando.** Sin esto, tirar el
    // socket dejaba vivo un `await` de **diez segundos** —el plazo del saludo—
    // con el guardia puesto: el enlace no estaba reintentando ni conectado, y
    // ni desconectar ni pedir conexión lo movían. Se ve como «reconectando»
    // clavado, y es el mismo silencio que ya costó una tarde con los dos
    // bucles. Medido: cada intento sin saludo cuesta diez segundos de nada.
    _cortarElSaludo();
    await escucha?.cancel();
    await socket?.close();
  }

  /// Corta el saludo en vuelo, si lo hay: el `await` de [_saludar] falla ya y
  /// quien esté en el bucle decide qué hacer con la bandera en la mano.
  void _cortarElSaludo() {
    final saludo = _saludo;
    _saludo = null;
    if (saludo != null && !saludo.isCompleted) {
      saludo.completeError(const LinkError(LinkFailure.desconectado));
    }
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

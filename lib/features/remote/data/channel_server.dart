import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/remote/domain/access_log.dart';
import 'package:nexus/features/remote/domain/dispatcher.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/gatekeeper.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

/// El socket del canal: acepta al teléfono, o no lo acepta.
///
/// Escucha **solo en la dirección que se le da**, y quien se la da —el proveedor—
/// solo tiene una de Tailscale o no arranca nada. La separación es para poder
/// probarlo: una prueba levanta esto en `127.0.0.1`, que es justo la dirección que
/// la política prohíbe en producción.
///
/// Lo que hace y lo que no: autentica, negocia la versión, y pasa las peticiones
/// al [Dispatcher]. **No sabe qué hace cada método** — eso es del despacho, que no
/// sabe qué es un socket.
class ChannelServer {
  ChannelServer({
    required this.gatekeeper,
    this.audio,
    required this.log,
    this.despacho,
    this.snapshot,
    this.acento,
    this.registro,
    this.diario,
    ProtocolRange? protocolo,
  }) : protocolo = protocolo ?? ProtocolRange.mine;

  final Gatekeeper gatekeeper;

  /// Dónde entra el micrófono del teléfono, si hay alguien escuchándolo.
  ///
  /// Un gancho y no una dependencia: el servidor mueve marcos y no tiene por qué
  /// saber qué es el audio ni quién lo usa.
  final void Function(Audio)? audio;

  /// Quien atiende los métodos.
  ///
  /// Opcional porque las pruebas del portero y de la negociación no necesitan la
  /// app entera detrás para comprobar quién entra. Sin él, una petición se contesta
  /// con un error honesto en vez de quedarse sin respuesta.
  final Dispatcher? despacho;

  /// Los eventos que ya se emitieron, para poder decir en la bienvenida por dónde
  /// va la numeración.
  final EventLog log;

  /// El acento elegido en este Mac, en ARGB.
  ///
  /// Una función y no un valor: se lee **al saludar**, así que un teléfono que
  /// reconecta después de cambiarlo recoge el nuevo. Con un valor fijo se congelaría
  /// al encender el canal, que es el mismo error que meterlo en el QR.
  final int Function()? acento;

  /// El estado entero, para quien pide desde un `seq` que ya se tiró.
  ///
  /// Una función y no el puente: el servidor no tiene por qué saber de dónde sale la
  /// foto, y así las pruebas del portero siguen sin necesitar la app detrás.
  final Snapshot Function()? snapshot;

  /// Dónde anotar lo que pasa **para depurar durante el desarrollo**.
  ///
  /// Sigue existiendo porque en `flutter run` es lo cómodo. Lo que no es, es el
  /// registro de la 2.5: en release no llega a ninguna parte —medido— así que el
  /// registro de verdad es [diario].
  final void Function(String)? registro;

  /// El registro append-only de la decisión 2.5.
  ///
  /// Aparte del [registro] porque son dos cosas distintas con el mismo nombre: uno es
  /// para mirar mientras se programa y el otro es para poder contestar «por qué me
  /// rechazó» un mes después.
  final AccessLog? diario;

  final ProtocolRange protocolo;

  HttpServer? _http;
  final _conexiones = <ChannelClient>[];

  /// Cuántos teléfonos caben dentro a la vez.
  ///
  /// Cuatro es más de lo que necesita ningún montaje real —un teléfono, una
  /// tableta, y sitio de sobra para una reconexión que todavía no se ha
  /// enterado de que la anterior murió—, y a la vez es un número.
  ///
  /// Sin tope, la lista crecía sin límite. Es post-autenticación, así que solo
  /// importa si el token se filtra o alguien se lleva el teléfono desbloqueado
  /// —que es exactamente el escenario contra el que se diseñó la frase de
  /// escritura—: en esa ventana, abrir conexiones era hinchar el proceso.
  static const maxConexiones = 4;

  /// La cabecera del token: `Authorization: Bearer …`.
  ///
  /// La estándar y no una propia, y no por elegancia: los registros y los proxies
  /// **ya saben** que `Authorization` se redacta. Una cabecera inventada como
  /// `X-Nexus-Token` viaja sin que nada la reconozca como secreta, y acaba escrita
  /// entera en el primer sitio que registre cabeceras.
  static const cabeceraToken = HttpHeaders.authorizationHeader;

  /// Los que están dentro ahora mismo. De aquí sale la lista de la decisión 2.7.
  List<ChannelClient> get clientes => List.unmodifiable(_conexiones);

  bool get escuchando => _http != null;

  int? get puerto => _http?.port;

  void _anotar(String que, {String? ip, String? motivo, String? detalle}) {
    registro?.call([que, ?ip, ?motivo, ?detalle].join(' '));
    diario?.anotar(
      AccessEntry(
        cuando: DateTime.now(),
        que: que,
        ip: ip,
        motivo: motivo,
        detalle: detalle,
      ),
    );
  }

  /// Manda un evento a todos los que están dentro **y ya saludaron**.
  ///
  /// Lo segundo importa: un evento antes de la bienvenida llegaría a un cliente que
  /// todavía no sabe qué versión se habla, y es lo que convierte un handshake en
  /// papel mojado.
  void difundir(Event evento) {
    for (final cliente in _conexiones) {
      if (cliente.saludado) cliente.enviar(evento);
    }
  }

  /// Manda un trozo de audio a quien esté dentro.
  ///
  /// Aparte de [difundir] y no como un evento más: **el audio no se numera ni se
  /// guarda**. Un teléfono que se reincorpora no quiere que le repitan medio segundo de
  /// hace un rato —eso es lo que decidió el marco propio para la voz que sube— y meterlo
  /// en el registro haría que el resync lo arrastrara.
  ///
  /// Si no hay nadie saludado, se cae al suelo en silencio. Es lo correcto: quien
  /// reproduce ya no está, y quien lo mandaba se entera por su propio camino.
  void difundirAudio(Audio marco) {
    for (final cliente in _conexiones) {
      if (cliente.saludado) cliente.enviar(marco);
    }
  }

  /// Levanta el servidor. Devuelve el puerto de verdad.
  Future<int> start({
    required InternetAddress direccion,
    int puerto = 7845,
  }) async {
    if (_http != null) throw StateError('ya está escuchando');
    // `shared: false`: si otro proceso ya tiene el puerto, se quiere el error y no
    // repartir conexiones con un desconocido.
    final servidor = await HttpServer.bind(direccion, puerto, shared: false);
    _http = servidor;
    unawaited(_atender(servidor));
    _anotar('escuchando', detalle: '${direccion.address}:${servidor.port}');
    return servidor.port;
  }

  Future<void> stop() async {
    final servidor = _http;
    _http = null;
    for (final cliente in [..._conexiones]) {
      await cliente.close();
    }
    await servidor?.close(force: true);
    _anotar('cerrado');
  }

  Future<void> _atender(HttpServer servidor) async {
    await for (final peticion in servidor) {
      // Cada petición en su propio hueco: una que se cuelgue no puede dejar de
      // atender a las siguientes.
      unawaited(_revisar(peticion));
    }
  }

  Future<void> _revisar(HttpRequest peticion) async {
    final ip = peticion.connectionInfo?.remoteAddress.address ?? 'desconocida';
    final rechazo = gatekeeper.revisar(
      ip: ip,
      host: peticion.headers.value(HttpHeaders.hostHeader),
      origin: peticion.headers.value('origin'),
      tokenRecibido: _token(peticion),
    );

    if (rechazo != null) {
      // **El motivo va aquí y no en la respuesta.** El 403 es uno solo para todos los
      // rechazos a propósito; este es el sitio donde el dueño del Mac puede ver cuál
      // fue, que es justo lo que faltaba para poder diagnosticar un «reconectando».
      _anotar('rechazado', ip: ip, motivo: rechazo.name);
      // **Un solo código para todos los rechazos, y sin cuerpo.**
      //
      // Distinguir «token equivocado» de «Host ajeno» le diría a quien lo intenta
      // qué comprobación pasó, y eso solo le sirve a quien no debería estar ahí.
      // El motivo va al registro local, que es donde lo puede leer el dueño del
      // Mac — que es el único que necesita depurarlo.
      peticion.response.statusCode = HttpStatus.forbidden;
      await peticion.response.close();
      return;
    }

    if (!WebSocketTransformer.isUpgradeRequest(peticion)) {
      // Autenticado pero no es un WebSocket. No es un ataque: es alguien
      // probando con el navegador… salvo que el navegador ya se rechazó por
      // `Origin`. Así que casi siempre es `curl`.
      _anotar('sinUpgrade', ip: ip);
      peticion.response.statusCode = HttpStatus.upgradeRequired;
      await peticion.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(peticion);
    final cliente = ChannelClient(socket: socket, ip: ip);

    // **Se cierra la más vieja, no se rechaza la nueva.** Rechazar dejaría a un
    // teléfono que reconecta fuera por culpa de su propia conexión anterior, que
    // es la que suele estar muerta sin saberlo. Y quien acaba de autenticarse es
    // quien está delante del teléfono ahora mismo.
    while (_conexiones.length >= maxConexiones) {
      final vieja = _conexiones.removeAt(0);
      _anotar('desalojado', ip: vieja.ip, motivo: 'demasiadas conexiones');
      unawaited(vieja.close());
    }

    _conexiones.add(cliente);
    _anotar('conectado', ip: ip);
    unawaited(_saludar(cliente));
  }

  String? _token(HttpRequest peticion) {
    final crudo = peticion.headers.value(cabeceraToken);
    if (crudo == null) return null;
    const prefijo = 'Bearer ';
    // Sin prefijo también vale: exigirlo convertiría un cliente mal escrito en un
    // «token incorrecto», que es un diagnóstico que manda a mirar al sitio
    // equivocado.
    return crudo.startsWith(prefijo) ? crudo.substring(prefijo.length) : crudo;
  }

  /// El saludo: se espera un [Hello] **antes que nada**.
  ///
  /// Y con plazo. Una conexión que se autentica y luego calla ocupa un socket para
  /// siempre; con tres conversaciones vivas y un móvil que entra y sale por
  /// cobertura, eso se acumula.
  Future<void> _saludar(ChannelClient cliente) async {
    Timer? plazo;
    var saludado = false;

    plazo = Timer(const Duration(seconds: 10), () {
      if (saludado) return;
      _anotar('sinSaludo', ip: cliente.ip, motivo: 'plazo de 10 s');
      unawaited(cliente.close());
    });

    cliente.socket.listen(
      (dynamic crudo) {
        if (crudo is! String) return;
        final Frame marco;
        try {
          marco = Frame.decode(crudo);
        } on FormatException catch (error) {
          registro?.call('mensaje roto de ${cliente.ip}: ${error.message}');
          return;
        }

        if (!saludado) {
          if (marco is! Hello) {
            _anotar(
              'sinSaludo',
              ip: cliente.ip,
              motivo: 'el primero no era un saludo',
            );
            unawaited(cliente.close());
            return;
          }
          saludado = true;
          cliente.saludado = true;
          plazo?.cancel();
          _negociar(cliente, marco);
          return;
        }
        if (marco is Call) {
          // **Cada petición por su cuenta**, y no en cola: un encargo y una
          // consulta del medidor no tienen por qué esperarse. Si se despacharan en
          // serie, abrir la pantalla mientras algo corre se vería colgado.
          unawaited(_despachar(cliente, marco));
          return;
        }
        if (marco is Resume) {
          _reanudar(cliente, marco);
          return;
        }
        if (marco is Audio) {
          // **Sin anotar y sin contestar.** Un trozo cada 20 ms llenaría el registro
          // del canal en un minuto y taparía todo lo demás, que es justo donde se
          // diagnostican los problemas; y confirmarlo sería volver a ponerle el `ack`
          // que este marco existe para no tener.
          audio?.call(marco);
          return;
        }
        // Lo que no es ni petición ni resync se anota para que no desaparezca en
        // silencio. Un `Snapshot` que llegue desde el móvil cae aquí: no lo manda él.
        registro?.call('marco sin despacho: ${marco.runtimeType}');
        cliente.entrantes.add(marco);
      },
      onDone: () {
        plazo?.cancel();
        _conexiones.remove(cliente);
        _anotar('desconectado', ip: cliente.ip);
      },
      onError: (Object error) {
        plazo?.cancel();
        _conexiones.remove(cliente);
        _anotar('perdido', ip: cliente.ip, motivo: 'conexión caída');
      },
      cancelOnError: true,
    );
  }

  /// «Mándame desde el 412».
  ///
  /// Es el camino normal de reconectar, y el snapshot es la excepción — decisión 4.4.
  /// Con tres conversaciones vivas la diferencia entre reenviar veinte eventos y
  /// mandar el estado entero es lo que hace que reconectar en 4G sea barato.
  void _reanudar(ChannelClient cliente, Resume peticion) {
    final pendientes = log.desde(peticion.lastSeq);

    if (pendientes == null) {
      // Lo que pide ya se tiró del búfer. Mandar una lista incompleta sería peor que
      // negarse: el cliente se creería al día con un hueco dentro.
      final foto = snapshot?.call();
      if (foto == null) {
        registro?.call('resync imposible y sin snapshot que dar');
        cliente.enviar(
          const Failure(
            code: 'unavailable',
            message: 'no hay estado que reenviar',
          ),
        );
        return;
      }
      registro?.call('resync desde ${peticion.lastSeq}: snapshot');
      cliente.enviar(foto);
      return;
    }

    registro?.call(
      'resync desde ${peticion.lastSeq}: ${pendientes.length} eventos',
    );
    for (final evento in pendientes) {
      cliente.enviar(evento);
    }
  }

  /// Pasa la petición al despacho y manda lo que salga, en orden.
  ///
  /// El servidor no mira lo que hay dentro: **lo único que sabe de un [Call] es que
  /// hay que reenviar sus respuestas**. Por eso el orden ack-primero no se decide
  /// aquí sino en el despacho, donde se puede probar sin socket.
  Future<void> _despachar(ChannelClient cliente, Call peticion) async {
    final despacho = this.despacho;
    if (despacho == null) {
      // Sin despacho se contesta que no, en vez de dejarlo sin respuesta: un
      // teléfono esperando para siempre se lee como «el Mac no responde», y manda
      // a buscar el problema al sitio equivocado.
      cliente.enviar(
        Failure(
          id: peticion.id,
          code: 'unavailable',
          message: 'este canal no atiende peticiones',
        ),
      );
      return;
    }

    // El método sí se registra, **y los parámetros nunca**: por ahí pasa la frase
    // de escritura, y un registro es exactamente donde no debe quedar escrita.
    // **El método y jamás los parámetros**: por ahí pasa la frase de escritura, y
    // esto se escribe en un archivo que se queda en el disco.
    _anotar('pide', ip: cliente.ip, detalle: peticion.method);
    try {
      await for (final respuesta in despacho.attend(peticion)) {
        cliente.enviar(respuesta);
      }
    } on Object catch (error) {
      // El despacho ya contestó un `Failure` antes de relanzar: esto es solo para
      // que quede anotado en el Mac.
      registro?.call('fallo atendiendo ${peticion.method}: $error');
    }
  }

  void _negociar(ChannelClient cliente, Hello saludo) {
    final resultado = negotiate(client: saludo.protocol, server: protocolo);
    switch (resultado) {
      case Negotiation.ok:
        cliente.peer = saludo.peer;
        cliente.enviar(
          Welcome(
            protocol: protocolo,
            seq: log.lastSeq,
            // El teléfono se pinta con el color del Mac: la app es una, y que el
            // móvil salga en cian de fábrica cuando el escritorio lleva meses en otro
            // tono lo delata como una app distinta.
            accent: acento?.call(),
          ),
        );
        _anotar(
          'saludo',
          ip: cliente.ip,
          detalle: '${saludo.peer.name} ${saludo.appVersion}',
        );
      case Negotiation.clientMustUpdate:
      case Negotiation.serverMustUpdate:
        // Se dice **a quién le toca**, no un «no nos entendemos». Los dos sentidos
        // son posibles: la tienda puede empujar el móvil mientras el Mac lleva
        // semanas sin abrirse.
        final quien = resultado == Negotiation.clientMustUpdate
            ? Peer.mobile
            : Peer.desktop;
        cliente.enviar(UpgradeRequired(protocol: protocolo, who: quien));
        _anotar(
          'versionIncompatible',
          ip: cliente.ip,
          motivo: 'actualiza ${quien.name}',
        );
        // Se cierra después de decirlo: dejarlo abierto invitaría a reintentar en
        // bucle sin que nada cambie.
        unawaited(cliente.close());
    }
  }
}

/// Una conexión aceptada.
class ChannelClient {
  ChannelClient({required this.socket, required this.ip});

  final WebSocket socket;
  final String ip;

  /// Quién dijo ser en el saludo. `null` hasta que salude.
  Peer? peer;

  /// Si ya pasó el handshake. Los eventos solo van a quien lo pasó.
  bool saludado = false;

  /// Lo que llega y todavía no tiene quien lo atienda.
  final entrantes = <Frame>[];

  void enviar(Frame marco) {
    try {
      socket.add(marco.encode());
    } on StateError catch (error) {
      // El socket ya estaba cerrado. Pasa: el móvil pierde cobertura entre que se
      // decide contestar y se contesta.
      debugPrint('no se pudo enviar a $ip: $error');
    }
  }

  Future<void> close() async {
    try {
      await socket.close();
    } on Object {
      // Cerrar lo que ya está cerrado no es un problema que nadie deba atender.
    }
  }
}

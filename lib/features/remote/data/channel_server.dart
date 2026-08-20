import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
/// Lo que hace y lo que no: autentica, negocia la versión y entrega una conexión
/// viva. **No despacha métodos** — eso necesita el estado de la app y es el paso
/// siguiente.
class ChannelServer {
  ChannelServer({
    required this.gatekeeper,
    required this.log,
    this.registro,
    ProtocolRange? protocolo,
  }) : protocolo = protocolo ?? ProtocolRange.mine;

  final Gatekeeper gatekeeper;

  /// Los eventos que ya se emitieron, para poder decir en la bienvenida por dónde
  /// va la numeración.
  final EventLog log;

  /// Dónde anotar lo que pasa, que es la decisión 2.5 empezada: quién intentó
  /// entrar, con qué resultado y cuándo.
  final void Function(String)? registro;

  final ProtocolRange protocolo;

  HttpServer? _http;
  final _conexiones = <ChannelClient>[];

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

  /// Levanta el servidor. Devuelve el puerto de verdad.
  Future<int> start({required InternetAddress direccion, int puerto = 7845}) async {
    if (_http != null) throw StateError('ya está escuchando');
    // `shared: false`: si otro proceso ya tiene el puerto, se quiere el error y no
    // repartir conexiones con un desconocido.
    final servidor = await HttpServer.bind(direccion, puerto, shared: false);
    _http = servidor;
    unawaited(_atender(servidor));
    registro?.call('canal escuchando en ${direccion.address}:${servidor.port}');
    return servidor.port;
  }

  Future<void> stop() async {
    final servidor = _http;
    _http = null;
    for (final cliente in [..._conexiones]) {
      await cliente.close();
    }
    await servidor?.close(force: true);
    registro?.call('canal cerrado');
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
      registro?.call('rechazado $ip: ${rechazo.name}');
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
      peticion.response.statusCode = HttpStatus.upgradeRequired;
      await peticion.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(peticion);
    final cliente = ChannelClient(socket: socket, ip: ip);
    _conexiones.add(cliente);
    registro?.call('conectado $ip');
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
      registro?.call('sin saludo en 10 s: se cierra ${cliente.ip}');
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
            registro?.call('primer mensaje no era un saludo: se cierra');
            unawaited(cliente.close());
            return;
          }
          saludado = true;
          plazo?.cancel();
          _negociar(cliente, marco);
          return;
        }
        // A partir de aquí van los métodos, que todavía no existen. Se anotan para
        // que no desaparezcan en silencio mientras se escribe el despacho.
        registro?.call('mensaje sin despacho todavía: ${marco.runtimeType}');
        cliente.entrantes.add(marco);
      },
      onDone: () {
        plazo?.cancel();
        _conexiones.remove(cliente);
        registro?.call('desconectado ${cliente.ip}');
      },
      onError: (Object error) {
        plazo?.cancel();
        _conexiones.remove(cliente);
        registro?.call('conexión perdida con ${cliente.ip}: $error');
      },
      cancelOnError: true,
    );
  }

  void _negociar(ChannelClient cliente, Hello saludo) {
    final resultado = negotiate(client: saludo.protocol, server: protocolo);
    switch (resultado) {
      case Negotiation.ok:
        cliente.peer = saludo.peer;
        cliente.enviar(Welcome(protocol: protocolo, seq: log.lastSeq));
        registro?.call('saludo de ${saludo.peer.name} ${saludo.appVersion}');
      case Negotiation.clientMustUpdate:
      case Negotiation.serverMustUpdate:
        // Se dice **a quién le toca**, no un «no nos entendemos». Los dos sentidos
        // son posibles: la tienda puede empujar el móvil mientras el Mac lleva
        // semanas sin abrirse.
        final quien = resultado == Negotiation.clientMustUpdate
            ? Peer.mobile
            : Peer.desktop;
        cliente.enviar(UpgradeRequired(protocol: protocolo, who: quien));
        registro?.call('versión incompatible: actualiza ${quien.name}');
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

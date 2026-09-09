import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/run/domain/usecases/el_error_que_pinta_la_app.dart';
import 'package:nexus/features/run/domain/usecases/el_freno_de_la_app.dart';
import 'package:nexus/features/run/domain/usecases/protocolo_del_vm_service.dart';

/// Cómo se abre el socket, como un dato.
///
/// Por lo mismo que `LanzarUnProceso` en el punto 3 del repaso: con
/// `WebSocket.connect` a pelo, probar este archivo pedía un VM service de verdad
/// —o sea una app compilada y corriendo— y lo que hay que comprobar aquí es
/// **qué se le pide y qué se hace con lo que contesta**.
typedef AbrirUnSocket = Future<WebSocket> Function(String url);

/// El socket al VM service de una corrida: sus errores y su freno.
///
/// **Un `WebSocket` pelado y no el paquete `vm_service`.** De todo el protocolo
/// aquí se usan cinco métodos —apuntarse a dos canales, listar isolates, poner
/// el modo de pausa y reanudar—, y el paquete trae un cliente generado entero,
/// con su propio modelo de objetos, para no usar casi nada de eso. Es la misma
/// decisión que ya se tomó con el daemon: el idioma vive en
/// [ElErrorQuePintaLaApp] y [ElFrenoDeLaApp], que son puros y se prueban con
/// eventos de verdad, y aquí solo está el cable.
///
/// La URL la dice el propio `flutter run` en `app.debugPort` —`wsUri`—, así que
/// tampoco se adivina ni se compone.
class ElCanalDelVmService {
  ElCanalDelVmService._(this._socket);

  final WebSocket _socket;

  /// Los ids de las peticiones, que **tienen que ser distintos**: es lo único
  /// que empareja una respuesta con lo que se preguntó, y dos peticiones con el
  /// mismo id dejan una esperando para siempre.
  var _ultimoId = 0;

  final _esperando = <int, Completer<String?>>{};

  /// Se conecta y se apunta a lo que haga falta. Devuelve `null` si no se pudo:
  /// **no es un fallo de la corrida**, que sigue corriendo igual de bien sin que
  /// nadie oiga sus errores. Se anota y se sigue.
  ///
  /// [alPararse] y [alSeguir] son opcionales, y **si no se pasan no se pide el
  /// canal del depurador**: apuntarse a un canal que nadie escucha es tráfico
  /// por nada.
  static Future<ElCanalDelVmService?> abrir(
    String wsUri, {
    required void Function(String error) alOirUnError,
    void Function(LaParadaDeLaApp parada)? alPararse,
    void Function(String isolate) alSeguir = _nadie,
    AbrirUnSocket conectar = WebSocket.connect,
  }) async {
    final WebSocket socket;
    try {
      socket = await conectar(wsUri);
    } on Object catch (e) {
      debugPrint('corrida · no se pudo oír los errores de la app: $e');
      return null;
    }

    final canal = ElCanalDelVmService._(socket);
    socket.listen(
      (mensaje) {
        if (mensaje is! String) return;
        // **Primero las respuestas.** Llegan con `id` y sin `method`, y quien
        // las espera está bloqueado: si se leyeran como eventos, `getVM` no
        // contestaría nunca y el freno no se llegaría a poner.
        if (canal._esLaRespuestaDeAlguien(mensaje)) return;

        if (ElErrorQuePintaLaApp.loQueDice(mensaje) case final error?) {
          alOirUnError(error);
          return;
        }
        if (ElFrenoDeLaApp.laParada(mensaje) case final parada?) {
          alPararse?.call(parada);
          return;
        }
        if (ElFrenoDeLaApp.siguio(mensaje) case final isolate?) {
          alSeguir(isolate);
        }
      },
      // Que se caiga es lo normal al cerrarse la app: no hay nada que decir.
      // Lo que sí hay que hacer es soltar a quien esté esperando: un socket
      // muerto no va a contestar, y sin esto se quedaría colgado su plazo
      // entero.
      onError: (Object _) => canal._nadieVaAContestar(),
      onDone: canal._nadieVaAContestar,
      cancelOnError: true,
    );

    unawaited(canal.pedir(ElErrorQuePintaLaApp.peticionDeEscucha));
    if (alPararse != null) {
      unawaited(canal.pedir(ElFrenoDeLaApp.escucharLasParadas));
    }
    return canal;
  }

  /// Manda una petición y espera su respuesta, tal como vino.
  ///
  /// [peticion] recibe el id porque lo pone esta clase: quien pregunta no tiene
  /// por qué llevar la cuenta. `null` cuando no contestó —el socket se cayó, o
  /// tardó más que [tope]—, que es distinto de contestar un error y se trata
  /// igual: no se puede hacer nada con ello.
  ///
  /// **El plazo no es decoración.** Todo esto pasa dentro de un botón: sin él,
  /// una app que se quedó a medias dejaría el botón girando hasta que alguien
  /// cierre la ventana.
  Future<String?> pedir(
    String Function(int id) peticion, {
    Duration tope = const Duration(seconds: 5),
  }) async {
    final id = ++_ultimoId;
    final esperando = Completer<String?>();
    _esperando[id] = esperando;
    try {
      _socket.add(peticion(id));
    } on Object catch (e) {
      _esperando.remove(id);
      debugPrint('vm service · no se pudo preguntar: $e');
      return null;
    }
    try {
      return await esperando.future.timeout(tope);
    } on TimeoutException {
      _esperando.remove(id);
      debugPrint('vm service · no contestó a tiempo la petición $id');
      return null;
    }
  }

  Future<void> cerrar() async {
    _nadieVaAContestar();
    try {
      await _socket.close();
    } on Object {
      // Ya estaba cerrado, que es el caso de siempre: la app se fue primero.
    }
  }

  /// Si este mensaje es la respuesta que alguien estaba esperando.
  bool _esLaRespuestaDeAlguien(String mensaje) {
    final id = ProtocoloDelVmService.deQuienEs(mensaje);
    if (id == null) return false;
    final esperando = _esperando.remove(id);
    if (esperando == null) {
      // Una respuesta que ya nadie espera —llegó tarde, después del plazo— no
      // es un evento: se descarta aquí y no baja a los lectores.
      return true;
    }
    if (!esperando.isCompleted) esperando.complete(mensaje);
    return true;
  }

  void _nadieVaAContestar() {
    for (final esperando in _esperando.values) {
      if (!esperando.isCompleted) esperando.complete(null);
    }
    _esperando.clear();
  }

  static void _nadie(String _) {}
}

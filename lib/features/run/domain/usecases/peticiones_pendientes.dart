import 'dart:async';

import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/protocolo_del_daemon.dart';

/// Las peticiones que esperan contestación, emparejadas por id.
///
/// **Es lo que separa este canal de escribir una `r` y cruzar los dedos.** El
/// daemon contesta a lo que se le pide, pero la contestación llega por el mismo
/// sitio que todo lo demás y en cualquier momento: hay que guardar quién
/// preguntó, emparejar por id, y rendirse con un plazo si no vuelve nadie.
///
/// No sabe de procesos: se le da una función que escribe y se le pasan las
/// respuestas que llegan. Así se puede probar con un reloj de mentira, sin
/// esperar de verdad los dos minutos del plazo.
class PeticionesPendientes {
  PeticionesPendientes({required this.escribir, this.tope = _topeDeFabrica});

  /// A dónde va la línea. En producción es el stdin del proceso.
  final void Function(String linea) escribir;

  /// Cuánto se espera antes de rendirse.
  ///
  /// Dos minutos, que parece mucho hasta que se recuerda que una recarga con
  /// dispositivo lento y un árbol grande no es instantánea. Rendirse antes
  /// diría «no funcionó» de algo que estaba funcionando, y eso es peor que
  /// esperar: manda a alguien a buscar un fallo que no existe.
  final Duration tope;
  static const _topeDeFabrica = Duration(minutes: 2);

  final _pendientes = <int, Completer<({bool ok, String? error})>>{};
  var _ultimoId = 0;

  /// Cuántas hay esperando. Para saber si el canal está ocupado sin adivinarlo.
  int get esperando => _pendientes.length;

  /// Manda una petición y espera su respuesta.
  ///
  /// [construir] recibe el id porque el id lo pone esto: quien pide no tiene por
  /// qué llevar la cuenta, y llevarla en dos sitios es cómo se acaban repitiendo.
  Future<({bool ok, String? error})> pedir(String Function(int id) construir) {
    final id = ++_ultimoId;
    final espera = Completer<({bool ok, String? error})>();
    _pendientes[id] = espera;

    final plazo = Timer(tope, () {
      // Se saca del mapa antes de contestar: si la respuesta llega tarde, se
      // ignora en vez de intentar completar dos veces —que lanza.
      if (_pendientes.remove(id) == null) return;
      espera.complete((ok: false, error: 'No contestó a tiempo'));
    });

    try {
      escribir(construir(id));
    } on Object catch (error) {
      // El proceso pudo morirse entre que se decidió pedir y se escribió. Eso no
      // es una excepción que deba subir: es un «no se pudo» con su motivo.
      plazo.cancel();
      _pendientes.remove(id);
      return Future.value((ok: false, error: '$error'));
    }

    return espera.future.whenComplete(plazo.cancel);
  }

  /// Una respuesta que llegó. `true` si era de alguien que la esperaba.
  ///
  /// Devuelve si la reconoció para que quien lee la salida pueda tratar como
  /// registro lo que no era de nadie, en vez de tirarlo en silencio.
  bool recibe(RespuestaDelDaemon respuesta) {
    final espera = _pendientes.remove(respuesta.id);
    if (espera == null) return false;

    espera.complete(
      ProtocoloDelDaemon.resultadoDe(respuesta.result, respuesta.error),
    );
    return true;
  }

  /// El proceso se fue. Nadie va a contestar ya.
  ///
  /// Sin esto, cerrar la app dejaría a quien pidió una recarga esperando dos
  /// minutos a un plazo que ya no significa nada.
  void cierra([String motivo = 'La app dejó de correr']) {
    for (final espera in _pendientes.values) {
      espera.complete((ok: false, error: motivo));
    }
    _pendientes.clear();
  }
}

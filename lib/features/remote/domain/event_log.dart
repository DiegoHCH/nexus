import 'dart:collection';

import 'package:nexus_protocol/nexus_protocol.dart';

/// Lo que se puede volver a mandar cuando el móvil reconecta.
///
/// La decisión 4.4 del contrato: los eventos van numerados y el servidor guarda un
/// búfer, así que reconectar es «mándame desde el 412» en vez de «mándame todo». En
/// 4G esa es la diferencia entre barato y caro, y con tres conversaciones a la vez
/// no es un detalle: son tres flujos vivos.
///
/// **Circular y no infinito**, y el tope es lo interesante: un búfer que lo guarda
/// todo crece mientras la app esté abierta, y una sesión de trabajo de un día son
/// decenas de miles de deltas. Al pasarse se tira lo viejo, y quien pida desde ahí
/// recibe el snapshot completo — que es el camino de excepción, no el normal.
class EventLog {
  EventLog({this.capacidad = 512});

  /// Cuántos eventos se recuerdan.
  ///
  /// 512 sale de la cadencia: los deltas se agrupan cada ~100 ms —decisión 4.5— así
  /// que 512 eventos son unos cincuenta segundos de escritura continua. Suficiente
  /// para cubrir un túnel o un cambio de wifi, que es lo que un resync tiene que
  /// salvar; una caída de diez minutos ya no se arregla reenviando, se arregla con
  /// el snapshot.
  final int capacidad;

  final _buffer = Queue<Event>();
  int _ultimo = 0;

  /// El número del último evento emitido. Va en la bienvenida para que el cliente
  /// sepa si va al día **sin pedir nada**.
  int get lastSeq => _ultimo;

  int get guardados => _buffer.length;

  /// Numera un evento y lo guarda.
  ///
  /// El `seq` lo pone **aquí y no quien publica**: si cada emisor llevara su cuenta,
  /// dos eventos simultáneos podrían compartir número y el resync se saltaría uno
  /// para siempre.
  Event emitir(String kind, [Map<String, Object?> data = const {}]) {
    final evento = Event(seq: ++_ultimo, kind: kind, data: data);
    _buffer.addLast(evento);
    while (_buffer.length > capacidad) {
      _buffer.removeFirst();
    }
    return evento;
  }

  /// Lo que le falta a quien vio hasta [lastSeqVisto].
  ///
  /// `null` significa **«no puedo, pídeme el snapshot»**: lo que buscas ya se tiró.
  /// Devolver una lista incompleta en ese caso sería peor que negarse — el cliente
  /// creería estar al día con un hueco dentro.
  List<Event>? desde(int lastSeqVisto) {
    if (lastSeqVisto == _ultimo) return const [];
    if (lastSeqVisto > _ultimo) {
      // El cliente dice haber visto más de lo que existe. Pasa de verdad: el
      // servidor se reinició y su numeración volvió a empezar. No es un resync, es
      // otra vida — y se resuelve con el snapshot.
      return null;
    }
    if (_buffer.isEmpty) return null;
    if (lastSeqVisto < _buffer.first.seq - 1) return null;
    return [for (final e in _buffer) if (e.seq > lastSeqVisto) e];
  }
}

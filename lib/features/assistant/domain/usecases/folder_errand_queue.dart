import 'dart:async';

/// Un encargo a la vez por carpeta.
///
/// Existe por una medición, no por prudencia: dos conversaciones sobre la misma
/// carpeta comparten la sesión de Claude —esa es la regla del producto— y
/// lanzar las dos a la vez **pierde una**. Medido contra el binario: dos
/// `--resume` simultáneos sobre la misma sesión responden bien los dos, pero al
/// preguntar después qué se había dicho, solo constaba el último. El turno del
/// otro había desaparecido del historial.
///
/// Serializar es la salida barata y la correcta: se conserva la regla —misma
/// carpeta, mismo contexto— y lo único que cambia es que el segundo espera. La
/// alternativa sería darle sesión propia a cada conversación, que es justo el
/// contexto compartido que se pidió.
///
/// Carpetas distintas no se estorban: cada una tiene su cola.
class FolderErrandQueue {
  FolderErrandQueue();

  final _queues = <String, Future<void>>{};

  /// Pide el turno para [folder]. Devuelve cuando le toca, y lo que entrega es
  /// la función para soltarlo — que hay que llamar **siempre**, incluso si el
  /// encargo falla o se cancela: sin eso, la carpeta se queda bloqueada para
  /// el resto de la sesión.
  Future<void Function()> acquire(String folder) async {
    final previous = _queues[folder];
    final mine = Completer<void>();
    _queues[folder] = mine.future;

    // Esperar al anterior, pase lo que pase con él: si el encargo de la otra
    // conversación revienta, el siguiente tiene que entrar igual.
    if (previous != null) {
      await previous;
    }

    var released = false;
    return () {
      if (released) return;
      released = true;
      mine.complete();
      // El último en soltar limpia: si no, este mapa acumula una entrada por
      // cada carpeta que se haya usado en la vida de la app.
      if (identical(_queues[folder], mine.future)) _queues.remove(folder);
    };
  }

  /// Si hay alguien trabajando ya en esa carpeta. Sirve para poder decirlo en
  /// pantalla: esperar sin explicación se ve igual que estar colgado.
  bool isBusy(String folder) => _queues.containsKey(folder);
}

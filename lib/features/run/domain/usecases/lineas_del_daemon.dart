import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/protocolo_del_daemon.dart';

/// Convierte los trozos que llegan por stdout en mensajes completos.
///
/// **Existe porque un `Stream` de proceso no viene en líneas.** Llega en trozos
/// del tamaño que decida el sistema, así que un mensaje puede partirse por la
/// mitad y dos pueden venir pegados. Decodificar cada trozo por su cuenta
/// convertiría el JSON cortado en un registro basura y perdería un evento — y el
/// evento perdido sería `app.started`, que es justo el que hace falta.
///
/// Es el mismo problema que ya resolvió `ClaudeStreamDecoder` para el
/// `stream-json` de `claude -p`. Se repite la técnica y no el código: aquel
/// decodifica otro formato y mezclarlos ataría dos protocolos ajenos.
class LineasDelDaemon {
  final _pendiente = StringBuffer();

  /// Los mensajes completos que haya en [trozo].
  ///
  /// Lo que quede a medias se guarda para el siguiente. Si el proceso muere
  /// dejando media línea, esa línea se pierde — y está bien: era media.
  Iterable<MensajeDelDaemon> add(String trozo) {
    _pendiente.write(trozo);
    final texto = _pendiente.toString();

    // Sin salto de línea todavía no hay nada completo.
    final ultimoSalto = texto.lastIndexOf('\n');
    if (ultimoSalto < 0) return const [];

    _pendiente
      ..clear()
      ..write(texto.substring(ultimoSalto + 1));

    return [
      for (final linea in texto.substring(0, ultimoSalto).split('\n'))
        if (linea.trim().isNotEmpty) ProtocoloDelDaemon.leerLinea(linea),
    ];
  }

  /// Lo que quedó sin terminar, para cuando el proceso se cierra.
  ///
  /// Se ofrece en vez de tirarlo porque la última línea de un proceso que muere
  /// mal suele ser justo el motivo, y a menudo llega sin su salto.
  MensajeDelDaemon? cierra() {
    final resto = _pendiente.toString().trim();
    _pendiente.clear();
    return resto.isEmpty ? null : ProtocoloDelDaemon.leerLinea(resto);
  }
}

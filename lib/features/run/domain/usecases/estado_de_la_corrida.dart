import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/protocolo_del_daemon.dart';

/// Lo que un evento del daemon le hace a una corrida.
///
/// **Puro y aparte del controlador** para poder probar la traducción sin lanzar
/// un `flutter run`: es la parte con reglas —qué evento significa qué— y la que
/// se rompe al añadir un evento nuevo.
({Corrida corrida, Map<String, ProgresoDelDaemon> progresos, bool termino})
aplicaEvento(
  Corrida actual,
  Map<String, ProgresoDelDaemon> progresos,
  EventoDelDaemon evento,
) {
  switch (evento.nombre) {
    case 'app.start':
      // Llega el identificador con el que se le pide todo lo demás.
      return (
        corrida: actual.copyWith(appId: evento.params['appId'] as String?),
        progresos: progresos,
        termino: false,
      );

    case 'app.started':
      // **El evento que en H1 hubo que sondear a mano** con el emulador: allí el
      // comando volvía antes que el aparato y había que preguntar cada dos
      // segundos. Aquí lo dicen ellos, y esa es la mitad del valor de hablar el
      // protocolo en vez de leer texto.
      return (
        corrida: actual.copyWith(
          estado: EstadoDeCorrida.corriendo,
          limpiaProgreso: true,
        ),
        progresos: const {},
        termino: false,
      );

    case 'app.progress':
      final siguiente = ProtocoloDelDaemon.aplicaProgreso(
        progresos,
        evento.params,
      );
      final visible = ProtocoloDelDaemon.progresoVisible(siguiente);
      return (
        corrida: visible == null
            ? actual.copyWith(limpiaProgreso: true)
            : actual.copyWith(progreso: visible.mensaje),
        progresos: siguiente,
        termino: false,
      );

    case 'app.debugPort' || 'app.webLaunchUrl':
      return (
        corrida: actual.copyWith(
          url: (evento.params['wsUri'] ?? evento.params['url']) as String?,
        ),
        progresos: progresos,
        termino: false,
      );

    case 'app.stop':
      return (corrida: actual, progresos: progresos, termino: true);

    default:
      // `daemon.connected`, `daemon.logMessage` y lo que inventen mañana: no
      // cambian nada y no son un error. Ignorarlos explícitamente es distinto de
      // no haberlos visto.
      return (corrida: actual, progresos: progresos, termino: false);
  }
}

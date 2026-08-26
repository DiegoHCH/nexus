import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/estado_de_la_corrida.dart';

/// La app corriendo: qué la bloquea y qué le hace cada evento.
Corrida _corrida({
  String deviceId = 'emulator-5554',
  PlataformaEmulador plataforma = PlataformaEmulador.android,
  EstadoDeCorrida estado = EstadoDeCorrida.arrancando,
}) => Corrida(
  deviceId: deviceId,
  dispositivo: 'Medium Phone',
  proyecto: '/casa/tienda',
  configuracion: 'Tienda (dev)',
  plataforma: plataforma,
  estado: estado,
);

void main() {
  group('qué impide arrancar otra', () {
    test('otra de la misma plataforma bloquea', () {
      // **Comparten el directorio de build del proyecto y se pisan.** Se corta
      // antes de lanzar porque enterarse por el error de Gradle cuesta tres
      // minutos y no apunta a su causa.
      final bloquea = loQueBloquea(
        [_corrida()],
        PlataformaEmulador.android,
      );
      expect(bloquea?.deviceId, 'emulator-5554');
    });

    test('cruzadas conviven, que es el caso que se quiere', () {
      // Ver el mismo cambio en Android y en iOS sin lanzar dos veces.
      expect(loQueBloquea([_corrida()], PlataformaEmulador.ios), isNull);
    });

    test('sin nada corriendo no bloquea nadie', () {
      expect(loQueBloquea(const [], PlataformaEmulador.android), isNull);
    });
  });

  group('qué le hace cada evento', () {
    test('app.start trae el identificador con el que se le pide todo', () {
      final r = aplicaEvento(
        _corrida(),
        const {},
        const EventoDelDaemon(
          nombre: 'app.start',
          params: {'appId': 'abc'},
        ),
      );

      expect(r.corrida.appId, 'abc');
      // Todavía no se ve en el dispositivo: sigue arrancando.
      expect(r.corrida.estado, EstadoDeCorrida.arrancando);
      expect(r.corrida.puedeRecargar, isFalse);
    });

    test('app.started es cuando ya se ve, y solo entonces acepta recargas', () {
      // Este es el evento que en H1 hubo que sondear a mano con el emulador.
      // Aquí lo dice el propio daemon, y esa es la mitad del valor de hablar el
      // protocolo en vez de leer texto.
      final r = aplicaEvento(
        _corrida().copyWith(appId: 'abc'),
        const {},
        const EventoDelDaemon(nombre: 'app.started'),
      );

      expect(r.corrida.estado, EstadoDeCorrida.corriendo);
      expect(r.corrida.puedeRecargar, isTrue);
      // Y se limpia lo que estuviera compilando: ya no compila.
      expect(r.corrida.progreso, isNull);
    });

    test('el progreso se enseña y se limpia solo', () {
      var r = aplicaEvento(
        _corrida(),
        const {},
        const EventoDelDaemon(
          nombre: 'app.progress',
          params: {'id': '1', 'message': 'Compilando'},
        ),
      );
      expect(r.corrida.progreso, 'Compilando');

      r = aplicaEvento(
        r.corrida,
        r.progresos,
        const EventoDelDaemon(
          nombre: 'app.progress',
          params: {'id': '1', 'finished': true},
        ),
      );
      expect(r.corrida.progreso, isNull);
    });

    test('la URL del depurador se guarda venga como venga', () {
      // `app.debugPort` la manda como `wsUri` y `app.webLaunchUrl` como `url`.
      expect(
        aplicaEvento(
          _corrida(),
          const {},
          const EventoDelDaemon(
            nombre: 'app.debugPort',
            params: {'wsUri': 'ws://127.0.0.1:1/x'},
          ),
        ).corrida.url,
        'ws://127.0.0.1:1/x',
      );
    });

    test('app.stop termina la corrida', () {
      expect(
        aplicaEvento(
          _corrida(),
          const {},
          const EventoDelDaemon(nombre: 'app.stop'),
        ).termino,
        isTrue,
      );
    });

    test('un evento que no conocemos no cambia nada ni revienta', () {
      // `daemon.connected`, `daemon.logMessage` y lo que inventen mañana.
      // Ignorarlos a propósito es distinto de no haberlos visto.
      final r = aplicaEvento(
        _corrida(),
        const {},
        const EventoDelDaemon(nombre: 'daemon.connected'),
      );
      expect(r.termino, isFalse);
      expect(r.corrida.estado, EstadoDeCorrida.arrancando);
    });
  });
}

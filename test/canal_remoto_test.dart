import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/gatekeeper.dart';
import 'package:nexus/features/remote/domain/tailscale.dart';

// El portero del canal y su registro de eventos.
//
// Estas son las reglas que **nadie va a probar a mano**: no se ven en la pantalla,
// solo se notan el día que alguien entra donde no debe. Y son las que el contrato
// —`docs/PROTOCOL.md`, decisiones 1 a 2.3 y 4.4— dejó escritas antes de que
// existiera este código.
void main() {
  group('la interfaz de Tailscale', () {
    test('reconoce el rango que Tailscale reparte', () {
      for (final buena in ['100.64.0.1', '100.100.20.30', '100.127.255.255']) {
        expect(
          Tailscale.esDeTailscale(InternetAddress(buena)),
          isTrue,
          reason: '$buena está en 100.64.0.0/10',
        );
      }
    });

    test('y no confunde el resto del 100.x con CGNAT', () {
      // Es `/10` y no `/8`: `100.0.x` y `100.128.x` son direcciones públicas de
      // internet. Darlas por buenas sería escuchar donde no se debe, que es
      // exactamente lo contrario de la decisión 1.
      for (final mala in [
        '100.0.0.1',
        '100.63.255.255',
        '100.128.0.1',
        '100.255.1.1',
      ]) {
        expect(
          Tailscale.esDeTailscale(InternetAddress(mala)),
          isFalse,
          reason: '$mala NO es de Tailscale y aceptarla abriría el canal',
        );
      }
    });

    test('ni la red local, ni el bucle', () {
      for (final otra in [
        '192.168.1.10',
        '10.0.0.5',
        '127.0.0.1',
        '172.16.0.1',
      ]) {
        expect(Tailscale.esDeTailscale(InternetAddress(otra)), isFalse);
      }
    });

    test('elige la de Tailscale de entre varias', () {
      final elegida = Tailscale.elegir([
        InternetAddress('192.168.1.10'),
        InternetAddress('100.101.102.103'),
        InternetAddress('10.0.0.1'),
      ]);
      expect(elegida?.address, '100.101.102.103');
    });

    test('y sin Tailscale contesta que no hay, en vez de caer a otra', () {
      // El fallo que esto evita: a falta de Tailscale, «coger la primera que haya»
      // acabaría escuchando en la red local — abriendo el canal a todo el wifi.
      expect(
        Tailscale.elegir([
          InternetAddress('192.168.1.10'),
          InternetAddress('10.0.0.1'),
        ]),
        isNull,
      );
      expect(Tailscale.elegir([]), isNull);
    });
  });

  group('el portero', () {
    Gatekeeper montar({DateTime Function()? reloj}) => Gatekeeper(
      token: 'el-token-de-verdad',
      hostEsperado: '100.100.20.30:7845',
      reloj: reloj,
    );

    // `_bueno` como centinela y no `??`: con un `host ?? elBueno`, pasar `null`
    // —que es justo el caso de «no trae Host»— sustituía silenciosamente por el
    // valor correcto y la prueba se mentía a sí misma. Lo dijo el primer fallo.
    const bueno = '__el-de-siempre__';
    Rechazo? revisar(
      Gatekeeper g, {
      String? host = bueno,
      String? origin,
      String? token = bueno,
      String ip = '100.64.0.9',
    }) => g.revisar(
      ip: ip,
      host: host == bueno ? '100.100.20.30:7845' : host,
      origin: origin,
      tokenRecibido: token == bueno ? 'el-token-de-verdad' : token,
    );

    test('con todo en orden, pasa', () {
      expect(revisar(montar()), isNull);
    });

    test('sin token, no', () {
      expect(revisar(montar(), token: ''), Rechazo.sinToken);
    });

    test('con el token equivocado, no', () {
      expect(revisar(montar(), token: 'otro'), Rechazo.tokenIncorrecto);
    });

    test('con Origin presente, no — eso es un navegador', () {
      // La regla que cierra el DNS rebinding: nuestro cliente **nunca** manda
      // `Origin`, y un navegador no puede evitarlo. Su presencia identifica al
      // navegador, y el token no habría servido de nada — el navegador lo
      // enviaría igual, porque el ataque viene de dentro del Mac.
      expect(
        revisar(montar(), origin: 'https://cualquier-web.com'),
        Rechazo.desdeUnNavegador,
      );
      // Incluso si el origen parece inofensivo.
      expect(
        revisar(montar(), origin: 'http://localhost:3000'),
        Rechazo.desdeUnNavegador,
      );
    });

    test('con un Host que no es el nuestro, no', () {
      expect(revisar(montar(), host: 'evil.example.com'), Rechazo.hostAjeno);
      expect(revisar(montar(), host: null), Rechazo.hostAjeno);
      // Y tampoco el mismo nombre con otro puerto.
      expect(revisar(montar(), host: '100.100.20.30:9999'), Rechazo.hostAjeno);
    });

    test(
      'el orden de las comprobaciones no gasta intentos de quien no lo intentaba',
      () {
        // Un navegador rechazado por `Origin` no puede contar como intento fallido de
        // adivinar el token: si contara, cualquier web abierta agotaría el cupo de la
        // IP del propio Mac y dejaría al móvil fuera.
        final g = montar();
        for (var i = 0; i < 20; i++) {
          revisar(g, origin: 'https://web.com');
        }
        expect(g.fallosDe('100.64.0.9'), 0);
        expect(revisar(g), isNull, reason: 'el legítimo sigue pudiendo entrar');
      },
    );

    test('demasiados intentos y se cierra', () {
      final g = montar();
      for (var i = 0; i < 10; i++) {
        expect(revisar(g, token: 'mal-$i'), Rechazo.tokenIncorrecto);
      }
      expect(revisar(g, token: 'mal-11'), Rechazo.demasiadosIntentos);
      // Y ni con el token correcto: el cupo es de la IP, no del token.
      expect(revisar(g), Rechazo.demasiadosIntentos);
    });

    test('el cupo es por IP, no global', () {
      // Si fuera global, un atacante dejaría al móvil fuera con solo fallar diez
      // veces desde cualquier sitio.
      final g = montar();
      for (var i = 0; i < 10; i++) {
        revisar(g, token: 'mal', ip: '100.64.0.66');
      }
      expect(revisar(g, ip: '100.64.0.66'), Rechazo.demasiadosIntentos);
      expect(revisar(g, ip: '100.64.0.9'), isNull);
    });

    test('pasada la ventana se vuelve a poder intentar', () {
      var ahora = DateTime(2026, 8, 20, 10);
      final g = montar(reloj: () => ahora);
      for (var i = 0; i < 10; i++) {
        revisar(g, token: 'mal');
      }
      expect(revisar(g), Rechazo.demasiadosIntentos);
      ahora = ahora.add(const Duration(minutes: 2));
      expect(
        revisar(g),
        isNull,
        reason:
            'un bloqueo permanente por diez errores '
            'dejaría fuera a quien se equivocó de token una tarde',
      );
    });

    test('los aciertos no gastan cupo', () {
      // Un móvil con mala cobertura reconecta muchas veces, y quedarse fuera por
      // eso sería el peor fallo posible de esta regla.
      final g = montar();
      for (var i = 0; i < 50; i++) {
        expect(revisar(g), isNull);
      }
      expect(g.fallosDe('100.64.0.9'), 0);
    });

    test('la comparación no delata el contenido por su longitud recorrida', () {
      // No se puede medir el tiempo de forma fiable en una prueba, así que se
      // comprueba lo que sí es comprobable: que acierta y falla correctamente en
      // los bordes donde una comparación normal se saldría antes.
      expect(Gatekeeper.coincide('abc', 'abc'), isTrue);
      expect(Gatekeeper.coincide('abc', 'abd'), isFalse);
      expect(Gatekeeper.coincide('abc', 'ab'), isFalse);
      expect(Gatekeeper.coincide('ab', 'abc'), isFalse);
      expect(Gatekeeper.coincide('', ''), isTrue);
      expect(Gatekeeper.coincide('', 'a'), isFalse);
      // Y el caso que delata a `==`: mismo prefijo largo, distinto al final.
      expect(Gatekeeper.coincide('a' * 63 + 'x', 'a' * 63 + 'y'), isFalse);
    });
  });

  group('el registro de eventos', () {
    test('numera desde uno y en orden', () {
      final log = EventLog();
      expect(log.emitir('a').seq, 1);
      expect(log.emitir('b').seq, 2);
      expect(log.lastSeq, 2);
    });

    test('quien va al día recibe una lista vacía, no un snapshot', () {
      final log = EventLog()..emitir('a');
      expect(log.desde(1), isEmpty);
    });

    test('devuelve solo lo que falta', () {
      final log = EventLog();
      for (final k in ['a', 'b', 'c', 'd']) {
        log.emitir(k);
      }
      final faltan = log.desde(2)!;
      expect(faltan.map((e) => e.seq), [3, 4]);
    });

    test('desde el principio, todo', () {
      final log = EventLog();
      log
        ..emitir('a')
        ..emitir('b');
      expect(log.desde(0)!.length, 2);
    });

    test('lo que ya se tiró pide snapshot en vez de mentir', () {
      // El caso que importa: devolver una lista incompleta dejaría al cliente
      // creyendo que está al día **con un hueco dentro**, y ese hueco no se
      // recupera nunca.
      final log = EventLog(capacidad: 3);
      for (var i = 0; i < 10; i++) {
        log.emitir('e$i');
      }
      expect(log.guardados, 3);
      expect(log.desde(1), isNull, reason: 'el 2 y el 3 ya no están');
      expect(log.desde(7)!.map((e) => e.seq), [8, 9, 10]);
    });

    test(
      'un cliente que dice haber visto más de lo que existe pide snapshot',
      () {
        // Pasa de verdad: el servidor se reinició y su numeración volvió a empezar.
        // No es un resync, es otra vida.
        final log = EventLog()..emitir('a');
        expect(log.desde(500), isNull);
      },
    );

    test('el búfer no crece sin tope', () {
      final log = EventLog(capacidad: 10);
      for (var i = 0; i < 1000; i++) {
        log.emitir('e');
      }
      expect(log.guardados, 10);
      expect(
        log.lastSeq,
        1000,
        reason: 'la numeración sigue, aunque el búfer no',
      );
    });
  });
}

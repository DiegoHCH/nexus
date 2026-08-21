import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/domain/pairing_code.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

// El código del QR y el acento heredado.
//
// Las dos cosas son lo mismo visto desde ángulos distintos: **qué viaja con el
// emparejamiento y qué viaja con la conexión**. Y la respuesta no es la misma para
// las dos, que es lo interesante.

const tokenBueno = 'MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3';

void main() {
  final pareja = Pairing(
    url: Uri.parse('ws://100.73.35.55:7845'),
    token: const ChannelToken(tokenBueno),
  );

  group('el código', () {
    test('va y vuelve: lo que se compone es lo que se lee', () {
      final leido = PairingCode.leer(PairingCode.componer(pareja));

      expect(leido.problema, isNull);
      expect(leido.emparejamiento!.comoSeVe, '100.73.35.55:7845');
      expect(leido.emparejamiento!.token.value, tokenBueno);
    });

    test('usa un esquema propio y no una URL clicable', () {
      final texto = PairingCode.componer(pareja);

      // Una `https` sería **clicable**, y un token en una URL clicable acaba abierto
      // en un navegador, en un historial y en un registro. Con `nexus://` no hay nada
      // que lo abra por accidente.
      expect(texto, startsWith('nexus://pair'));
      expect(texto, isNot(contains('http')));
    });

    test('un QR de otra cosa se dice como lo que es', () {
      // Lo que la cámara ve antes del bueno: la wifi de la cafetería, una URL, un
      // billete. No es un error de quien escanea.
      for (final ajeno in [
        'WIFI:S:MiRed;T:WPA;P:secreto;;',
        'https://ejemplo.com',
        'tel:+34600000000',
        'texto suelto',
      ]) {
        expect(
          PairingCode.leer(ajeno).problema,
          PairingProblem.noEsDeNexus,
          reason: ajeno,
        );
      }
    });

    test('un código de Nexus a medias se dice por su problema, no como ajeno', () {
      // La distinción importa: «no es de Nexus» manda a buscar otro QR, y «el token
      // está incompleto» manda a mirar el que hay. Confundirlos manda a la persona al
      // sitio equivocado.
      expect(
        PairingCode.leer('nexus://pair?h=100.64.0.1:7845&t=corto').problema,
        PairingProblem.tokenCorto,
      );
      expect(
        PairingCode.leer('nexus://pair?t=$tokenBueno').problema,
        PairingProblem.urlIlegible,
      );
    });

    test('valida con la misma función que el campo de texto', () {
      // Si el QR validara aparte, podría aceptar algo que el campo rechaza — y
      // entonces habría dos ideas de qué es un emparejamiento válido. Se comprueba
      // con un caso que las dos rutas tienen que rechazar igual.
      const aMedias = 'nexus://pair?h=100.64.0.1&t=$tokenBueno';
      expect(PairingCode.leer(aMedias).problema, PairingProblem.faltaElPuerto);
      expect(
        leerEmparejamiento(url: 'ws://100.64.0.1', token: tokenBueno).problema,
        PairingProblem.faltaElPuerto,
      );
    });

    test('el host y el puerto van juntos en un solo parámetro', () {
      final texto = PairingCode.componer(pareja);
      // Partirlos permitiría que llegara uno sin el otro, y un emparejamiento a
      // medias es el que luego se ve como «no responde».
      expect(texto, contains('h=100.73.35.55%3A7845'));
    });

    test('no caduca, y eso es la decisión', () {
      // El token que lleva dentro **sí** es revocable —se rota desde Ajustes y eso
      // echa a quien esté dentro—, así que una caducidad aquí sería una segunda cosa
      // que caduca sin añadir seguridad: quien fotografíe la pantalla tiene el token,
      // y el remedio es rotarlo. Un reloj daría la sensación de protección sin la
      // protección.
      expect(PairingCode.caduca, isFalse);
    });
  });

  group('rotar el token cambia el código', () {
    test('el contenido del QR sale del token, así que rotar lo regenera', () {
      // La pregunta que lo motivó: «si roto el token, el QR se regenera solo?». Sí, y
      // el mecanismo es que la sección **observa** el token en vez de leerlo una vez —
      // rotar pone el estado nuevo y el widget se redibuja.
      //
      // Esto ata la mitad que se puede romper en silencio: que el código lleve el
      // token dentro. Si alguien lo compusiera de otra cosa —de la dirección sola, de
      // un valor guardado— rotar dejaría de tener efecto en el QR y el teléfono
      // escanearía un código muerto sin que nada lo dijera.
      const antes = ChannelToken(
        'MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3',
      );
      const despues = ChannelToken(
        'OTg3NjU0MzIxMHp5eHd2dXRzcnFwb25tbGtqaWhnZg',
      );

      final uno = PairingCode.componer(
        Pairing(url: Uri.parse('ws://100.64.0.1:7845'), token: antes),
      );
      final otro = PairingCode.componer(
        Pairing(url: Uri.parse('ws://100.64.0.1:7845'), token: despues),
      );

      expect(uno, isNot(otro));
      expect(PairingCode.leer(otro).emparejamiento!.token.value, despues.value);
      // Y el viejo ya no aparece: un QR que siguiera llevando el token anterior sería
      // exactamente lo que rotar viene a evitar.
      expect(otro, isNot(contains(antes.value)));
    });
  });

  group('el acento viaja en el saludo, no en el código', () {
    test('el código no lo lleva', () {
      // Es la decisión: en el QR quedaría **congelado** en el momento de emparejar, y
      // el día que se cambie el acento en el Mac habría dos fuentes de verdad para
      // algo que cambia.
      final texto = PairingCode.componer(pareja);
      expect(texto, isNot(contains('accent')));
      expect(texto, isNot(contains('a=')));
    });

    test('el saludo sí, y va y vuelve', () {
      const naranja = 0xFFE3B25C;
      final saludo = Welcome(
        protocol: ProtocolRange.mine,
        seq: 12,
        accent: naranja,
      );

      final devuelto = Frame.decode(saludo.encode()) as Welcome;
      expect(devuelto.accent, naranja);
      expect(devuelto.seq, 12);
    });

    test('un Mac más viejo saluda sin él, y eso no rompe nada', () {
      // Opcional a propósito: un campo obligatorio en el saludo rompería a cualquier
      // teléfono que no lo conozca, y la tolerancia hacia adelante del protocolo
      // existe justo para no tener que hacer eso.
      final viejo = Frame.decode(
        '{"t":"welcome","protocol":{"min":1,"current":1},"seq":3}',
      );
      expect(viejo, isA<Welcome>());
      expect((viejo as Welcome).accent, isNull);
    });
  });
}

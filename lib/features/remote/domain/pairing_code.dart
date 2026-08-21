import 'package:nexus/features/remote/domain/pairing.dart';

/// Lo que va dentro del QR.
///
/// **El QR no es un mecanismo de emparejamiento: es no teclear 43 caracteres.** Lleva
/// exactamente los dos valores que hoy se pegan a mano —dónde y con qué— y nada más.
/// Eso es lo que permite que la pantalla de escribirlo a mano siga existiendo y siga
/// siendo la de verdad: las dos rutas producen el mismo emparejamiento.
///
/// Y hay algo que el mockup de esta pantalla da por hecho y ya no vale: dibuja «Mac
/// detectado en la red · 192.168.1.42» y un pie que dice «comprueba que ambos están en
/// la misma red». Eso es descubrimiento por red local, que es justo lo que la decisión
/// `lo1` descartó al elegir **solo Tailscale**. Se sigue la forma del mockup —el código
/// grande, la salida a mano— y no su mecanismo.
abstract final class PairingCode {
  /// El esquema propio.
  ///
  /// Uno propio y no una URL `https` con parámetros: una `https` es **clicable**, y un
  /// token en una URL clicable acaba abierto en un navegador, en un historial y en un
  /// registro. Con `nexus://` no hay nada que lo abra por accidente, y si alguien pega
  /// el texto en un chat se ve lo que es.
  static const esquema = 'nexus';

  /// Cuánto dura el código.
  ///
  /// **No caduca, y es a propósito.** El token que lleva dentro sí es revocable —se
  /// rota desde Ajustes y eso echa a quien esté dentro—, así que la caducidad del
  /// código sería una segunda cosa que caduca sin añadir seguridad: quien fotografíe
  /// la pantalla tiene el token, y el remedio es rotarlo, no esperar cinco minutos.
  /// Poner un reloj aquí daría la sensación de protección sin la protección.
  static const caduca = false;

  /// Compone el texto del QR.
  static String componer(Pairing pareja) => Uri(
    scheme: esquema,
    host: 'pair',
    queryParameters: {
      // El host con su puerto, tal como se pega a mano. No se parte en dos
      // parámetros: partirlo permite que llegue uno sin el otro.
      'h': '${pareja.url.host}:${pareja.url.port}',
      't': pareja.token.value,
      // El esquema del socket, para que un día `wss` no obligue a otro formato.
      if (pareja.url.scheme != 'ws') 's': pareja.url.scheme,
    },
  ).toString();

  /// Lee lo que se escaneó.
  ///
  /// Devuelve el mismo par que la pantalla de escribirlo a mano, y **valida con la
  /// misma función**: si la validación fuera otra, el QR podría aceptar algo que el
  /// campo rechaza, y entonces habría dos ideas de qué es un emparejamiento válido.
  static ({PairingProblem? problema, Pairing? emparejamiento}) leer(
    String escaneado,
  ) {
    final leida = Uri.tryParse(escaneado.trim());
    if (leida == null || leida.scheme != esquema || leida.host != 'pair') {
      // Un QR cualquiera —una wifi, una URL, un billete— no es un error del usuario:
      // es que apuntó a otra cosa. Se dice como lo que es.
      return (problema: PairingProblem.noEsDeNexus, emparejamiento: null);
    }

    final host = leida.queryParameters['h'] ?? '';
    final token = leida.queryParameters['t'] ?? '';
    final esquemaDelSocket = leida.queryParameters['s'] ?? 'ws';

    return leerEmparejamiento(url: '$esquemaDelSocket://$host', token: token);
  }
}

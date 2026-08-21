import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/tailscale.dart';

/// Lo que el teléfono necesita para llegar al Mac: dónde y con qué.
///
/// **Se teclea a mano, y esa es la primera forma y no un apaño.** El QR —la 4.2—
/// transporta exactamente estos dos valores y nada más, así que no es un mecanismo
/// de emparejamiento: es no teclear un token de 43 caracteres en un teléfono. Y no
/// se puede construir antes que esto, porque comprobar un QR exige una cámara
/// apuntando a una pantalla.
@immutable
class Pairing {
  const Pairing({required this.url, required this.token});

  final Uri url;
  final ChannelToken token;

  /// La dirección sin el token, para poder enseñarla. El token nunca se enseña
  /// entero — igual que en el Mac, solo su huella.
  String get comoSeVe => '${url.host}:${url.port}';

  @override
  String toString() => 'Pairing($comoSeVe · ${token.fingerprint})';
}

/// Lo que mide un token del canal: 32 bytes en base64url sin relleno.
const _largoDelToken = 43;

/// Qué está mal en lo que se pegó.
enum PairingProblem {
  /// No se entiende como dirección.
  urlIlegible,

  /// No es `ws://` ni `wss://`. Es el error de pegar la del navegador.
  esquemaEquivocado,

  /// Sin puerto. Importa decirlo aparte: el canal escucha en uno fijo y una URL sin
  /// puerto se conectaría al 80, que no es donde está.
  faltaElPuerto,

  /// El token no tiene la pinta de un token del canal.
  tokenCorto,

  /// El QR es de otra cosa: una wifi, una URL, un billete.
  ///
  /// **No es un error de quien escanea**: es que apuntó a otro código. Decirlo así
  /// evita el mensaje que más molesta —«código inválido»— cuando lo único que pasó es
  /// que la cámara vio antes otro QR que había en la mesa.
  noEsDeNexus,
}

/// Lee lo que el usuario pegó.
///
/// Devuelve el problema o el emparejamiento. **Lo que no hace es exigir que la
/// dirección sea de Tailscale**, y eso es una decisión: la política de «solo por
/// Tailscale» ya la impone el Mac, que es quien decide dónde escucha. Repetirla aquí
/// sería tener la misma regla en dos sitios, y dos sitios se separan — el día que el
/// Mac cambie de criterio, el teléfono se quedaría negándose sin motivo. Sí se avisa
/// —ver [fueraDeTailscale]— porque avisar ayuda y bloquear adivina.
({PairingProblem? problema, Pairing? emparejamiento}) leerEmparejamiento({
  required String url,
  required String token,
}) {
  final tokenLimpio = token.trim();

  // **Sin esquema se le pone `ws://`.** Exigirlo era una regla mía y no del canal: lo
  // que se copia del Mac es `ws://100.x.y.z:7845`, pero lo que un humano teclea de
  // memoria es la dirección y el puerto — y rechazarlo con «tiene que empezar por
  // ws://» es hacer trabajar al usuario para cumplir un formato que este código puede
  // completar solo.
  //
  // Se detecta por la ausencia de `://` y no por lo que parezca: `100.73.35.55:7845`
  // se lee como un URI con **esquema `100.73.35.55`** —sintácticamente lo es— así que
  // sin esto pasaría el `tryParse` y fallaría por «esquema equivocado», que es
  // justamente el mensaje que menos ayuda.
  //
  // Y se completa **solo si parece una dirección**: con un espacio dentro no lo es, y
  // ponerle `ws://` a «esto no es una url» la convertía en un host raro sin puerto —
  // así que la basura salía como «falta el puerto» en vez de como ilegible. Completar
  // de más empeora el mensaje del caso que ya estaba bien.
  final crudo = url.trim();
  final parece =
      crudo.isNotEmpty &&
      !crudo.contains('://') &&
      !crudo.contains(RegExp(r'\s'));
  final limpia = parece ? 'ws://$crudo' : crudo;

  // Los 43 caracteres que salen de 32 bytes en base64url sin relleno. Se compara
  // con un margen y no con la igualdad exacta: el objetivo es atrapar el «pegué
  // media cosa», no validar criptografía — de eso ya se encarga el portero del Mac,
  // que es quien tiene el token de verdad contra el que comparar.
  if (tokenLimpio.length < _largoDelToken - 4) {
    return (problema: PairingProblem.tokenCorto, emparejamiento: null);
  }

  final leida = Uri.tryParse(limpia);
  if (leida == null || leida.host.isEmpty) {
    return (problema: PairingProblem.urlIlegible, emparejamiento: null);
  }
  if (leida.scheme != 'ws' && leida.scheme != 'wss') {
    return (problema: PairingProblem.esquemaEquivocado, emparejamiento: null);
  }
  if (!leida.hasPort) {
    return (problema: PairingProblem.faltaElPuerto, emparejamiento: null);
  }

  return (
    problema: null,
    emparejamiento: Pairing(url: leida, token: ChannelToken(tokenLimpio)),
  );
}

/// Si la dirección **no** parece de Tailscale.
///
/// Se usa para avisar, no para negarse. Una dirección de fuera del rango casi
/// siempre significa que se pegó la del wifi de casa, y el Mac no escucha ahí — así
/// que decirlo ahorra un «no conecta y no sé por qué». Pero no se bloquea: quien
/// tenga un montaje distinto sabe más que esta comprobación.
bool fueraDeTailscale(Uri url) {
  final ip = url.host;
  // Solo se opina de lo que se entiende. Un nombre de máquina —`mi-mac.ts.net`— no
  // se puede clasificar aquí sin resolverlo, y resolver para poder avisar sería
  // hacer red antes de conectar.
  final dir = InternetAddress.tryParse(ip);
  // Solo se opina de lo que se entiende como dirección. `tryParse` y no una expresión
  // regular propia: escribir a mano qué es una IP es cómo se acaba rechazando una
  // válida.
  if (dir == null) return false;
  return !Tailscale.esDeTailscale(dir);
}

/// Donde vive el emparejamiento entre arranques.
abstract class PairingStore {
  Future<Pairing?> read();
  Future<void> write(Pairing pairing);
  Future<void> clear();
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// El token que abre el canal del teléfono.
///
/// Va antes que el socket a propósito: **un servidor sin token no debería existir
/// ni un commit.** Escuchar primero y autenticar después deja una ventana en la que
/// cualquiera de la red de Tailscale entra, y esa ventana se olvida abierta.
///
/// Es un objeto y no un `String` por una razón concreta, y es la de abajo:
/// `toString`.
@immutable
class ChannelToken {
  const ChannelToken(this.value);

  /// Cuántos bytes de azar.
  ///
  /// 32 son 256 bits. Adivinarlo no es cuestión de tiempo sino de imposibilidad, y
  /// con el límite de diez intentos por minuto del portero ni eso hace falta. No se
  /// eligen más porque el token también se teclea o se escanea alguna vez, y 43
  /// caracteres ya es lo máximo razonable para eso.
  static const bytes = 32;

  /// Se genera con `Random.secure()`, que pide entropía al sistema.
  ///
  /// **No `Random()`**, que es un generador de números pseudoaleatorios sembrado
  /// con la hora: predecible con esfuerzo modesto, y aquí eso sería regalar el
  /// canal. Es el tipo de error que no se nota nunca — el token *parece* aleatorio.
  factory ChannelToken.generar([Random? azar]) {
    final fuente = azar ?? Random.secure();
    final crudo = List<int>.generate(bytes, (_) => fuente.nextInt(256));
    // `base64Url` y sin relleno: el token viaja en una cabecera y podría acabar
    // copiado en cualquier sitio. El alfabeto seguro para URL no necesita escapes
    // en ninguna capa por la que pase, y el `=` del final solo estorba.
    return ChannelToken(base64Url.encode(crudo).replaceAll('=', ''));
  }

  final String value;

  /// Un trozo corto para poder nombrarlo en el registro **sin escribirlo**.
  ///
  /// Seis caracteres bastan para distinguir dos tokens en una traza y no acercan a
  /// nadie a adivinar los 43.
  String get fingerprint =>
      value.length <= 6 ? '……' : '${value.substring(0, 6)}…';

  /// Y aquí está el motivo de que esto sea una clase.
  ///
  /// Esta app registra mucho —`debugPrint` en los controladores, `os_log` en los
  /// canales nativos, y la interpolación de Dart llama a `toString` sin avisar—.
  /// Un `String` desnudo se cuela en un registro el día que alguien escriba
  /// `debugPrint('token: $token')` de buena fe, y ese registro se queda en el
  /// disco. Con esto, ese mismo descuido imprime la huella y no el secreto.
  @override
  String toString() => 'ChannelToken($fingerprint)';

  @override
  bool operator ==(Object other) =>
      other is ChannelToken && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Donde vive el token entre arranques.
///
/// Interfaz propia para poder probar la rotación sin tocar el llavero del Mac: lo
/// que importa comprobar es **qué pasa al rotar**, no que el llavero guarde
/// cadenas.
abstract class ChannelTokenStore {
  /// El que hay, o `null` si nunca se generó.
  Future<ChannelToken?> read();

  Future<void> write(ChannelToken token);

  /// Lo borra. El canal queda sin token hasta que se genere otro, y **eso es lo
  /// correcto**: mejor un canal que no acepta a nadie que uno que acepta con un
  /// token que se quiso revocar.
  Future<void> clear();
}

import 'dart:io';

/// Encontrar la dirección de Tailscale, y **solo** esa.
///
/// La decisión 1 del contrato dice que el servidor escucha únicamente en la
/// interfaz de Tailscale, nunca en `0.0.0.0`. Esto es lo que la hace cumplible:
/// sin saber cuál es, «escuchar solo ahí» no se puede escribir.
///
/// Se reconoce **por el rango de direcciones y no por el nombre de la interfaz**.
/// En macOS Tailscale monta un `utun`, pero los `utun` los usan también las VPN
/// del sistema y cualquier otro túnel: elegir por nombre acabaría escuchando en la
/// VPN de la oficina. El rango `100.64.0.0/10` es de Tailscale por diseño —es el
/// espacio CGNAT que reserva para su red— y eso sí identifica.
abstract final class Tailscale {
  /// El rango que Tailscale reparte: `100.64.0.0` … `100.127.255.255`.
  ///
  /// Es `/10`, no `/8`: el primer octeto 100 solo pertenece a CGNAT cuando el
  /// segundo va de 64 a 127. Dar por bueno todo el `100.x` metería direcciones
  /// públicas de internet, que es exactamente lo contrario de lo que se busca.
  static bool esDeTailscale(InternetAddress dir) {
    if (dir.type != InternetAddressType.IPv4) return false;
    final partes = dir.address.split('.');
    if (partes.length != 4) return false;
    final primero = int.tryParse(partes[0]);
    final segundo = int.tryParse(partes[1]);
    if (primero != 100 || segundo == null) return false;
    return segundo >= 64 && segundo <= 127;
  }

  /// La dirección en la que escuchar, o `null` si no hay Tailscale.
  ///
  /// Toma la lista en vez de consultarla para poder probarse: en una máquina sin
  /// Tailscale —o en CI— no hay ninguna interfaz que mirar, y una función que
  /// consulta el sistema no se puede probar en el caso que importa.
  ///
  /// `null` no es un error que haya que esconder: es la respuesta que la
  /// comprobación de arranque tiene que convertir en «instala Tailscale», igual
  /// que hace con Claude Code.
  static InternetAddress? elegir(List<InternetAddress> direcciones) {
    for (final dir in direcciones) {
      if (esDeTailscale(dir)) return dir;
    }
    return null;
  }

  /// Lo mismo, preguntándole al sistema.
  static Future<InternetAddress?> buscar() async {
    final interfaces = await NetworkInterface.list(
      // Sin las de bucle: `127.0.0.1` no es Tailscale y aceptarla abriría el
      // canal a cualquier proceso del propio Mac, que es justo lo que la
      // validación de `Host` y `Origin` viene a cerrar por el otro lado.
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    return elegir([for (final i in interfaces) ...i.addresses]);
  }
}

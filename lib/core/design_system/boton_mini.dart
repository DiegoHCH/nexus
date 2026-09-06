import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';

/// Una acción sobre la corrida: icono con su nombre en el tooltip.
///
/// **Iconos y no palabras, y eso lo decidió una prueba**: «Recargar»,
/// «Reiniciar» y «Parar» en la misma fila desbordaban por 71 px, con el nombre
/// del entorno al lado.
///
/// Aquel «no hay ancho que alcance» era falso y conviene dejarlo escrito: el
/// panel medía **280** porque Material recorta ahí cualquier menú sin
/// `constraints`, no los 380 que yo creía. Con el ancho de verdad las palabras
/// caben. Se quedan los iconos porque son cuatro acciones —recargar, reiniciar,
/// registro, parar— y cuatro palabras en una fila con el nombre del entorno
/// convierten la fila en un párrafo; además es lo que hace la barra de la que se
/// copia esto.
///
/// El nombre no se pierde, se mueve al tooltip — y ahí sigue estando para quien
/// use un lector de pantalla, porque `IconButton` lo anuncia.
/// **Vive en el sistema de diseño porque ya son dos.** Lo escribió el panel de
/// correr y la botonera flotante necesita exactamente el mismo botón: copiarlo
/// habría dejado dos filas de acciones con dos densidades que acaban
/// discrepando en cuanto se toque una.
class BotonMini extends StatelessWidget {
  const BotonMini({
    super.key,
    required this.icono,
    required this.titulo,
    required this.onPulsar,
    this.activo = false,
    this.color,
  });

  final IconData icono;
  final String titulo;
  final VoidCallback onPulsar;

  /// Marcado. Lo usa el del registro: un botón que abre algo tiene que decir si
  /// está abierto, o se pulsa dos veces buscando lo que ya estaba.
  final bool activo;

  /// Su color, cuando el icono no basta para distinguirlo: el reinicio en verde
  /// y el parar en rojo, que es lo que hace cualquier barra de depuración. Sin
  /// esto son cuatro siluetas grises seguidas y se pulsa la de al lado.
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPulsar,
    tooltip: titulo,
    iconSize: 15,
    splashRadius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    constraints: const BoxConstraints(),
    visualDensity: VisualDensity.compact,
    color: activo ? context.colors.accent : (color ?? context.colors.faint),
    icon: Icon(icono),
  );
}

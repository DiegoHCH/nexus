import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';

/// En qué anda la conexión, dicho en pantalla.
///
/// Es la ficha `lo6` cumplida, y en esta app pesa más que en otras por una razón
/// concreta: **un encargo dura minutos y el orbe usa el silencio como estado
/// normal**, así que sin señal explícita «está pensando» y «no llego al Mac» se
/// dibujan idénticos. Quien mira la pantalla no puede distinguirlos, y esperar por
/// algo que no va a pasar es la peor forma de perder el tiempo.
class LinkBadge extends ConsumerWidget {
  const LinkBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final estado = ref.watch(linkStateProvider).value ?? LinkState.sinConexion;
    final (texto, color) = _decir(estado, colors);

    return Row(
      key: const ValueKey('estado-del-enlace'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Un punto y no un icono: cambia de color sin cambiar de forma, así que el
        // ojo lo lee sin releer.
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          texto,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  /// Los cuatro estados de la ficha, más el que no se arregla esperando.
  ///
  /// **«Reconectando» y «sin conexión» se dicen distinto** aunque las dos signifiquen
  /// que ahora mismo no hay Mac: en la primera el teléfono está haciendo algo y no
  /// hay nada que tocar, y en la segunda toca mirar si el Mac está encendido. Un solo
  /// mensaje para las dos manda a comprobar cosas mientras se arreglaba solo.
  (String, Color) _decir(LinkState estado, NexusColors colors) => switch (estado) {
    LinkState.conectado => ('conectado', colors.ok),
    LinkState.conectando => ('conectando', colors.mute),
    LinkState.reconectando => ('reconectando', colors.warn),
    LinkState.resincronizando => ('poniéndose al día', colors.warn),
    LinkState.sinConexion => ('sin conexión', colors.err),
    // Terminal: reintentar no lo arregla, así que el mensaje no puede sonar a
    // «espera un momento».
    LinkState.hayQueActualizar => ('hay que actualizar', colors.err),
  };
}

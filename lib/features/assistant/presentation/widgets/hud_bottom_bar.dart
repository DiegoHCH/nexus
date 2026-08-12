import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';

/// La franja de avisos de abajo (`hud-bottom` del mockup).
///
/// A la izquierda, **la consecuencia del permiso sobre la carpeta concreta**:
/// el diseño insiste en que el interruptor y su consecuencia se vean juntos,
/// porque «puede editar» en abstracto no asusta y «puede editar archivos en
/// front-mobile-b2c» sí. A la derecha, cómo salir de lo que está pasando.
class HudBottomBar extends StatelessWidget {
  const HudBottomBar({super.key, required this.consequence, this.escape});

  final String consequence;
  final String? escape;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexusSpacing.s6,
        0,
        NexusSpacing.s6,
        NexusSpacing.s4,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              consequence,
              style: NexusTypography.mono.copyWith(color: colors.faint),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (escape != null) ...[
            const SizedBox(width: NexusSpacing.s4),
            Text(
              escape!,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

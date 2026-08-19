import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';

/// Un punto rojo sobre algo, mientras quede una versión sin instalar.
///
/// Existe porque descartar el aviso no debería hacerlo desaparecer del todo:
/// «más tarde» es ahora no, no nunca. Sin esto, quien cierra el aviso pierde el
/// único rastro de que había algo, y la siguiente noticia llega cuando el
/// actualizador vuelva a preguntar — dos horas después.
///
/// Envuelve en vez de pintarse suelto para que el punto vaya **pegado** a lo que
/// lleva a la actualización, y no flotando en un sitio que haya que descubrir.
class PendingDot extends ConsumerWidget {
  const PendingDot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendiente = ref.watch(
      updatesControllerProvider.select((s) => s.notice?.isNewer ?? false),
    );
    if (!pendiente) return child;

    final colors = context.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        // Fuera del flujo y sin `Positioned` con tamaño: así el punto no cambia
        // la medida de lo que envuelve. Un icono que se mueve al aparecer un
        // aviso es peor que no avisar.
        Positioned(
          top: -2,
          right: -2,
          child: Semantics(
            label: context.strings.updateAvailable(''),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                // Rojo y no el acento: el cian ya significa otras cosas en este
                // HUD —está escuchando, está activo—, así que un punto cian no se
                // leería como algo pendiente.
                color: colors.err,
                shape: BoxShape.circle,
                // Un borde del color del fondo, para que el punto se separe de lo
                // que tiene debajo sin necesitar sombra.
                border: Border.all(color: colors.void_, width: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

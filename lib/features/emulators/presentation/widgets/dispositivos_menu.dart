import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/emulators/presentation/widgets/dispositivos_panel.dart';

/// Los dispositivos, a un clic desde el compositor.
///
/// **Existe porque Ajustes es el sitio equivocado para usarlos.** Ahí están bien
/// para configurar —mirar qué hay, ver estado—, pero arrancar un emulador es algo
/// que se hace a media faena, justo cuando no quieres irte de la conversación.
/// Es el mismo reparto que ya tienen los documentos —viven en su carpeta y se
/// abren desde un chip de aquí— y el cupo, que se lee en un panel en esta misma
/// fila.
///
/// Se copia la forma del `UsageMenu`: un `PopupMenuButton` con un solo elemento
/// deshabilitado dentro, que no es un menú de elegir sino un panel. Y su
/// `onOpened`, que es lo que hace que al desplegarlo la lista no sea de hace un
/// rato.
class DispositivosMenu extends ConsumerWidget {
  const DispositivosMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    // **Cuántos hay arriba, para el punto del icono.** Sin esto habría que
    // desplegar el menú para saber si queda un emulador encendido, y entonces el
    // atajo no ahorra nada: seguirías abriendo algo para preguntar.
    final arriba =
        ref
            .watch(emuladoresProvider)
            .value
            ?.emuladores
            .where((e) => e.corriendo)
            .length ??
        0;

    return PopupMenuButton<void>(
      color: colors.deep,
      tooltip: '',
      // Al desplegar se vuelve a preguntar. El panel enseña lo último que se supo
      // mientras llega, así que esto no cuesta una pantalla en blanco.
      onOpened: () {
        ref.invalidate(emuladoresProvider);
        ref.invalidate(dispositivosProvider);
      },
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: SizedBox(
            // 360 y no 320: con 320 la fila de un emulador apagado —punto,
            // nombre, «en frío» y «Arrancar»— iba justa incluso con los botones
            // apretados, y una fila que va justa desborda con el primer nombre
            // largo.
            width: 360,
            child: const DispositivosPanel(compacto: true),
          ),
        ),
      ],
      child: Semantics(
        label: strings.sectionEmulators,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.phone_iphone,
                size: 15,
                // Con algo arriba el icono se enciende, como el micrófono cuando
                // la voz está abierta: el mismo lenguaje en la misma fila.
                color: arriba > 0 ? colors.accent : colors.faint,
              ),
            ),
            if (arriba > 0)
              // Fuera del flujo y sin tamaño propio, copiado de `PendingDot`: así
              // el punto no mueve el icono al aparecer. Un icono que se desplaza
              // cuando algo cambia es peor que no avisar.
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    // El acento y no el rojo: un emulador encendido no es un
                    // problema pendiente, es algo que está pasando. El rojo en
                    // este HUD ya significa «hay algo sin resolver».
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.void_, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

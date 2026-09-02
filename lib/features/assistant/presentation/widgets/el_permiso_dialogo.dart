import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/presentation/providers/el_permiso_pendiente.dart';

/// El diálogo con el que se concede o se niega lo que Claude está pidiendo.
///
/// **No se puede cerrar sin contestar**: ni con Escape ni pulsando fuera. Al
/// otro lado hay un proceso detenido esperando una respuesta, y un diálogo que
/// se esfuma sin decir nada lo deja esperando para siempre. Los dos botones son
/// las dos únicas salidas.
class ElPermisoDialogo extends ConsumerWidget {
  const ElPermisoDialogo({super.key, required this.peticion});

  final PeticionDePermiso peticion;

  /// Lo engancha al árbol: mientras haya algo en la fila, se enseña.
  ///
  /// Va como widget dentro del árbol y no como `showDialog`, y esa es la
  /// diferencia que importa: la fila puede vaciarse por su cuenta —el encargo
  /// se paró, la respuesta llegó por otro lado— y un diálogo empujado a la pila
  /// de navegación habría que acordarse de sacarlo. Así se quita cuando el
  /// valor se va, sin que nadie tenga que recordarlo.
  /// `Positioned.fill` y no un hijo suelto: dentro de un `Stack` un hijo sin
  /// posicionar se mide por su contenido, y el velo tiene que tapar la pantalla
  /// entera, no el tamaño del diálogo.
  static Widget enElArbol() => const Positioned.fill(child: _Puerta());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final colors = context.colors;
    final pendiente = ref.read(elPermisoPendienteProvider.notifier);

    return AlertDialog(
      backgroundColor: colors.rise,
      title: Text(
        strings.permisoTitulo,
        style: NexusTypography.body.copyWith(color: colors.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.permisoPregunta(peticion.nombreVisible),
            style: NexusTypography.body.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 12),
          // Qué exactamente, en monoespaciada y sin recortar a una línea: lo
          // que se aprueba es esto y no el nombre de la herramienta. Con tope
          // de alto, porque un `Write` trae el contenido entero del archivo y
          // sin tope el diálogo se sale de la pantalla.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Text(
                peticion.resumen,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
            ),
          ),
          if (peticion.escribe) ...[
            const SizedBox(height: 12),
            Text(
              strings.permisoEscribe,
              style: NexusTypography.mono.copyWith(color: colors.warn),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: pendiente.denegar,
          child: Text(strings.permisoDenegar),
        ),
        TextButton(
          onPressed: pendiente.conceder,
          child: Text(strings.permisoConceder),
        ),
        // La salida de «y no me lo preguntes más», solo si el CLI la ofrece.
        // Sin ella un encargo que toca quince archivos son quince diálogos, y
        // eso es peor que conceder sin preguntar — que es lo que había.
        if (peticion.sePuedeConcederTodo)
          TextButton(
            onPressed: pendiente.concederTodo,
            style: TextButton.styleFrom(foregroundColor: colors.accent),
            child: Text(strings.permisoConcederTodo),
          ),
      ],
    );
  }
}

class _Puerta extends ConsumerWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peticion = ref.watch(elPermisoPendienteProvider);
    if (peticion == null) return const SizedBox.shrink();

    final colors = context.colors;
    // El velo lo pone esto y no `showDialog`, porque el diálogo tampoco viene
    // de ahí. `PopScope` bloquea el Escape; el velo, sin `GestureDetector`
    // encima, se come los clics de fuera sin convertirlos en un cierre.
    return PopScope(
      canPop: false,
      child: ColoredBox(
        color: colors.scrim,
        child: Center(child: ElPermisoDialogo(peticion: peticion)),
      ),
    );
  }
}

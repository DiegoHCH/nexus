import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/platform/status_item_channel.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// Mantiene el icono de la barra de estado al día con el orbe.
///
/// No pinta nada: vive en el árbol solo para tener a quién escuchar. Va aquí y
/// no en el controlador porque el estado del orbe es de **la conversación en
/// foco**, y eso es una noción de pantalla — con tres conversaciones a la vez,
/// el controlador no sabe cuál se está mirando.
class StatusPresence extends ConsumerWidget {
  const StatusPresence({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select` y no el estado entero: si no, cada delta de texto que llega de
    // Claude cruzaría el canal nativo. Con esto solo se cruza al cambiar de
    // estado, que son unas pocas veces por turno.
    ref.listen<NexusOrbState>(
      assistantControllerProvider(conversationId).select((s) => s.orbState),
      (previous, next) => StatusItemChannel.show(next.name),
    );
    return const SizedBox.shrink();
  }
}

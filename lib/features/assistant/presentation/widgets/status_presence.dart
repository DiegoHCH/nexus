import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/core/platform/status_item_channel.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';

/// Mantiene el icono de la barra de estado al día, y le da su menú.
///
/// No pinta nada: vive en el árbol solo para tener a quién escuchar y de dónde
/// sacar el idioma. Va aquí y no en el controlador porque el estado del orbe es
/// de **la conversación en foco**, y eso es una noción de pantalla — con tres
/// conversaciones a la vez, el controlador no sabe cuál se está mirando.
class StatusPresence extends ConsumerStatefulWidget {
  const StatusPresence({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<StatusPresence> createState() => _StatusPresenceState();
}

class _StatusPresenceState extends ConsumerState<StatusPresence> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // En `didChangeDependencies` y no en `initState`: los rótulos salen del
    // diccionario, que cuelga del árbol, y así se rehacen solos si se cambia el
    // idioma en Ajustes sin reiniciar.
    final strings = context.strings;
    StatusItemChannel.setMenu(
      talk: strings.statusTalk,
      show: strings.statusShow,
      settings: strings.openSettings,
      quit: strings.statusQuit,
    );
    StatusItemChannel.onAction(
      talk: () => ref
          .read(assistantControllerProvider(widget.conversationId).notifier)
          .toggleVoice(),
      settings: () {
        if (mounted) SettingsPage.open(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // `select` y no el estado entero: si no, cada delta de texto que llega de
    // Claude cruzaría el canal nativo. Con esto solo se cruza al cambiar de
    // estado, que son unas pocas veces por turno.
    ref.listen<NexusOrbState>(
      assistantControllerProvider(widget.conversationId).select((s) => s.orbState),
      (previous, next) => StatusItemChannel.show(next.name),
    );
    return const SizedBox.shrink();
  }
}

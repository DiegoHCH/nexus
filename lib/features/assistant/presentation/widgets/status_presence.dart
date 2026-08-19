import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/core/platform/status_item_channel.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
import 'package:nexus/features/updates/presentation/widgets/update_modal.dart';
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
    _rehacerMenu();
  }

  /// El menú se rehace cuando cambian los textos **o el aviso de versión**: es la
  /// única fila que aparece y desaparece.
  void _rehacerMenu() {
    // En `didChangeDependencies` y no en `initState`: los rótulos salen del
    // diccionario, que cuelga del árbol, y así se rehacen solos si se cambia el
    // idioma en Ajustes sin reiniciar.
    final strings = context.strings;
    final aviso = ref.read(updatesControllerProvider).notice;
    StatusItemChannel.setMenu(
      talk: strings.statusTalk,
      show: strings.statusShow,
      settings: strings.openSettings,
      quit: strings.statusQuit,
      update: aviso != null && aviso.isNewer
          ? strings.updateAvailable(aviso.latest ?? '')
          : null,
    );
    StatusItemChannel.onAction(
      talk: () => ref
          .read(assistantControllerProvider(widget.conversationId).notifier)
          .toggleVoice(),
      settings: () {
        if (mounted) SettingsPage.open(context);
      },
      // La fila del aviso saca la modal, que es donde se instala. Antes abría el
      // navegador y ahí se acababa lo que la app podía hacer por ti.
      update: () {
        if (mounted) UpdateModal.open(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // `select` y no el estado entero: si no, cada delta de texto que llega de
    // Claude cruzaría el canal nativo. Con esto solo se cruza al cambiar de
    // estado, que son unas pocas veces por turno.
    // Y si aparece una versión nueva mientras la app está abierta, el menú se
    // rehace: si no, el aviso no llegaría hasta el siguiente arranque.
    ref.listen(
      updatesControllerProvider.select((s) => s.notice),
      (_, _) => _rehacerMenu(),
    );

    ref.listen<NexusOrbState>(
      assistantControllerProvider(widget.conversationId).select((s) => s.orbState),
      (previous, next) => StatusItemChannel.show(next.name),
    );
    return const SizedBox.shrink();
  }
}

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/core/platform/status_item_channel.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
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
    // Y los del visor de documentos, que es la otra ventana nativa con texto
    // propio. Va aquí porque este es el sitio que ya se rehace cuando cambia el
    // idioma: montar otra máquina igual al lado sería tener dos que mantener.
    ref
        .read(artifactsDataSourceProvider)
        .textos(
          permitir: strings.allowScriptsAndNetwork,
          permitirAyuda: strings.allowScriptsExplainer,
        );
    StatusItemChannel.onAction(
      talk: () => ref
          .read(assistantControllerProvider(widget.conversationId).notifier)
          .toggleVoice(),
      settings: () {
        if (mounted) SettingsPage.open(context);
      },
      // La fila del aviso vuelve a preguntar, y el aviso sale arriba a la
      // derecha. Antes abría el navegador, y ahí se acababa lo que la app podía
      // hacer por ti.
      update: ref.read(updatesControllerProvider.notifier).comprobarAhora,
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
      assistantControllerProvider(
        widget.conversationId,
      ).select((s) => s.orbState),
      (previous, next) => StatusItemChannel.show(
        next.name,
        accent: _acento(ref.read(accentControllerProvider)),
      ),
    );

    // El punto rojo del icono, que sobrevive a descartar el aviso. Se manda al
    // cambiar el aviso y no en cada estado del orbe: el lado nativo lo recuerda.
    ref.listen(
      updatesControllerProvider.select((s) => s.notice?.isNewer ?? false),
      (_, pendiente) => StatusItemChannel.show(
        ref
            .read(assistantControllerProvider(widget.conversationId))
            .orbState
            .name,
        pending: pendiente,
      ),
    );

    // Y el acento, para que la marca de la barra no sea el único sitio de la
    // interfaz que se queda cian cuando todo lo demás cambia de color.
    ref.listen(accentControllerProvider, (_, elegido) {
      StatusItemChannel.show(
        ref
            .read(assistantControllerProvider(widget.conversationId))
            .orbState
            .name,
        accent: _acento(elegido),
      );
    });
    return const SizedBox.shrink();
  }

  /// El acento en `#RRGGBB` para el icono de la barra.
  ///
  /// Se elige contra **la apariencia del sistema y no la del tema de la app**, y
  /// eso no es un descuido: el icono se pinta sobre la barra de menús del Mac, que
  /// sigue al sistema. Con la app en claro y el Mac en oscuro, usar el tono claro
  /// dejaría un acento apagado sobre una barra negra.
  String _acento(Accent elegido) {
    final color = elegido.forBrightness(
      PlatformDispatcher.instance.platformBrightness,
    );
    return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Las conversaciones abiertas, apiladas en vertical: una esfera por cada una,
/// **incluida la que tienes delante**, que va marcada.
///
/// Funciona como pestañas sin serlo. El diseño descarta las pestañas de
/// navegador y el panel lateral, así que se reutiliza el único sujeto que el
/// HUD ya tiene —el orbe— y la actual se distingue por marca, no por ausencia:
/// esconderla dejaba la lista sin decir en cuál estás.
class ConversationDock extends ConsumerWidget {
  const ConversationDock({super.key});

  /// Todas las fichas miden lo mismo. Ajustar cada una a su nombre dejaba la
  /// columna en escalera, y una lista con los bordes desalineados se lee como
  /// elementos sueltos en vez de como un conjunto entre el que se elige.
  static const tabWidth = 190.0;
  static const tabHeight = 50.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final all = conversations.items;
    if (conversations.isEmpty) return const SizedBox.shrink();

    // En columna: las fichas se apilan hacia arriba desde la esquina. Cada
    // ficha sigue siendo horizontal —orbe y nombre en línea— así que la
    // columna crece poco y deja libre el centro, que es del orbe grande.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final conversation in all)
          _DockOrb(
            conversation: conversation,
            isFocused: conversation.id == conversations.focused?.id,
            onTap: () =>
                ref.read(conversationsProvider.notifier).focus(conversation.id),
            onClose: () =>
                ref.read(conversationsProvider.notifier).close(conversation.id),
          ),
        if (!conversations.isFull) const _OpenAnother(),
      ],
    );
  }
}

class _DockOrb extends ConsumerStatefulWidget {
  const _DockOrb({
    required this.conversation,
    required this.isFocused,
    required this.onTap,
    required this.onClose,
  });

  final Conversation conversation;

  /// Es la que estás mirando. Se marca en vez de esconderse: una fila que
  /// oculta la actual no dice en cuál estás.
  final bool isFocused;

  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  ConsumerState<_DockOrb> createState() => _DockOrbState();
}

class _DockOrbState extends ConsumerState<_DockOrb> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final conversation = widget.conversation;
    final hud = ref.watch(assistantControllerProvider(conversation.id));
    final home = ref.watch(homeDirectoryProvider);
    final name = conversation.folderPath.split('/').last;
    final working = hud.orbState == NexusOrbState.think;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s2),
      child: SizedBox(
        width: ConversationDock.tabWidth,
        height: ConversationDock.tabHeight,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Tooltip(
            message: conversation.folderPath.replaceFirst(home, '~'),
            child: InkWell(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.only(right: NexusSpacing.s3),
                decoration: BoxDecoration(
                  // La actual se marca con fondo y filo cian; las demás solo se
                  // insinúan al pasar por encima. Es el mismo recurso que el
                  // interruptor de permisos usa para decir cuál está puesta.
                  color: widget.isFocused
                      ? colors.cyan.withValues(alpha: 0.07)
                      : null,
                  border: Border.all(
                    color: widget.isFocused
                        ? colors.cyan.withValues(alpha: 0.45)
                        : (_hovering ? colors.rule2 : Colors.transparent),
                  ),
                  borderRadius: BorderRadius.circular(NexusRadius.sm),
                ),
                // En línea, no apilado: el nombre al lado del orbe. Apilados
                // ocupaban el alto de dos elementos por conversación y con tres
                // abiertas la esquina se convertía en una torre.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: Stack(
                        children: [
                          // Sin horizonte: a este tamaño la línea no se lee y solo
                          // ensucia. El movimiento del orbe ya distingue el estado.
                          Positioned.fill(
                            child: NexusOrb(
                              state: hud.orbState,
                              showHorizon: false,
                            ),
                          ),
                          // Cerrar tiene que verse. Estaba en el clic derecho, y un
                          // gesto que nadie descubre equivale a no poder cerrarla:
                          // las conversaciones parecían aparecidas de la nada y
                          // fijas para siempre.
                          if (_hovering)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: InkWell(
                                onTap: widget.onClose,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.void_,
                                    border: Border.all(color: colors.rule2),
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 10,
                                    color: colors.faint,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.s2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: Text(
                        name,
                        style: NexusTypography.label.copyWith(
                          color: widget.isFocused
                              ? colors.ink
                              : (working ? colors.cyan : colors.faint),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El hueco de «Nueva», del mismo tamaño que una conversación y justo debajo:
/// así se ve cuántas caben —hasta tres— sin tener que contarlas ni leer un
/// aviso. Cuando no quedan carpetas libres o ya hay tres, desaparece.
class _OpenAnother extends ConsumerWidget {
  const _OpenAnother();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final home = ref.watch(homeDirectoryProvider);
    // Todas las carpetas emparejadas, también las que ya tienen conversación:
    // son **sesiones independientes**, así que abrir dos sobre el mismo repo
    // es legítimo —una para revisar, otra para escribir— y cada una lleva su
    // propia memoria.
    final folders = ref.watch(workspaceControllerProvider).folders;
    if (folders.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: context.strings.openAnotherConversation,
      onSelected: (path) => ref.read(conversationsProvider.notifier).open(path),
      itemBuilder: (context) => [
        for (final folder in folders)
          PopupMenuItem(
            value: folder.path,
            child: Text(folder.displayPath(home)),
          ),
      ],
      child: Container(
        width: ConversationDock.tabWidth,
        height: ConversationDock.tabHeight,
        padding: const EdgeInsets.only(right: NexusSpacing.s3),
        decoration: BoxDecoration(
          border: Border.all(color: colors.rule),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: Icon(Icons.add, size: 18, color: colors.faint),
            ),
            const SizedBox(width: NexusSpacing.s2),
            Text(
              context.strings.newConversation,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

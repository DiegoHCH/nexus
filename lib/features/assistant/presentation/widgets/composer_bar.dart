import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// La caja para escribirle, con sus controles alrededor.
///
/// Los ajustes de la conversación —dónde trabaja, con qué cuenta, qué puede
/// tocar— estaban arriba del todo, lejos de donde se escribe. Aquí están donde
/// se decide: se lee la carpeta justo antes de pedir algo, y se cambia el
/// permiso sin cruzar la pantalla. Es la forma del compositor de Claude Code, y
/// se adopta por lo mismo que la organización del vault: si la herramienta que
/// tienes al lado ya resolvió dónde va cada cosa, inventar otra distribución
/// solo obliga a aprender dos.
///
/// Arriba, lo que **no** se cambia a menudo: carpeta, cuenta, si se le puede
/// hablar. Abajo, lo que sí: el permiso, el micrófono, y a la derecha el modelo
/// y cuánto contexto lleva ocupado.
class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({
    super.key,
    required this.onSubmit,
    required this.onFocusChanged,
    this.folderPath,
    this.meter = const SessionMeter(),
    this.voiceActive = false,
    this.onToggleVoice,
  });

  final ValueChanged<String> onSubmit;
  final ValueChanged<bool> onFocusChanged;
  final String? folderPath;
  final SessionMeter meter;
  final bool voiceActive;
  final VoidCallback? onToggleVoice;

  @override
  ConsumerState<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends ConsumerState<ComposerBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() => widget.onFocusChanged(_focusNode.hasFocus);

  void _handleSubmit(String value) {
    if (value.trim().isEmpty) return;
    widget.onSubmit(value);
    _controller.clear();
  }

  void _handleClear() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final workspace = ref.watch(workspaceControllerProvider);
    final folder = workspace.folders
        .where((item) => item.path == widget.folderPath)
        .firstOrNull;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.cyan.withValues(alpha: 0.28)),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.7],
          colors: [
            colors.cyan.withValues(alpha: 0.045),
            colors.cyan.withValues(alpha: 0),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NexusSpacing.s8,
          NexusSpacing.s4,
          NexusSpacing.s8,
          NexusSpacing.s5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Chips(folder: folder),
            const SizedBox(height: NexusSpacing.s3),
            _Field(
              controller: _controller,
              focusNode: _focusNode,
              onSubmit: _handleSubmit,
              onClear: _handleClear,
            ),
            const SizedBox(height: NexusSpacing.s3),
            _Controls(
              workspace: workspace,
              meter: widget.meter,
              voiceActive: widget.voiceActive,
              onToggleVoice: widget.onToggleVoice,
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que describe dónde estás, en fila y sin ruido: carpeta, cuenta y si se le
/// puede hablar a este proyecto.
class _Chips extends StatelessWidget {
  const _Chips({required this.folder});

  final PairedFolder? folder;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final paired = folder;
    if (paired == null) {
      return _Chip(
        icon: Icons.folder_off_outlined,
        label: strings.noFolderNothingToTouch,
      );
    }

    final profile = paired.claudeProfile?.split('/').last;
    return Row(
      children: [
        _Chip(icon: Icons.folder_outlined, label: paired.name),
        if (profile != null && profile.startsWith('.claude-'))
          _Chip(icon: Icons.badge_outlined, label: profile.substring(8)),
        _Chip(
          icon: paired.modality.allowsVoice ? Icons.graphic_eq : Icons.keyboard,
          label: paired.modality.allowsVoice
              ? strings.sectionVoice
              : strings.textOnly,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: NexusSpacing.s3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: colors.rule),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: colors.faint),
            const SizedBox(width: 6),
            Text(
              label,
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Enter envía; ⇧Enter hace salto de línea. Se intercepta la tecla porque un
    // campo de varias líneas trata Enter como salto por defecto, y entonces no
    // habría forma de enviar sin ratón.
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey != LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }
        onSubmit(controller.text);
        return KeyEventResult.handled;
      },
      // En escritorio Flutter le cuelga una barra de desplazamiento al campo en
      // cuanto pasa de una línea, y en una caja de seis se ve como un cuerpo
      // extraño. El scroll sigue funcionando con la rueda y con el cursor.
      child: ScrollConfiguration(
        behavior: const _NoScrollbar(),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) => TextField(
            controller: controller,
            focusNode: focusNode,
            style: NexusTypography.body.copyWith(color: colors.ink),
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: context.strings.composerHint,
              hintStyle: NexusTypography.body.copyWith(color: colors.faint),
              suffixIcon: value.text.isEmpty
                  ? null
                  : Tooltip(
                      message: context.strings.clearWhatYouWrote,
                      child: IconButton(
                        onPressed: onClear,
                        padding: EdgeInsets.zero,
                        splashRadius: 14,
                        iconSize: 16,
                        color: colors.faint,
                        hoverColor: colors.cyan.withValues(alpha: 0.12),
                        icon: const Icon(Icons.backspace_outlined),
                      ),
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se toca a menudo: permiso, micrófono, y a la derecha lo que informa.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.workspace,
    required this.meter,
    required this.voiceActive,
    required this.onToggleVoice,
  });

  final Workspace workspace;
  final SessionMeter meter;
  final bool voiceActive;
  final VoidCallback? onToggleVoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final canWrite = workspace.permission.canWrite;

    return Row(
      children: [
        // El permiso, como un menú y no como un interruptor: al desplegarlo se
        // lee la consecuencia de cada opción, que es lo que hay que saber para
        // elegir bien y no cabía junto a un conmutador.
        PopupMenuButton<FilePermission>(
          color: colors.deep,
          tooltip: '',
          initialValue: workspace.permission,
          onSelected: ref
              .read(workspaceControllerProvider.notifier)
              .setPermission,
          itemBuilder: (context) => [
            for (final option in FilePermission.values)
              PopupMenuItem<FilePermission>(
                value: option,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.canWrite ? strings.canEdit : strings.readOnly,
                      style: NexusTypography.data.copyWith(color: colors.ink),
                    ),
                    Text(
                      option.canWrite
                          ? strings.canEditExplainer
                          : strings.readOnlyExplainer,
                      style: NexusTypography.mono.copyWith(color: colors.faint),
                    ),
                  ],
                ),
              ),
          ],
          child: Row(
            children: [
              Icon(
                canWrite ? Icons.edit_outlined : Icons.lock_outline,
                size: 13,
                color: canWrite ? colors.warn : colors.faint,
              ),
              const SizedBox(width: 6),
              Text(
                canWrite ? strings.canEdit : strings.readOnly,
                style: NexusTypography.label.copyWith(
                  color: canWrite ? colors.warn : colors.faint,
                ),
              ),
              Icon(Icons.expand_more, size: 14, color: colors.faint),
            ],
          ),
        ),
        const SizedBox(width: NexusSpacing.s4),
        if (onToggleVoice case final toggle?)
          IconButton(
            onPressed: toggle,
            tooltip: voiceActive
                ? strings.micOpenHint
                : strings.sayStopToInterrupt,
            iconSize: 15,
            splashRadius: 15,
            color: voiceActive ? colors.cyan : colors.faint,
            icon: Icon(voiceActive ? Icons.mic : Icons.mic_none),
          ),
        const Spacer(),
        if (meter.displayModel case final model?)
          Text(
            model,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
        if (meter.contextPercent case final percent?) ...[
          const SizedBox(width: NexusSpacing.s3),
          Tooltip(
            message: strings.contextUsed(percent),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 3,
                      backgroundColor: colors.rule,
                      // Ámbar al acercarse al tope: a partir del 85% la
                      // conversación se comprime sola, y verlo venir explica
                      // por qué de pronto hay un turno de más.
                      color: percent >= 85 ? colors.warn : colors.cyan,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$percent%',
                  style: NexusTypography.data.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NoScrollbar extends MaterialScrollBehavior {
  const _NoScrollbar();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

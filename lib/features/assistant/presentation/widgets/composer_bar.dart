import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer/composer_chips.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer/composer_menus.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer/usage_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/usecases/attached_files.dart';
import 'package:nexus/features/assistant/presentation/widgets/attachment_strip.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';
import 'package:nexus/features/onboarding/presentation/widgets/tour_anchor.dart';
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

  /// Recibe **el texto y las rutas por separado**, no un texto ya compuesto.
  /// Quién decide qué se le manda a Claude es el controlador, que además tiene
  /// los textos del idioma; la caja solo dice qué se escribió y qué se adjuntó.
  final void Function(String text, List<String> attachments) onSubmit;
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

  /// Las rutas que acompañan a lo que se está escribiendo. Viven aquí y no en
  /// un provider porque son del mensaje a medio escribir, no de la
  /// conversación: al enviarlo se van con él.
  var _attachments = <String>[];

  /// Hay algo encima esperando a que lo sueltes.
  var _dragging = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() => widget.onFocusChanged(_focusNode.hasFocus);

  void _handleSubmit(String value) {
    if (value.trim().isEmpty && _attachments.isEmpty) return;
    widget.onSubmit(value, _attachments);
    _controller.clear();
    setState(() => _attachments = const []);
  }

  void _attach(Iterable<String> paths) =>
      setState(() => _attachments = AttachedFiles.add(_attachments, paths));

  void _detach(String path) =>
      setState(() => _attachments = [..._attachments]..remove(path));

  void _handleClear() {
    _controller.clear();
    // Borrar la caja se lleva también los adjuntos: son parte del mensaje que
    // se está descartando, y dejarlos pegados a un texto que ya no existe los
    // colaría en la siguiente petición.
    setState(() => _attachments = const []);
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
    // La carpeta de esta conversación; y sin conversación abierta —el primer
    // arranque, antes de escribir nada— la activa, que es donde iría a parar lo
    // que escribas. Sin esto, al abrir la app no salía ni modelo ni esfuerzo y
    // tampoco había dónde elegirlos: los controles existían apagados.
    final folder =
        workspace.folders
            .where((item) => item.path == widget.folderPath)
            .firstOrNull ??
        workspace.folders
            .where((item) => item.path == workspace.activePath)
            .firstOrNull ??
        workspace.folders.firstOrNull;

    return DropTarget(
      // Alrededor de toda la barra y no solo de la caja de texto: quien
      // arrastra apunta al sitio donde escribe, no a un rectángulo de 30 px de
      // alto, y fallar el blanco devuelve el archivo a su carpeta de un salto.
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _attach(detail.files.map((file) => file.path));
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.accent.withValues(alpha: _dragging ? 0.9 : 0.28),
              width: _dragging ? 2 : 1,
            ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.7],
            colors: [
              colors.accent.withValues(alpha: _dragging ? 0.16 : 0.045),
              colors.accent.withValues(alpha: 0),
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
              ComposerChips(folder: folder, folderPath: widget.folderPath),
              const SizedBox(height: NexusSpacing.s3),
              AttachmentStrip(paths: _attachments, onRemove: _detach),
              _Field(
                controller: _controller,
                focusNode: _focusNode,
                onSubmit: _handleSubmit,
                onClear: _handleClear,
              ),
              const SizedBox(height: NexusSpacing.s3),
              _Controls(
                folder: folder,
                workspace: workspace,
                meter: widget.meter,
                voiceActive: widget.voiceActive,
                onToggleVoice: widget.onToggleVoice,
                onAttach: _attach,
              ),
              // Solo mientras hay algo encima. macOS ya enseña la miniatura de lo
              // que llevas colgando del cursor; lo que falta decir es que **este**
              // sitio lo acepta, y eso se dice una vez y en pequeño.
              if (_dragging) ...[
                const SizedBox(height: NexusSpacing.s2),
                Row(
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      size: 13,
                      color: colors.accent,
                    ),
                    const SizedBox(width: NexusSpacing.s2),
                    Text(
                      context.strings.dropHere,
                      style: NexusTypography.label.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
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
                        hoverColor: colors.accent.withValues(alpha: 0.12),
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
    required this.folder,
    required this.workspace,
    required this.meter,
    required this.voiceActive,
    required this.onToggleVoice,
    required this.onAttach,
  });

  /// La carpeta de esta conversación: de ella salen la cuenta, el modelo y el
  /// esfuerzo, porque los tres se deciden por carpeta.
  final PairedFolder? folder;
  final Workspace workspace;
  final SessionMeter meter;
  final bool voiceActive;
  final VoidCallback? onToggleVoice;
  final void Function(Iterable<String>) onAttach;

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
        const SizedBox(width: NexusSpacing.s3),
        MoreMenu(onAttach: onAttach),
        const SizedBox(width: NexusSpacing.s2),
        if (onToggleVoice case final toggle?)
          IconButton(
            onPressed: toggle,
            tooltip: voiceActive
                ? strings.micOpenHint
                : strings.sayStopToInterrupt,
            iconSize: 15,
            splashRadius: 15,
            color: voiceActive ? colors.accent : colors.faint,
            icon: Icon(voiceActive ? Icons.mic : Icons.mic_none),
          ),
        const Spacer(),
        ModelMenu(folder: folder, meter: meter),
        const SizedBox(width: NexusSpacing.s3),
        EffortMenu(folder: folder),
        const SizedBox(width: NexusSpacing.s3),
        TourAnchor(
          stop: TourStop.meter,
          child: UsageMenu(meter: meter, claudeProfile: folder?.claudeProfile),
        ),
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

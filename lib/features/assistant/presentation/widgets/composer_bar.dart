import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/model_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
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

  /// Mete texto en la caja sin pisar lo que ya haya escrito: adjuntar un
  /// archivo es añadir su ruta a lo que estabas pidiendo, no empezar de nuevo.
  void _insert(String text) {
    final actual = _controller.text.trimRight();
    _controller.text = actual.isEmpty ? text : '$actual $text';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _focusNode.requestFocus();
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
              folder: folder,
              workspace: workspace,
              meter: widget.meter,
              voiceActive: widget.voiceActive,
              onToggleVoice: widget.onToggleVoice,
              onInsert: _insert,
            ),
          ],
        ),
      ),
    );
  }
}

/// Dónde estás, en fila: carpeta, repositorio, rama, cuenta y si se le puede
/// hablar a este proyecto.
///
/// La carpeta **se puede cambiar desde aquí**: antes, sin ninguna emparejada,
/// esto era una etiqueta que decía que no había carpeta y no hacía nada — un
/// cartel en el sitio donde uno va a arreglarlo.
class _Chips extends ConsumerWidget {
  const _Chips({required this.folder});

  final PairedFolder? folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final workspace = ref.watch(workspaceControllerProvider);
    final paired = folder;
    // La rama es la del sitio donde va a trabajar Claude, que con una raíz de
    // varios repos no es la carpeta emparejada sino el repo elegido.
    final git = paired == null
        ? null
        : ref.watch(gitInfoProvider(paired.workingDirectory)).value;
    final repos = paired == null
        ? const <String>[]
        : ref.watch(reposInsideProvider(paired.path)).value ?? const [];

    return Row(
      children: [
        PopupMenuButton<String>(
          color: colors.deep,
          tooltip: '',
          onSelected: (value) async {
            if (value == '__pair__') {
              await ref.read(workspaceControllerProvider.notifier).pairFolder();
              return;
            }
            final abierta = ref.read(conversationsProvider).focused;
            if (abierta == null) {
              // Sin ninguna abierta no se crea nada: se apunta la carpeta y la
              // conversación nacerá cuando escribas o hables. Crear una aquí
              // llenaría el dock de conversaciones vacías cada vez que miras
              // dónde ibas a trabajar.
              await ref
                  .read(workspaceControllerProvider.notifier)
                  .setActive(value);
              return;
            }

            final dicho = ref
                .read(assistantControllerProvider(abierta.id))
                .messages
                .isEmpty;
            if (dicho) {
              // Vacía: se mueve, y con ella su nombre en el dock. Es corregir
              // el rumbo antes de empezar, no empezar otra cosa.
              await ref
                  .read(conversationsProvider.notifier)
                  .moveTo(abierta.id, value);
            } else {
              // Con algo hablado, la nueva carpeta merece su propia
              // conversación: la de al lado tiene la memoria de la suya.
              await ref.read(conversationsProvider.notifier).open(value);
            }
          },
          itemBuilder: (context) => [
            for (final option in workspace.folders)
              PopupMenuItem<String>(
                value: option.path,
                child: Row(
                  children: [
                    Text(
                      option.name,
                      style: NexusTypography.data.copyWith(color: colors.ink),
                    ),
                    if (option.path == paired?.path) ...[
                      const SizedBox(width: NexusSpacing.s3),
                      Icon(Icons.check, size: 13, color: colors.cyan),
                    ],
                  ],
                ),
              ),
            PopupMenuItem<String>(
              value: '__pair__',
              child: Row(
                children: [
                  Icon(
                    Icons.create_new_folder_outlined,
                    size: 14,
                    color: colors.faint,
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Text(
                    strings.addFolderShort,
                    style: NexusTypography.data.copyWith(color: colors.mute),
                  ),
                ],
              ),
            ),
          ],
          child: _Chip(
            icon: paired == null
                ? Icons.folder_off_outlined
                : Icons.folder_outlined,
            label: paired?.name ?? strings.chooseFolder,
            warn: paired == null,
          ),
        ),
        // Con varios repos dentro, el chip elige. Es el caso de una carpeta
        // raíz de trabajo: Claude tiene que arrancar **dentro** del repo o
        // cualquier cosa de git ocurre en el sitio equivocado.
        if (repos.length > 1 && paired != null)
          PopupMenuButton<String?>(
            color: colors.deep,
            tooltip: '',
            onSelected: (value) => ref
                .read(workspaceControllerProvider.notifier)
                .setActiveRepo(paired.path, value),
            itemBuilder: (context) => [
              PopupMenuItem<String?>(
                child: Row(
                  children: [
                    Text(
                      // Trabajar sobre la raíz sigue siendo válido: hay
                      // encargos que cruzan repos y ahí bajar a uno sería
                      // esconderle la mitad.
                      paired.name,
                      style: NexusTypography.data.copyWith(color: colors.mute),
                    ),
                    if (paired.activeRepo == null) ...[
                      const SizedBox(width: NexusSpacing.s3),
                      Icon(Icons.check, size: 13, color: colors.cyan),
                    ],
                  ],
                ),
              ),
              for (final repo in repos)
                PopupMenuItem<String?>(
                  value: repo,
                  child: Row(
                    children: [
                      Text(
                        repo.split('/').last,
                        style: NexusTypography.data.copyWith(color: colors.ink),
                      ),
                      if (repo == paired.activeRepo) ...[
                        const SizedBox(width: NexusSpacing.s3),
                        Icon(Icons.check, size: 13, color: colors.cyan),
                      ],
                    ],
                  ),
                ),
            ],
            child: _Chip(
              icon: Icons.hub_outlined,
              label: git?.repository ?? paired.name,
            ),
          )
        else if (git != null) ...[
          // El repositorio aparte de la carpeta porque no siempre coinciden: se
          // puede trabajar sobre un subdirectorio de un repo, y entonces la
          // carpeta dice una cosa y el repo otra.
          _Chip(icon: Icons.hub_outlined, label: git.repository),
        ],
        if (git?.branch case final branch?)
          _Chip(icon: Icons.alt_route, label: branch),
        if (git == null && paired != null)
          // Sin repositorio no hay nada que deshacer, y eso hay que decirlo
          // donde se ve el permiso: es la red de seguridad que falta.
          _Chip(
            icon: Icons.warning_amber,
            label: strings.noGitRepo,
            warn: true,
          ),
        // La cuenta solo se enseña si hay más de una en el Mac: con una sola,
        // decir cuál se usa es contestar una pregunta que nadie tiene.
        if (ref.watch(claudeProfilesProvider).value case final cuentas?)
          if (cuentas.length > 1)
            if (paired?.claudeProfile?.split('/').last case final profile?)
              if (profile.startsWith('.claude-'))
                _Chip(icon: Icons.badge_outlined, label: profile.substring(8)),
        // La modalidad de voz no se repite aquí: se decide por carpeta en
        // Ajustes, y tenerla también en la barra creaba dos sitios que decían
        // lo mismo con distinta forma —uno como estado, el otro como
        // interruptor— y se contradecían a la vista.
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.warn = false});

  final IconData icon;
  final String label;

  /// Algo que falta o que conviene mirar: sin carpeta, sin git.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: NexusSpacing.s3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(
            color: warn ? colors.warn.withValues(alpha: 0.5) : colors.rule,
          ),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: warn ? colors.warn : colors.faint),
            const SizedBox(width: 6),
            Text(
              label,
              style: NexusTypography.mono.copyWith(
                color: warn ? colors.warn : colors.mute,
              ),
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
    required this.folder,
    required this.workspace,
    required this.meter,
    required this.voiceActive,
    required this.onToggleVoice,
    required this.onInsert,
  });

  /// La carpeta de esta conversación: de ella salen la cuenta, el modelo y el
  /// esfuerzo, porque los tres se deciden por carpeta.
  final PairedFolder? folder;
  final Workspace workspace;
  final SessionMeter meter;
  final bool voiceActive;
  final VoidCallback? onToggleVoice;
  final ValueChanged<String> onInsert;

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
        _MoreMenu(onInsert: onInsert),
        const SizedBox(width: NexusSpacing.s2),
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
        _ModelMenu(folder: folder, meter: meter),
        const SizedBox(width: NexusSpacing.s3),
        _EffortMenu(folder: folder),
        const SizedBox(width: NexusSpacing.s3),
        _UsageMenu(meter: meter, claudeProfile: folder?.claudeProfile),
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

/// El «+»: lo que se añade a lo que estás pidiendo.
///
/// Adjuntar es **poner la ruta en la caja**, no subir un archivo a ningún
/// sitio: Claude trabaja en tu disco y lee lo que le señales, así que copiar el
/// contenido sería duplicarlo y perder el vínculo con el original.
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.onInsert});

  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return PopupMenuButton<String>(
      color: colors.deep,
      tooltip: '',
      onSelected: (value) async {
        switch (value) {
          case 'file':
            final file = await openFile();
            if (file != null) onInsert(file.path);
          case 'folder':
            await ref.read(workspaceControllerProvider.notifier).pairFolder();
          case 'settings':
            if (context.mounted) await SettingsPage.open(context);
        }
      },
      itemBuilder: (context) => [
        _item('file', Icons.attach_file, strings.attachFile, colors),
        _item(
          'folder',
          Icons.create_new_folder_outlined,
          strings.addFolderShort,
          colors,
        ),
        _item('settings', Icons.tune, strings.openSettings, colors),
      ],
      child: Icon(Icons.add, size: 16, color: colors.faint),
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label,
    NexusColors colors,
  ) => PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 14, color: colors.faint),
        const SizedBox(width: NexusSpacing.s3),
        Text(label, style: NexusTypography.data.copyWith(color: colors.ink)),
      ],
    ),
  );
}

/// Qué modelo pide Nexus. «El del CLI» es lo de fábrica y no un hueco: Claude
/// se usa también desde la terminal, y pisar su configuración desde aquí
/// sorprendería allí.
class _ModelMenu extends ConsumerWidget {
  const _ModelMenu({required this.folder, required this.meter});

  final PairedFolder? folder;
  final SessionMeter meter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final model = ClaudeModel.fromStored(folder?.claudeModel);
    // Lo que se usaría sin elegir nada: primero lo que reportó el CLI en este
    // turno, y si no ha corrido ninguno, lo que tenga configurado ese perfil.
    final actual =
        meter.displayModel ??
        ref.watch(claudeDefaultsProvider(folder?.claudeProfile)).value?.model ??
        // Un perfil puede no fijar modelo —`private` no lo hace—: entonces vale
        // el último con el que se le vio trabajar.
        ref.watch(seenModelsProvider)[folder?.claudeProfile ?? 'por-defecto'];
    // El que está en uso: el elegido para esta carpeta, o el del CLI.
    final vigente = model ?? ClaudeModel.fromCliName(actual);

    return PopupMenuButton<ClaudeModel?>(
      color: colors.deep,
      tooltip: '',
      // Sin carpeta no hay dónde guardarlo: el menú se abre igual, pero elegir
      // no haría nada, así que no se ofrece.
      onSelected: folder == null
          ? null
          : (option) => ref
                .read(workspaceControllerProvider.notifier)
                .setClaudeModel(folder!.path, option?.alias),
      // Sin opción «el del CLI»: lo que el CLI ya usa **es** uno de estos, y
      // sale marcado. Una entrada aparte para lo mismo obliga a saber de
      // antemano a qué modelo equivale.
      itemBuilder: (context) => [
        for (final option in ClaudeModel.values)
          PopupMenuItem<ClaudeModel?>(
            value: option,
            child: Row(
              children: [
                Text(
                  option.label,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                if (option == vigente) ...[
                  const SizedBox(width: NexusSpacing.s3),
                  Icon(Icons.check, size: 13, color: colors.cyan),
                ],
              ],
            ),
          ),
      ],
      child: Text(
        vigente?.label ??
            (actual == null ? strings.modelTitle : _clean(actual)),
        style: NexusTypography.label.copyWith(
          color: model == null ? colors.faint : colors.mute,
        ),
      ),
    );
  }

  /// `claude-opus-5[1m]` se enseña sin el corchete: dice el tamaño de ventana,
  /// no el modelo, y en un botón de dos centímetros estorba.
  static String _clean(String model) {
    final bracket = model.indexOf('[');
    return bracket == -1 ? model : model.substring(0, bracket);
  }
}

/// Cuánto razona antes de contestar, de más rápido a más listo.
class _EffortMenu extends ConsumerWidget {
  const _EffortMenu({required this.folder});

  final PairedFolder? folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final effort = ClaudeEffort.fromStored(folder?.claudeEffort);
    final actual = ref
        .watch(claudeDefaultsProvider(folder?.claudeProfile))
        .value
        ?.effort;
    // El vigente: el elegido aquí, o el que ese perfil tenga fijado.
    final vigente = effort ?? ClaudeEffort.fromStored(actual);

    return PopupMenuButton<ClaudeEffort?>(
      color: colors.deep,
      tooltip: '',
      onSelected: folder == null
          ? null
          : (option) => ref
                .read(workspaceControllerProvider.notifier)
                .setClaudeEffort(folder!.path, option?.flag),
      itemBuilder: (context) => [
        for (final option in ClaudeEffort.values)
          PopupMenuItem<ClaudeEffort?>(
            value: option,
            child: Row(
              children: [
                Text(
                  option.flag,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                const SizedBox(width: NexusSpacing.s3),
                // Los extremos se nombran, porque «xhigh» no dice por sí solo
                // hacia qué lado tira.
                if (option == ClaudeEffort.low)
                  Text(
                    strings.effortFaster,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                if (option == ClaudeEffort.max)
                  Text(
                    strings.effortSmarter,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                if (option == vigente) ...[
                  const SizedBox(width: NexusSpacing.s3),
                  Icon(Icons.check, size: 13, color: colors.cyan),
                ],
              ],
            ),
          ),
      ],
      child: Text(
        vigente?.flag ?? strings.effortTitle,
        style: NexusTypography.label.copyWith(
          color: effort == null ? colors.faint : colors.mute,
        ),
      ),
    );
  }
}

/// El círculo de la derecha: contexto de esta conversación y cupo de la
/// suscripción.
///
/// Son dos cosas distintas y por eso están juntas: puedes tener la ventana medio
/// vacía y el cupo de la semana en las últimas. El contexto lo reporta el CLI en
/// cada turno; el cupo sale del mismo endpoint que usa la app de la barra de
/// menús.
class _UsageMenu extends ConsumerWidget {
  const _UsageMenu({required this.meter, required this.claudeProfile});

  final SessionMeter meter;
  final String? claudeProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final context_ = meter.contextPercent ?? 0;

    return PopupMenuButton<void>(
      color: colors.deep,
      tooltip: '',
      onOpened: () => ref.invalidate(claudeUsageProvider(claudeProfile)),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: SizedBox(
            width: 300,
            child: Consumer(
              builder: (context, ref, _) {
                final usage = ref
                    .watch(claudeUsageProvider(claudeProfile))
                    .value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Gauge(
                      label: strings.contextWindow,
                      percent: context_,
                      warnAt: 85,
                    ),
                    const SizedBox(height: NexusSpacing.s4),
                    Text(
                      usage == null ||
                              (ref.watch(claudeProfilesProvider).value ??
                                          const [])
                                      .length <
                                  2
                          ? strings.usageLimits
                          : '${strings.usageLimits} · ${usage.account}',
                      style: NexusTypography.label.copyWith(
                        color: colors.faint,
                      ),
                    ),
                    const SizedBox(height: NexusSpacing.s3),
                    if (usage == null)
                      // Sin dato no se dibuja una barra a cero: se leería como
                      // «no has gastado nada», que es lo contrario de «no se
                      // sabe».
                      Text(
                        strings.usageUnavailable,
                        style: NexusTypography.mono.copyWith(
                          color: colors.faint,
                        ),
                      )
                    else ...[
                      _Gauge(
                        label: strings.usageFiveHour,
                        percent: usage.fiveHourPercent,
                        note: _resets(strings, usage.fiveHourResetsAt),
                      ),
                      const SizedBox(height: NexusSpacing.s3),
                      _Gauge(
                        label: strings.usageWeekly,
                        percent: usage.weeklyPercent,
                        note: _resets(strings, usage.weeklyResetsAt),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
      child: SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(
          value: context_ / 100,
          strokeWidth: 2,
          backgroundColor: colors.rule,
          color: context_ >= 85 ? colors.warn : colors.cyan,
        ),
      ),
    );
  }

  static String? _resets(NexusStrings strings, DateTime? when) {
    if (when == null) return null;
    final falta = when.difference(DateTime.now());
    if (falta.isNegative) return null;
    final horas = falta.inHours;
    final minutos = falta.inMinutes % 60;
    return strings.resetsIn(
      horas > 0 ? 'en ${horas}h ${minutos}m' : 'en ${minutos}m',
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.label,
    required this.percent,
    this.note,
    this.warnAt = 90,
  });

  final String label;
  final int percent;
  final String? note;
  final int warnAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Encima de la barra solo el nombre y el número: son los dos datos que
        // se leen de un vistazo y caben siempre. Cuándo se renueva va **debajo**
        // — es un dato secundario y, apretado en la misma línea, desbordaba el
        // panel en cuanto el plazo pasaba de las horas a los días («129 h 27 m»).
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.mono.copyWith(color: colors.mute),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            Text(
              '$percent %',
              style: NexusTypography.data.copyWith(color: colors.faint),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 3,
            backgroundColor: colors.rule,
            color: percent >= warnAt ? colors.warn : colors.cyan,
          ),
        ),
        if (note case final texto?) ...[
          const SizedBox(height: 3),
          Text(
            texto,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ],
      ],
    );
  }
}

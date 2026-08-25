import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/permission_switch.dart';

/// Permisos: las carpetas emparejadas, su modalidad y qué no puede ejecutar.
///
/// Es la sección más grande, y la que más piezas propias tiene —la fila de
/// carpeta, el selector de cuenta, los comandos bloqueados—. Ninguna se usa fuera
/// de aquí, así que se quedan privadas en este archivo.

class PermissionsSection extends ConsumerWidget {
  const PermissionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final workspace = ref.watch(workspaceControllerProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);

    return ListView(
      children: [
        Text(
          context.strings.filePermissionsTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Align(
          alignment: Alignment.centerLeft,
          child: PermissionSwitch(
            permission: workspace.permission,
            onChanged: controller.setPermission,
          ),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          context.strings.filePermissionsExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s7),

        Text(
          context.strings.foldersWithPermission,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        if (workspace.isEmpty)
          Text(
            context.strings.noFoldersYet,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else
          for (final folder in workspace.folders)
            _FolderRow(
              folder: folder,
              // «Activa» dejó de existir al haber varias conversaciones: lo
              // que importa aquí es si esa carpeta tiene una abierta.
              isActive: ref.watch(conversationsProvider).hasFolder(folder.path),
              onActivate: () =>
                  ref.read(conversationsProvider.notifier).open(folder.path),
              onModality: (value) => controller.setModality(folder.path, value),
              onRemove: () => controller.removeFolder(folder.path),
            ),
        const SizedBox(height: NexusSpacing.s4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: controller.pairFolder,
            child: Text(context.strings.addFolder),
          ),
        ),
        const SizedBox(height: NexusSpacing.s3),
        // Lo que la pregunta sobre el workspace destapó, escrito donde se
        // decide: emparejar solo el repo carga sus reglas y luego no puede
        // leerlas si viven en una carpeta hermana.
        Text(
          // Decía que las demás carpetas viajan como acceso adicional, y eso
          // dejó de ser verdad en 3.4: la carpeta es la frontera del contexto y
          // `--add-dir` se quitó. Un ajuste que explica algo que el código ya no
          // hace es peor que no explicar nada.
          context.strings.foldersExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        // De la carpeta activa: lo que tarda en un repo no tarda en otro, así
        // que una lista global bloquearía en un proyecto lo que en otro es
        // instantáneo.
        if (workspace.folders
                .where((folder) => folder.path == workspace.activePath)
                .firstOrNull
            case final activa?) ...[
          const SizedBox(height: NexusSpacing.s6),
          _BlockedCommands(folder: activa),
        ],
      ],
    );
  }
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({
    required this.folder,
    required this.isActive,
    required this.onActivate,
    required this.onModality,
    required this.onRemove,
  });

  final PairedFolder folder;
  final bool isActive;
  final VoidCallback onActivate;
  final ValueChanged<FolderModality> onModality;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final home = ref.watch(homeDirectoryProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s4,
          vertical: NexusSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: colors.rise,
          border: Border.all(
            color: isActive
                ? colors.accent.withValues(alpha: 0.5)
                : colors.rule2,
          ),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Row(
          children: [
            // Radio y no casilla: solo una carpeta puede ser el directorio de
            // trabajo, y el resto acompañan.
            IconButton(
              onPressed: isActive ? null : onActivate,
              tooltip: isActive
                  ? context.strings.isActiveFolder
                  : context.strings.workHere,
              icon: Icon(
                isActive
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: isActive ? colors.accent : colors.faint,
              ),
            ),
            Expanded(
              child: Text(
                folder.displayPath(home),
                style: NexusTypography.data.copyWith(
                  color: isActive ? colors.ink : colors.mute,
                ),
              ),
            ),
            _AccountPicker(folder: folder),
            _PlanToggle(folder: folder),
            _ModalityToggle(modality: folder.modality, onChanged: onModality),
            IconButton(
              onPressed: onRemove,
              tooltip: context.strings.remove,
              icon: Icon(Icons.remove, size: 16, color: colors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Si esta carpeta exige un plan firmado antes de escribir.
///
/// Va en la misma fila que la cuenta y la modalidad porque es lo mismo que ellas: un
/// permiso de **esta** carpeta. Y se enciende aquí y se firma en el compositor a
/// propósito — encender es una decisión que se toma una vez, firmar es algo que se hace
/// cada vez que se va a trabajar, y mezclarlos mandaría a Ajustes a cada rato.
///
/// Apagarlo no borra el plan escrito: si mañana se enciende, lo que había sigue ahí con
/// su fecha. Borrarlo haría que apagar y encender pareciera firmar.
class _PlanToggle extends ConsumerWidget {
  const _PlanToggle({required this.folder});

  final PairedFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final donde = dondeMirar(
      carpeta: folder.path,
      perfil: folder.claudeProfile,
    );
    final exige = ref.watch(planFirmadoProvider(donde)).value?.exige ?? false;

    return IconButton(
      onPressed: () =>
          ref.read(planFirmadoProvider(donde).notifier).exigir(!exige),
      tooltip: exige ? strings.planRequireOn : strings.planRequireOff,
      icon: Icon(
        Icons.gavel,
        size: 15,
        color: exige ? colors.accent : colors.faint,
      ),
    );
  }
}

/// Lo que Claude no puede ejecutar en la carpeta activa.
///
/// Va en Permisos y no en una sección propia porque es un permiso: la
/// diferencia con el interruptor es que aquel dice si puede escribir y este
/// dice qué **no** puede correr, y los dos se leen juntos.
class _BlockedCommands extends ConsumerStatefulWidget {
  const _BlockedCommands({required this.folder});

  final PairedFolder folder;

  @override
  ConsumerState<_BlockedCommands> createState() => _BlockedCommandsState();
}

class _BlockedCommandsState extends ConsumerState<_BlockedCommands> {
  late final _controller = TextEditingController(
    text: widget.folder.blockedCommands.join('\n'),
  );

  @override
  void didUpdateWidget(covariant _BlockedCommands oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al cambiar de carpeta activa hay que traer su lista: sin esto se quedaría
    // la de la anterior y se guardaría encima de la nueva.
    if (widget.folder.path == oldWidget.folder.path) return;
    _controller.text = widget.folder.blockedCommands.join('\n');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.blockedTitle(widget.folder.name),
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.blockedExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 6,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(
            hintText: strings.blockedHint,
            hintStyle: NexusTypography.mono.copyWith(color: colors.rule2),
          ),
          onChanged: (value) => ref
              .read(workspaceControllerProvider.notifier)
              .setBlockedCommands(
                widget.folder.path,
                value
                    .split('\n')
                    .map((line) => line.trim())
                    .where((line) => line.isNotEmpty)
                    .toList(),
              ),
        ),
      ],
    );
  }
}

/// Con qué cuenta de Claude trabaja esta carpeta.
///
/// Va aquí, junto a la carpeta, por lo mismo que la modalidad de voz: se decide
/// **por carpeta**. Los repos del trabajo con la cuenta del trabajo y los
/// personales con la personal; un interruptor global obligaría a acordarse de
/// cambiarlo al saltar de proyecto, y equivocarse ahí gasta el cupo de la
/// cuenta que no era.
///
/// Solo aparece si hay más de una cuenta en la máquina: con una sola, elegir no
/// es una decisión, es un adorno.
class _AccountPicker extends ConsumerWidget {
  const _AccountPicker({required this.folder});

  final PairedFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final profiles = ref.watch(claudeProfilesProvider).value ?? const [];
    if (profiles.length < 2) return const SizedBox.shrink();

    final current = profiles
        .where((profile) => profile.path == folder.claudeProfile)
        .firstOrNull;

    return Tooltip(
      message: strings.claudeAccount,
      child: PopupMenuButton<String?>(
        color: colors.deep,
        tooltip: '',
        onSelected: (value) => ref
            .read(workspaceControllerProvider.notifier)
            .setClaudeProfile(folder.path, value),
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            child: Text(
              strings.claudeAccountDefault,
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
          ),
          for (final profile in profiles)
            PopupMenuItem<String?>(
              value: profile.path,
              child: Text(
                // Un perfil sin sesión se puede elegir, pero se dice: el
                // encargo fallaría con un error del CLI que no explica nada.
                profile.signedIn
                    ? profile.name
                    : strings.claudeAccountSignedOut(profile.name),
                style: NexusTypography.mono.copyWith(
                  color: profile.signedIn ? colors.ink : colors.warn,
                ),
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3),
          child: Text(
            current?.name ?? strings.claudeAccountDefault,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ),
      ),
    );
  }
}

/// El segundo eje de i5: qué puede salir de esta carpeta hacia el servicio de
/// voz. Vive junto a la carpeta y no en un ajuste global porque **se decide
/// por carpeta**: hay repos a los que se les puede hablar y otros a los que no.
class _ModalityToggle extends StatelessWidget {
  const _ModalityToggle({required this.modality, required this.onChanged});

  final FolderModality modality;
  final ValueChanged<FolderModality> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final voice = modality.allowsVoice;

    return Tooltip(
      message: voice
          ? context.strings.voiceAllowedExplainer
          : context.strings.textOnlyExplainer,
      child: TextButton(
        onPressed: () =>
            onChanged(voice ? FolderModality.textOnly : FolderModality.voice),
        child: Text(
          voice ? 'VOZ' : context.strings.textOnly,
          style: NexusTypography.label.copyWith(
            color: voice ? colors.accent : colors.faint,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

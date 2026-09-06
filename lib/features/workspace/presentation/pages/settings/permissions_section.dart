import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/domain/entities/config_del_repo.dart';
import 'package:nexus/features/workspace/domain/usecases/allowed_commands.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
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
    // Dos vistas del mismo estado, y hacen falta las dos: `workspace` es lo que
    // está en vigor —ya apretado por el repositorio— y es lo que hay que
    // **enseñar**; `mio` es lo que elegiste tú, y es sobre lo que hay que
    // **editar**. Editar sobre lo apretado guardaría la regla del repo como si
    // fuera tuya, y al día siguiente ya no sabrías cuál era cuál.
    final mio = controller.guardado;
    final manda = workspace.configActiva;

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
            // 🔴 **Ya no lo bloquea el repo que esté delante.** Esto es el tope
            // de la app y un `soloLectura` de un repositorio se respeta donde
            // toca —en el permiso de **su** carpeta, ver [ElPermisoQueVale]—.
            // Bloquearlo aquí ataba el cerrojo de toda la app a qué
            // conversación tenías abierta.
          ),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          context.strings.filePermissionsExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        if (manda != null &&
            (manda.declaraAlgo || manda.avisos.isNotEmpty)) ...[
          const SizedBox(height: NexusSpacing.s7),
          _LoQueDeclaraElRepo(config: manda),
        ],
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
              // Si el repo pide solo texto, el botón no puede prometer voz:
              // pulsarlo guardaría tu preferencia y no cambiaría nada.
              bloqueada: workspace.delRepo[folder.path]?.soloTexto ?? false,
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
        if (mio.folders
                .where((folder) => folder.path == workspace.activePath)
                .firstOrNull
            case final activa?) ...[
          const SizedBox(height: NexusSpacing.s6),
          _BlockedCommands(
            folder: activa,
            delRepo: manda?.comandosVetados ?? const [],
          ),
          const SizedBox(height: NexusSpacing.s6),
          _AllowedCommands(folder: activa),
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
    required this.bloqueada,
  });

  final PairedFolder folder;
  final bool isActive;
  final VoidCallback onActivate;
  final ValueChanged<FolderModality> onModality;
  final VoidCallback onRemove;
  final bool bloqueada;

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
            _ModalityToggle(
              modality: folder.modality,
              onChanged: onModality,
              bloqueada: bloqueada,
            ),
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

/// Lo que Claude no puede ejecutar en la carpeta activa.
///
/// Va en Permisos y no en una sección propia porque es un permiso: la
/// diferencia con el interruptor es que aquel dice si puede escribir y este
/// dice qué **no** puede correr, y los dos se leen juntos.
class _BlockedCommands extends ConsumerStatefulWidget {
  const _BlockedCommands({required this.folder, required this.delRepo});

  /// **La carpeta como la guardaste tú**, no la que quedó tras apretar el
  /// repositorio: lo que se escriba aquí se guarda, y guardar los comandos del
  /// repo como tuyos los dejaría puestos aunque el repo los quitara.
  final PairedFolder folder;

  /// Los que pone el repositorio. Se enseñan debajo y no se pueden editar aquí:
  /// se editan en su `.nexus/config.json`, que es donde se revisan.
  final List<String> delRepo;

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
        if (widget.delRepo.isNotEmpty) ...[
          const SizedBox(height: NexusSpacing.s2),
          Text(
            '${ConfigDelRepo.archivo} · ${widget.delRepo.join(' · ')}',
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ],
      ],
    );
  }
}

/// Lo que Claude **sí** puede ejecutar en la carpeta activa.
///
/// Va justo debajo de los bloqueados porque se leen juntos, y son las dos
/// mitades de la misma pregunta. La asimetría con ellos es deliberada y se
/// explica en [AllowedCommands]: bloquear de más deja un comando sin correr;
/// permitir de más deja correr algo que nadie autorizó.
///
/// **Sin la línea del repositorio** que sí tienen los bloqueados: un
/// `.nexus/config.json` no puede ampliar permisos, así que aquí no hay nada del
/// repo que enseñar.
class _AllowedCommands extends ConsumerStatefulWidget {
  const _AllowedCommands({required this.folder});

  final PairedFolder folder;

  @override
  ConsumerState<_AllowedCommands> createState() => _AllowedCommandsState();
}

class _AllowedCommandsState extends ConsumerState<_AllowedCommands> {
  late final _controller = TextEditingController(
    text: widget.folder.allowedCommands.join('\n'),
  );

  @override
  void didUpdateWidget(covariant _AllowedCommands oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al cambiar de carpeta activa hay que traer su lista, por lo mismo que en
    // los bloqueados: si no, se guardaría la de la anterior encima de la nueva.
    if (widget.folder.path == oldWidget.folder.path) return;
    _controller.text = widget.folder.allowedCommands.join('\n');
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
          strings.allowedTitle(widget.folder.name),
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.allowedExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 5,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(
            hintText: strings.allowedHint,
            hintStyle: NexusTypography.mono.copyWith(color: colors.rule2),
          ),
          onChanged: (value) => ref
              .read(workspaceControllerProvider.notifier)
              .setAllowedCommands(
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

/// Lo que el repositorio declara sobre sí mismo, en cristiano.
///
/// Tiene que verse, y por una razón que no es de transparencia sino de que la
/// pantalla no mienta: si el repo apaga la voz y aquí no lo dice, el botón de
/// la carpeta se queda en «SOLO TEXTO» sin motivo visible y parece un fallo.
///
/// Los avisos van con el mismo peso que las declaraciones, no escondidos: este
/// archivo se escribe a mano y se revisa en un PR, así que una llave mal puesta
/// necesita salir a la primera y no cuando alguien note que no se aplica.
class _LoQueDeclaraElRepo extends StatelessWidget {
  const _LoQueDeclaraElRepo({required this.config});

  final ConfigDelRepo config;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    final dice = <String>[
      if (config.soloTexto) strings.repoSoloTexto,
      if (config.soloLectura) strings.repoSoloLectura,
      if (config.comandosVetados.isNotEmpty)
        strings.repoComandosVetados(config.comandosVetados.length),
      if (config.carpetaDePruebas case final carpeta?)
        strings.repoCarpetaDePruebas(carpeta),
      if (config.modelo case final modelo?) strings.repoModelo(modelo),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.repoDeclaraTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.repoDeclaraExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        for (final linea in dice) ...[
          const SizedBox(height: NexusSpacing.s2),
          Text(
            '· $linea',
            style: NexusTypography.mono.copyWith(color: colors.ink),
          ),
        ],
        if (config.avisos.isNotEmpty) ...[
          const SizedBox(height: NexusSpacing.s3),
          Text(
            strings.repoAvisosTitle,
            style: NexusTypography.mono.copyWith(color: colors.warn),
          ),
          for (final aviso in config.avisos)
            Text(
              '· $aviso',
              style: NexusTypography.mono.copyWith(color: colors.warn),
            ),
        ],
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
  const _ModalityToggle({
    required this.modality,
    required this.onChanged,
    required this.bloqueada,
  });

  final FolderModality modality;
  final ValueChanged<FolderModality> onChanged;

  /// El repositorio pide solo texto. No es que esté deshabilitado: es que ya no
  /// hay nada que elegir aquí.
  final bool bloqueada;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final voice = modality.allowsVoice;

    return Tooltip(
      message: bloqueada
          ? context.strings.repoLoFija
          : voice
          ? context.strings.voiceAllowedExplainer
          : context.strings.textOnlyExplainer,
      child: TextButton(
        onPressed: bloqueada
            ? null
            : () => onChanged(
                voice ? FolderModality.textOnly : FolderModality.voice,
              ),
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

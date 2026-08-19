import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/design_system/theme_preference.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/onboarding/presentation/providers/tour_providers.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
import 'package:nexus/features/updates/presentation/widgets/update_modal.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/audio_output_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/microphone_tester.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/stats/presentation/widgets/stats_section.dart';
import 'package:nexus/features/superpowers/presentation/widgets/superpowers_section.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/permission_switch.dart';

/// Ajustes (D05 del mockup). De sus cuatro secciones solo vive «Permisos»:
/// las otras tres se listan apagadas, como en el propio mockup, porque
/// pertenecen a fases que aún no existen y fingirlas sería peor que dejarlas
/// a la vista.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  /// Se abre desde cuatro sitios —el botón de la barra, el de «empareja una
  /// carpeta», ⌘, y el menú de macOS—, y algunos pueden coincidir en la misma
  /// pulsación. Apilar dos ajustes deja al usuario cerrando la misma pantalla
  /// dos veces, así que el segundo no hace nada.
  static bool _isOpen = false;

  static Future<void> open(BuildContext context) async {
    if (_isOpen) return;
    _isOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// «Móvil» sigue apagada: pertenece a una fase que no existe, y fingirla
  /// sería peor que dejarla a la vista como lo que es. Donde estaba «Modelo»
  /// ahora hay estadísticas: el modelo se elige por carpeta desde la barra
  /// —le12—, así que esa sección se quedó sin contenido antes de tenerlo.
  /// Las secciones vivas, en el orden en que se leen. Son claves, no textos:
  /// el nombre visible sale del diccionario.
  ///
  /// Sale de `values` y **no de una lista escrita a mano**: esa lista ya se
  /// olvidó dos veces —el Historial primero y los Superpoderes después—, y el
  /// resultado es siempre el mismo, una sección que existe, se pinta bien y no
  /// tiene forma de abrirse. Con el orden de declaración como orden del menú,
  /// añadir una al enum basta para que aparezca.
  _Section _section = _Section.permissions;

  @override
  void initState() {
    super.initState();
    // Se relee al abrir Ajustes, no una vez por arranque: crear o borrar un
    // perfil pasa fuera de la app, y con la lista cacheada seguía ofreciendo
    // una cuenta que ya no existía.
    //
    // Después del primer fotograma y no aquí mismo: invalidar durante la
    // construcción del árbol marca el scope como sucio en mitad de su propio
    // build, y Flutter lo corta con «setState() called during build» — la
    // pantalla entera en rojo al abrir Ajustes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(claudeProfilesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsTopBar(onClose: () => Navigator.of(context).maybePop()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(64, 56, 64, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final section in _Section.values)
                              _SectionLink(
                                // Con nombre propio: «VOZ» aparece dos veces en
                                // esta pantalla —el enlace de la izquierda y la
                                // modalidad de una carpeta— y sin una llave no
                                // hay forma de decir cuál se pulsa.
                                key: ValueKey('seccion-${section.name}'),
                                label: section.title(context.strings),
                                active: _section == section,
                                onTap: () => setState(() => _section = section),
                              ),
                            _disabled(context.strings.sectionMobile, colors),
                          ],
                        ),
                      ),
                      const SizedBox(width: 96),
                      Expanded(
                        child: SizedBox(
                          width: 600,
                          child: switch (_section) {
                            _Section.voice => const _VoiceSection(),
                            _Section.permissions => const _PermissionsSection(),
                            _Section.history => const _HistorySection(),
                            _Section.stats => const StatsSection(),
                            _Section.superpowers => const SuperpowersSection(),
                            _Section.appearance => const _AppearanceSection(),
                            _Section.language => const _LanguageSection(),
                            _Section.help => const _HelpSection(),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _disabled(String label, NexusColors colors) => Padding(
    padding: const EdgeInsets.only(bottom: NexusSpacing.s4),
    child: Text(
      label.toUpperCase(),
      style: NexusTypography.label.copyWith(color: colors.rule2),
    ),
  );
}

class _SectionLink extends StatelessWidget {
  const _SectionLink({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // El relleno **dentro** del InkWell y no fuera: por fuera, la mitad de
    // abajo de cada enlace era hueco muerto que no respondía al clic. Lo
    // destapó la prueba que abre la pantalla, y el ratón lo sufría igual.
    //
    // Y ancho completo, no el del texto: la columna mide 200 y el área que
    // respondía era del ancho de cada palabra —«VOZ» daba tres letras de blanco
    // útil—, así que apuntar a la pestaña corta fallaba más que las largas. Ahora
    // todas valen lo mismo y no queda hueco muerto entre una y la siguiente.
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: NexusSpacing.s3,
            horizontal: NexusSpacing.s2,
          ),
          child: Text(
            label.toUpperCase(),
            style: NexusTypography.label.copyWith(
              color: active ? colors.cyan : colors.faint,
            ),
          ),
        ),
      ),
    );
  }
}

/// La voz con la que responde. Existe porque sin fijarla el servicio elegía
/// una distinta en cada sesión.
class _VoiceSection extends ConsumerWidget {
  const _VoiceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final selected = ref.watch(voicePreferenceProvider);
    final controller = ref.read(voicePreferenceProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.nexusVoice,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          context.strings.voiceExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        _Chooser<NexusVoice>(
          value: NexusVoice.all.firstWhere(
            (voice) => voice.name == selected.name,
            orElse: () => NexusVoice.all.first,
          ),
          options: NexusVoice.all,
          label: (voice) => voice.name,
          detail: (voice) => voice.character,
          onSelected: controller.select,
        ),
        const SizedBox(height: NexusSpacing.s6),
        const _AudioOutputPicker(),
        const SizedBox(height: NexusSpacing.s6),
        // El micrófono se prueba aquí y no solo en el primer arranque: es donde
        // se viene cuando algo no se oye, y hasta ahora esta sección solo
        // dejaba cambiar la voz con la que Nexus habla, no comprobar la que
        // escucha.
        const Expanded(child: MicrophoneTester()),
      ],
    );
  }
}

class _SettingsTopBar extends ConsumerWidget {
  const _SettingsTopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.s6,
        vertical: NexusSpacing.s5,
      ),
      child: Row(
        children: [
          // Un solo `Flexible` para el rótulo entero, y **sin `Spacer`**: con un
          // `Flexible` por texto, cada uno se llevaba su parte del reparto —flex 1
          // por defecto— y el hueco quedaba dividido en tres, así que «Cerrar» se
          // plantaba a media pantalla en vez de en el borde. Ahora el rótulo se
          // queda todo el sobrante y empuja el botón a la derecha, y en una
          // ventana estrecha sigue encogiendo con puntos suspensivos, que es para
          // lo que estaba puesto.
          // `Expanded` y no `Flexible`: el segundo deja al hijo quedarse pequeño,
          // así que el rótulo medía lo que su texto y «Cerrar» se pegaba a él —a
          // 825 px del borde, medido—. Con restricciones ajustadas el rótulo ocupa
          // todo el sobrante y empuja el botón al borde.
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    context.strings.brand,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.data.copyWith(
                      color: colors.mute,
                      letterSpacing: 4.2,
                    ),
                  ),
                ),
                const SizedBox(width: NexusSpacing.s5),
                Flexible(
                  child: Text(
                    context.strings.settings,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.label.copyWith(
                      color: colors.faint,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NexusSpacing.s5),
          // El interruptor de permisos ya no vive aquí.
          //
          // Es del espacio de trabajo entero, así que en la cabecera salía en
          // **todas** las secciones sin nada que lo explicase — al lado de la voz
          // o del idioma no dice de qué habla. Se cambia donde tiene contexto: en
          // la sección de Permisos, con su título y su explicación, y en la
          // pantalla principal, junto a la caja de escribir, que es donde importa
          // saber si Claude puede editar antes de pedirle algo.
          OutlinedButton(
            onPressed: onClose,
            child: Text(context.strings.closeEsc),
          ),
        ],
      ),
    );
  }
}

class _PermissionsSection extends ConsumerWidget {
  const _PermissionsSection();

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
            color: isActive ? colors.cyan.withValues(alpha: 0.5) : colors.rule2,
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
                color: isActive ? colors.cyan : colors.faint,
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
            color: voice ? colors.cyan : colors.faint,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

/// Las secciones de Ajustes, como claves. El nombre visible sale del
/// diccionario: aquí solo se decide cuáles hay y en qué orden.
enum _Section {
  voice,
  permissions,
  history,
  stats,
  superpowers,
  appearance,
  language,
  help;

  String title(NexusStrings strings) => switch (this) {
    _Section.voice => strings.sectionVoice,
    _Section.permissions => strings.sectionPermissions,
    _Section.history => strings.sectionHistory,
    _Section.stats => strings.sectionStats,
    _Section.superpowers => strings.sectionSuperpowers,
    _Section.appearance => strings.sectionAppearance,
    _Section.language => strings.sectionLanguage,
    _Section.help => strings.sectionHelp,
  };
}

/// Ayuda: por ahora, volver a ver el tour.
///
/// Sección propia y no una fila colgada de otra porque es donde va a vivir la
/// guía —el «qué necesita Nexus y qué hago con él» en frío—, y meterla ahora
/// dentro de Apariencia obligaría a mudarla después.
class _HelpSection extends ConsumerWidget {
  const _HelpSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    // Con su propio scroll: el cuerpo de una sección no lo trae, y esto es lo
    // más largo de todos los ajustes — la guía no cabe en una pantalla y no
    // debería tener que caber.
    return ListView(
      children: [
        Text(
          strings.helpTourTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.helpTourExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () {
              ref.read(tourControllerProvider.notifier).replay();
              Navigator.of(context).maybePop();
            },
            child: Text(strings.helpTourAction),
          ),
        ),
        const SizedBox(height: NexusSpacing.s7),
        Divider(color: colors.rule, height: 1),
        const SizedBox(height: NexusSpacing.s6),

        // La versión y, si hay una nueva, el enlace. Aquí y no en un diálogo:
        // un aviso modal por una actualización interrumpe justo a quien está
        // trabajando, y esto no es urgente — es información.
        const _VersionRow(),
        const SizedBox(height: NexusSpacing.s7),

        // La guía en frío. Cuatro bloques y en este orden: qué hace falta, qué
        // sale de tu Mac, qué hace cada pieza y qué hacer cuando algo falla.
        //
        // El segundo va tan arriba a propósito: es lo único de aquí que **no se
        // puede deducir mirando la app**, y decidirlo mal tiene consecuencias
        // fuera de ella.
        _GuideBlock(
          title: strings.guideNeedsTitle,
          body: strings.guideNeedsBody,
        ),
        _GuideBlock(
          title: strings.guidePrivacyTitle,
          body: strings.guidePrivacyBody,
        ),
        _GuideBlock(
          title: strings.guidePiecesTitle,
          body: strings.guidePiecesBody,
        ),
        _GuideBlock(
          title: strings.guideTroubleTitle,
          body: strings.guideTroubleBody,
        ),
      ],
    );
  }
}

/// La versión que corre y, si la hay, la que está publicada.
///
/// Ya descarga e instala: el motor es Sparkle y la modal es la de la app. Lo que
/// **no** hace es reiniciarse por su cuenta —eso mataría un `claude -p` a media
/// escritura—, así que el último paso siempre lo confirma quien está delante.
class _VersionRow extends ConsumerWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final aviso = ref.watch(updatesControllerProvider).notice;
    final actual =
        aviso?.current ?? ref.watch(currentVersionProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.versionLabel,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          actual ?? '—',
          style: NexusTypography.data.copyWith(color: colors.ink),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Align(
          alignment: Alignment.centerLeft,
          // Dos botones distintos y no uno que cambia de texto: «comprobar» es
          // algo que se pulsa sin saber si hay nada, y «actualizar» solo aparece
          // cuando ya se sabe que sí. Con un solo botón habría que decidir qué
          // dice mientras no se sabe, y ahí es donde se acaba mintiendo.
          child: aviso != null && aviso.isNewer
              ? FilledButton(
                  onPressed: () => UpdateModal.open(context),
                  child: Text(strings.updateAvailable(aviso.latest ?? '')),
                )
              : OutlinedButton(
                  onPressed: () {
                    // Primero la modal y después la pregunta: así se ve
                    // «buscando…» en vez de un botón que no hace nada durante
                    // los segundos que tarda.
                    UpdateModal.open(context);
                    ref.read(updatesControllerProvider.notifier).comprobarAhora();
                  },
                  child: Text(strings.updateCheckNow),
                ),
        ),
      ],
    );
  }
}

/// Un bloque de la guía: un título y su texto.
///
/// El cuerpo llega como un solo texto con saltos dobles y se parte aquí. Es a
/// propósito: un bloque por párrafo multiplicaría por cuatro los textos que hay
/// que traducir sin añadir nada, y lo que se traduce es prosa, no maquetación.
class _GuideBlock extends StatelessWidget {
  const _GuideBlock({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: NexusTypography.lead.copyWith(color: colors.ink),
          ),
          const SizedBox(height: NexusSpacing.s4),
          for (final parrafo in body.split('\n\n'))
            Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
              child: Text(
                parrafo,
                style: NexusTypography.body.copyWith(color: colors.mute),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dónde acaban las conversaciones.
///
/// Los tres destinos son del usuario, no del programa, y por eso el estado de
/// partida es «en ningún sitio»: sacar lo que hablas de esta máquina es una
/// decisión suya, no algo que pase por omisión.
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final settings = ref.watch(archiveControllerProvider);
    final controller = ref.read(archiveControllerProvider.notifier);

    String label(ArchiveDestination option) => switch (option) {
      ArchiveDestination.none => strings.archiveNone,
      ArchiveDestination.folder => strings.archiveFolder,
      ArchiveDestination.obsidian => strings.archiveObsidian,
      ArchiveDestination.notion => strings.archiveNotion,
    };
    String hint(ArchiveDestination option) => switch (option) {
      ArchiveDestination.none => strings.archiveNoneHint,
      ArchiveDestination.folder => strings.archiveFolderHint,
      ArchiveDestination.obsidian => strings.archiveObsidianHint,
      ArchiveDestination.notion => strings.archiveNotionHint,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.archiveTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.archiveExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        for (final option in ArchiveDestination.values)
          InkWell(
            onTap: () => controller.selectDestination(option),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    option == settings.destination
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 15,
                    color: option == settings.destination
                        ? colors.cyan
                        : colors.faint,
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label(option),
                          style: NexusTypography.data.copyWith(
                            color: option == settings.destination
                                ? colors.ink
                                : colors.mute,
                          ),
                        ),
                        Text(
                          hint(option),
                          style: NexusTypography.mono.copyWith(
                            color: colors.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (settings.destination == ArchiveDestination.notion) ...[
          const SizedBox(height: NexusSpacing.s5),
          _NotionFields(settings: settings, controller: controller),
        ],
        if (settings.destination.needsFolder) ...[
          const SizedBox(height: NexusSpacing.s5),
          Row(
            children: [
              OutlinedButton(
                onPressed: () async {
                  final chosen = await getDirectoryPath();
                  if (chosen != null) await controller.selectFolder(chosen);
                },
                child: Text(strings.archiveChooseFolder),
              ),
              const SizedBox(width: NexusSpacing.s4),
              Expanded(
                child: Text(
                  settings.folderPath ?? '',
                  style: NexusTypography.mono.copyWith(color: colors.mute),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.s3),
          Text(
            settings.isReady
                ? strings.archiveLayout(settings.folderPath!)
                : strings.archiveNoFolderYet,
            style: NexusTypography.mono.copyWith(
              color: settings.isReady ? colors.faint : colors.warn,
            ),
          ),
        ],
      ],
    );
  }
}

/// Por dónde sale la voz de Nexus, cuando hay más de un aparato conectado.
class _AudioOutputPicker extends ConsumerWidget {
  const _AudioOutputPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final devices = ref.watch(audioOutputDevicesProvider).value ?? const [];
    // Con un solo aparato no hay nada que elegir; el desplegable sobra.
    if (devices.length < 2) return const SizedBox.shrink();

    final selected = ref.watch(audioOutputControllerProvider);
    final options = <int?>[null, ...devices.map((device) => device.id)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.audioOutput,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        _Chooser<int?>(
          value: options.contains(selected) ? selected : null,
          options: options,
          label: (id) {
            if (id == null) return strings.audioOutputSystem;
            return devices.firstWhere((device) => device.id == id).name;
          },
          // El que usa el sistema se marca, para que elegir «el del sistema» no
          // sea elegir a ciegas.
          detail: (id) => id == null
              ? (devices
                        .where((device) => device.isDefault)
                        .firstOrNull
                        ?.name ??
                    '')
              : '',
          onSelected: ref.read(audioOutputControllerProvider.notifier).select,
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.audioOutputExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

/// El token y la página de Notion.
///
/// Se pide aquí y no en la configuración inicial porque no es un requisito para
/// usar Nexus: es una decisión de dónde quieres tus conversaciones. El token
/// viaja al llavero, como la llave de Gemini — no a las preferencias en claro.
class _NotionFields extends StatefulWidget {
  const _NotionFields({required this.settings, required this.controller});

  final ArchiveSettings settings;
  final ArchiveController controller;

  @override
  State<_NotionFields> createState() => _NotionFieldsState();
}

class _NotionFieldsState extends State<_NotionFields> {
  late final _page = TextEditingController(
    text: widget.settings.notionPage ?? '',
  );
  final _token = TextEditingController();

  @override
  void dispose() {
    _page.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final settings = widget.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.notionToken,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        TextField(
          controller: _token,
          obscureText: true,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(hintText: strings.notionTokenHint),
          onChanged: widget.controller.saveNotionToken,
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.notionTokenExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Text(
          strings.notionPage,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        TextField(
          controller: _page,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(hintText: strings.notionPageHint),
          onChanged: widget.controller.saveNotionPage,
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.notionPageExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),
        Text(
          settings.isReady ? strings.notionReady : strings.notionMissing,
          style: NexusTypography.mono.copyWith(
            color: settings.isReady ? colors.ok : colors.warn,
          ),
        ),
      ],
    );
  }
}

/// El idioma de la app — y de lo que te responden.
///
/// Existe porque la regla del proyecto pide español e inglés como mínimo, y
/// hasta ahora la interfaz estaba escrita a mano en español. Cambiarlo aquí
/// cambia también cómo contestan los modelos: una app en inglés con una voz que
/// responde en español sería lo peor de los dos mundos.
/// Claro u oscuro, elegido a mano.
///
/// Va aparte del idioma aunque compartan forma: son dos preferencias de la app
/// y meterlas en la misma pantalla obligaría a leerse una para cambiar la otra.
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final choice = ref.watch(themeControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.themeTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.themeExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        _Chooser<ThemeChoice>(
          value: choice,
          options: ThemeChoice.values,
          label: (option) => switch (option) {
            ThemeChoice.system => strings.themeSystem,
            ThemeChoice.light => strings.themeLight,
            ThemeChoice.dark => strings.themeDark,
          },
          onSelected: ref.read(themeControllerProvider.notifier).select,
        ),
      ],
    );
  }
}

class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final choice = ref.watch(languageControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.languageTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.languageExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        _Chooser<LanguageChoice>(
          value: choice,
          options: LanguageChoice.values,
          label: (option) => switch (option) {
            LanguageChoice.system => strings.languageSystem,
            LanguageChoice.spanish => strings.languageSpanish,
            LanguageChoice.english => strings.languageEnglish,
          },
          onSelected: ref.read(languageControllerProvider.notifier).select,
        ),
      ],
    );
  }
}

/// El desplegable de Ajustes.
///
/// Lo comparten la voz y el idioma para que no acaben pareciéndose solo un
/// rato: son la misma pregunta —elige uno de esta lista— y separarlos en dos
/// widgets fue exactamente lo que hizo que uno tuviera 30 opciones en una
/// columna interminable y el otro tres.
class _Chooser<T> extends StatelessWidget {
  const _Chooser({
    required this.value,
    required this.options,
    required this.label,
    required this.onSelected,
    this.detail,
  });

  final T value;
  final List<T> options;

  /// Lo que se lee en la fila. Se pide como función y no como texto ya hecho
  /// porque las opciones vienen del dominio —una voz, un idioma— y traducirlas
  /// es cosa de la pantalla.
  final String Function(T option) label;

  /// La coletilla en gris: el carácter de una voz, por ejemplo. Opcional
  /// porque el idioma no tiene nada que añadir.
  final String Function(T option)? detail;

  final void Function(T option) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s4),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          // El desplegado hereda el fondo claro de Material si no se le dice
          // lo contrario, y en esta app eso es un fogonazo blanco.
          dropdownColor: colors.deep,
          // Sin esto, el botón se queda pintado de cian después de elegir: es
          // el resaltado de foco de Material, que en un control tan ancho se
          // lee como «esto sigue seleccionado» en vez de «esto tiene el foco».
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(NexusRadius.sm),
          icon: Icon(Icons.expand_more, size: 16, color: colors.faint),
          style: NexusTypography.data.copyWith(color: colors.ink),
          onChanged: (option) {
            if (option != null) onSelected(option);
          },
          items: [
            for (final option in options)
              DropdownMenuItem<T>(
                value: option,
                child: Row(
                  children: [
                    Text(
                      label(option),
                      style: NexusTypography.data.copyWith(color: colors.ink),
                    ),
                    if (detail case final describe?) ...[
                      const SizedBox(width: NexusSpacing.s3),
                      Text(
                        describe(option),
                        style: NexusTypography.mono.copyWith(
                          color: colors.faint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

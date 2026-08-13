import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/audio_output_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/microphone_tester.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
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
  /// «Móvil» y «Modelo» siguen apagadas: pertenecen a fases que no existen, y
  /// fingirlas sería peor que dejarlas a la vista como lo que son.
  /// Las secciones vivas, en el orden en que se leen. Son claves, no textos:
  /// el nombre visible sale del diccionario.
  static const _sections = [
    _Section.voice,
    _Section.permissions,
    _Section.history,
    _Section.language,
  ];
  _Section _section = _Section.permissions;

  @override
  void initState() {
    super.initState();
    // Se relee al abrir Ajustes, no una vez por arranque: crear o borrar un
    // perfil pasa fuera de la app, y con la lista cacheada seguía ofreciendo
    // una cuenta que ya no existía.
    ref.invalidate(claudeProfilesProvider);
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
                            for (final section in _sections)
                              _SectionLink(
                                label: section.title(context.strings),
                                active: _section == section,
                                onTap: () => setState(() => _section = section),
                              ),
                            _disabled(context.strings.sectionMobile, colors),
                            _disabled(context.strings.sectionModel, colors),
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
                            _Section.language => const _LanguageSection(),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s4),
      child: InkWell(
        onTap: onTap,
        child: Text(
          label.toUpperCase(),
          style: NexusTypography.label.copyWith(
            color: active ? colors.cyan : colors.faint,
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
    final workspace = ref.watch(workspaceControllerProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.s6,
        vertical: NexusSpacing.s5,
      ),
      child: Row(
        children: [
          Text(
            context.strings.brand,
            style: NexusTypography.data.copyWith(
              color: colors.mute,
              letterSpacing: 4.2,
            ),
          ),
          const SizedBox(width: NexusSpacing.s5),
          Text(
            context.strings.settings,
            style: NexusTypography.label.copyWith(
              color: colors.faint,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          PermissionSwitch(
            permission: workspace.permission,
            onChanged: ref
                .read(workspaceControllerProvider.notifier)
                .setPermission,
          ),
          const SizedBox(width: NexusSpacing.s5),
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
  language;

  String title(NexusStrings strings) => switch (this) {
    _Section.voice => strings.sectionVoice,
    _Section.permissions => strings.sectionPermissions,
    _Section.history => strings.sectionHistory,
    _Section.language => strings.sectionLanguage,
  };
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

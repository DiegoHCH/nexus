import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
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
    _Section.language,
  ];
  _Section _section = _Section.permissions;

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
        Expanded(
          child: ListView.builder(
            itemCount: NexusVoice.all.length,
            itemBuilder: (context, index) {
              final voice = NexusVoice.all[index];
              final isSelected = voice.name == selected.name;
              return InkWell(
                onTap: () => controller.select(voice),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: NexusSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 15,
                        color: isSelected ? colors.cyan : colors.faint,
                      ),
                      const SizedBox(width: NexusSpacing.s3),
                      Text(
                        voice.name,
                        style: NexusTypography.data.copyWith(
                          color: isSelected ? colors.ink : colors.mute,
                        ),
                      ),
                      const SizedBox(width: NexusSpacing.s3),
                      Text(
                        voice.character,
                        style: NexusTypography.mono.copyWith(
                          color: colors.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
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
  language;

  String title(NexusStrings strings) => switch (this) {
    _Section.voice => strings.sectionVoice,
    _Section.permissions => strings.sectionPermissions,
    _Section.language => strings.sectionLanguage,
  };
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
        for (final option in LanguageChoice.values)
          InkWell(
            onTap: () =>
                ref.read(languageControllerProvider.notifier).select(option),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
              child: Row(
                children: [
                  Icon(
                    option == choice
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 15,
                    color: option == choice ? colors.cyan : colors.faint,
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Text(
                    switch (option) {
                      LanguageChoice.system => strings.languageSystem,
                      LanguageChoice.spanish => strings.languageSpanish,
                      LanguageChoice.english => strings.languageEnglish,
                    },
                    style: NexusTypography.data.copyWith(
                      color: option == choice ? colors.ink : colors.mute,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

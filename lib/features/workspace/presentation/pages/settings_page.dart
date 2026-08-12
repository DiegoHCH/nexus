import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';
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

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsPage(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// «Móvil» y «Modelo» siguen apagadas: pertenecen a fases que no existen, y
  /// fingirlas sería peor que dejarlas a la vista como lo que son.
  static const _sections = ['Voz', 'Permisos'];
  String _section = 'Permisos';

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
                            for (final name in _sections)
                              _SectionLink(
                                label: name,
                                active: _section == name,
                                onTap: () => setState(() => _section = name),
                              ),
                            _disabled('Móvil', colors),
                            _disabled('Modelo', colors),
                          ],
                        ),
                      ),
                      const SizedBox(width: 96),
                      Expanded(
                        child: SizedBox(
                          width: 600,
                          child: _section == 'Voz'
                              ? const _VoiceSection()
                              : const _PermissionsSection(),
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
          'VOZ DE NEXUS',
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          'Se fija al abrir la sesión, así que un cambio vale desde la próxima vez que '
          'le hables. El idioma no se elige: lo detecta de lo que dices.',
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
            'N E X U S',
            style: NexusTypography.data.copyWith(
              color: colors.mute,
              letterSpacing: 4.2,
            ),
          ),
          const SizedBox(width: NexusSpacing.s5),
          Text(
            'AJUSTES',
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
          OutlinedButton(onPressed: onClose, child: const Text('CERRAR  ESC')),
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
          'PERMISOS SOBRE TUS ARCHIVOS',
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
          'Este interruptor está siempre visible en la barra superior. En «solo leer», Nexus '
          'puede abrir archivos y correr comandos que no escriben; en «puede editar», también '
          'modifica archivos.',
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s7),

        Text(
          'CARPETAS CON PERMISO',
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        if (workspace.isEmpty)
          Text(
            'Todavía no hay ninguna. Sin carpeta emparejada no hay dónde trabajar: '
            'Claude correría sobre la raíz del disco.',
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else
          for (final folder in workspace.folders)
            _FolderRow(
              folder: folder,
              isActive: folder.path == workspace.activePath,
              onActivate: () => controller.setActive(folder.path),
              onModality: (value) => controller.setModality(folder.path, value),
              onRemove: () => controller.removeFolder(folder.path),
            ),
        const SizedBox(height: NexusSpacing.s4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: controller.pairFolder,
            child: const Text('AÑADIR CARPETA'),
          ),
        ),
        const SizedBox(height: NexusSpacing.s3),
        // Lo que la pregunta sobre el workspace destapó, escrito donde se
        // decide: emparejar solo el repo carga sus reglas y luego no puede
        // leerlas si viven en una carpeta hermana.
        Text(
          'La carpeta activa es donde trabaja Claude; las demás se le pasan como acceso '
          'adicional. Si las reglas de un repo viven fuera de él —un ai-context al lado, por '
          'ejemplo— empareja también esa carpeta, o Claude cargará instrucciones que no puede seguir.',
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
              tooltip: isActive ? 'Es la carpeta activa' : 'Trabajar aquí',
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
              tooltip: 'Quitar',
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
          ? 'Se puede hablar con esta carpeta: tu voz y lo que Claude lea salen hacia Google'
          : 'Solo texto: nada de esta carpeta sale hacia el servicio de voz',
      child: TextButton(
        onPressed: () =>
            onChanged(voice ? FolderModality.textOnly : FolderModality.voice),
        child: Text(
          voice ? 'VOZ' : 'SOLO TEXTO',
          style: NexusTypography.label.copyWith(
            color: voice ? colors.cyan : colors.faint,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/permission_switch.dart';

/// La barra superior del HUD: wordmark, carpeta activa y el interruptor de
/// permisos, que según el diseño está **siempre** visible.
///
/// Esa insistencia del mockup tiene motivo: un asistente por voz que puede
/// escribir archivos sin que se vea en pantalla da miedo con razón, así que el
/// permiso no se esconde en Ajustes.
class HudTopBar extends ConsumerWidget {
  const HudTopBar({super.key, required this.status});

  /// Lo que Nexus está haciendo ahora mismo, en una palabra.
  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final workspace = ref.watch(workspaceControllerProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);
    final active = workspace.active;

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
            status.toUpperCase(),
            style: NexusTypography.label.copyWith(
              color: colors.faint,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          if (active == null)
            OutlinedButton(
              onPressed: controller.pairFolder,
              child: const Text('EMPAREJAR CARPETA'),
            )
          else
            _ActiveFolder(
              folder: active,
              onTap: () => SettingsPage.open(context),
            ),
          const SizedBox(width: NexusSpacing.s5),
          PermissionSwitch(
            permission: workspace.permission,
            onChanged: (value) => controller.setPermission(value),
          ),
        ],
      ),
    );
  }
}

class _ActiveFolder extends ConsumerWidget {
  const _ActiveFolder({required this.folder, required this.onTap});

  final PairedFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final home = ref.watch(homeDirectoryProvider);
    // El modo de la carpeta se enseña junto a la ruta y no en Ajustes: es la
    // diferencia entre poder hablarle o no, y descubrirlo al pulsar el atajo
    // sería descubrirlo tarde.
    final voice = folder.modality.allowsVoice;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s2,
          vertical: 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              folder.displayPath(home),
              style: NexusTypography.data.copyWith(color: colors.mute),
            ),
            const SizedBox(width: NexusSpacing.s3),
            Text(
              voice ? 'VOZ' : 'SOLO TEXTO',
              style: NexusTypography.label.copyWith(
                color: voice ? colors.cyan : colors.faint,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

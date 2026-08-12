import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
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
  const HudTopBar({
    super.key,
    required this.status,
    this.live = false,
    this.meter = const SessionMeter(),
    this.folderPath,
  });

  /// Lo que Nexus está haciendo ahora mismo, en una palabra.
  final String status;

  /// Hay algo en marcha: el wordmark enciende su punto, como en el mockup.
  final bool live;

  /// Modelo, tokens y contexto. Si no ha arrancado ninguna conversación no se
  /// inventa nada: se dice que no la hay.
  final SessionMeter meter;

  /// La carpeta de **la conversación que se está mirando**.
  ///
  /// Se recibe en vez de leerse del workspace porque con varias conversaciones
  /// abiertas ya no existe «la carpeta activa»: cada una tiene la suya, y la
  /// cabecera tiene que decir la de esta o miente sobre dónde estás trabajando.
  final String? folderPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final workspace = ref.watch(workspaceControllerProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);
    final active = workspace.folders
        .where((folder) => folder.path == folderPath)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.s6,
        vertical: NexusSpacing.s5,
      ),
      child: Row(
        children: [
          if (live) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.cyan,
                boxShadow: [
                  BoxShadow(
                    color: colors.cyan.withValues(alpha: 0.8),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
          ],
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
              color: live ? colors.cyan : colors.faint,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          _Meter(meter: meter),
          const SizedBox(width: NexusSpacing.s5),
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

/// «claude-opus-5 · 12,4k tokens · 18 % contexto», y cada dato desaparece si
/// no se conoce en vez de mostrar un cero que parecería medido.
class _Meter extends StatelessWidget {
  const _Meter({required this.meter});

  final SessionMeter meter;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final model = meter.displayModel;
    if (model == null) {
      return Text(
        'sin conversación',
        style: NexusTypography.data.copyWith(color: colors.faint),
      );
    }

    final tokens = meter.tokensLabel;
    final context_ = meter.contextPercent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(model, style: NexusTypography.data.copyWith(color: colors.mute)),
        if (tokens != null) ...[
          _dot(colors),
          Text(
            tokens,
            style: NexusTypography.data.copyWith(color: colors.mute),
          ),
          Text(
            ' tokens',
            style: NexusTypography.data.copyWith(color: colors.faint),
          ),
        ],
        if (context_ != null) ...[
          _dot(colors),
          Text(
            '$context_ %',
            style: NexusTypography.data.copyWith(color: colors.mute),
          ),
          Text(
            ' contexto',
            style: NexusTypography.data.copyWith(color: colors.faint),
          ),
        ],
      ],
    );
  }

  Widget _dot(NexusColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3),
    child: Text('·', style: NexusTypography.data.copyWith(color: colors.rule2)),
  );
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

import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';

/// El interruptor «Solo leer / Puede editar» del mockup, siempre visible en la
/// barra superior.
///
/// El punto delante de la opción activa no es adorno: es lo que hace que el
/// estado se distinga de un vistazo y a distancia, sin leer. Cian cuando solo
/// lee, ámbar cuando puede escribir — el mismo código de color que el resto
/// del HUD usa para «esto es normal» y «esto merece atención».
class PermissionSwitch extends StatelessWidget {
  const PermissionSwitch({
    super.key,
    required this.permission,
    required this.onChanged,
  });

  final FilePermission permission;
  final ValueChanged<FilePermission> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.rule2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Option(
              label: 'SOLO LEER',
              selected: permission == FilePermission.readOnly,
              dotColor: colors.cyan,
              onTap: () => onChanged(FilePermission.readOnly),
            ),
            _Option(
              label: 'PUEDE EDITAR',
              selected: permission == FilePermission.canEdit,
              dotColor: colors.warn,
              onTap: () => onChanged(FilePermission.canEdit),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.dotColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color dotColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: selected ? colors.ink.withValues(alpha: 0.05) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? dotColor : colors.rule2,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.9),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: NexusTypography.label.copyWith(
                color: selected ? colors.ink : colors.faint,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

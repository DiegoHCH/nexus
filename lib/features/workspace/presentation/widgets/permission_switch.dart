import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
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
    this.bloqueado = false,
  });

  final FilePermission permission;
  final ValueChanged<FilePermission> onChanged;

  /// El repositorio sobre el que se trabaja declara solo lectura.
  ///
  /// Deja de responder en vez de responder y volver atrás: sin esto el
  /// interruptor aceptaría «puede editar», se guardaría tu preferencia y la
  /// pantalla se quedaría en «solo leer» sin decir por qué — que se lee como
  /// un fallo y no como un permiso denegado.
  final bool bloqueado;

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
              label: context.strings.readOnly,
              selected: permission == FilePermission.readOnly,
              dotColor: colors.accent,
              onTap: bloqueado
                  ? null
                  : () => onChanged(FilePermission.readOnly),
            ),
            _Option(
              label: context.strings.canEdit,
              selected: permission == FilePermission.canEdit,
              dotColor: colors.warn,
              onTap: bloqueado ? null : () => onChanged(FilePermission.canEdit),
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

  /// `null` cuando el repositorio fija el permiso: el gesto no existe.
  final VoidCallback? onTap;

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

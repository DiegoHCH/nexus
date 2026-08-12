import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';

/// El historial «Antes» del mockup: lo último que le pediste, arriba a la
/// derecha.
///
/// El propio diseño lo etiqueta como «accesible, no protagonista», y de ahí
/// todo lo demás: alineado a la derecha, en gris tenue y de dos líneas. No es
/// una lista de chat — si compitiera con la conversación en curso, dejaría de
/// ser un HUD para ser una app de mensajería.
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({
    super.key,
    required this.entries,
    required this.onOpenAll,
  });

  /// Cuántas caben sin dejar de ser un apunte al margen.
  static const _visible = 2;

  final List<String> entries;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final previous = entries.take(_visible).toList();
    if (previous.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ANTES',
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        for (final entry in previous)
          Padding(
            padding: const EdgeInsets.only(bottom: NexusSpacing.s2),
            child: Text(
              entry,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.data.copyWith(
                color: colors.faint,
                height: 1.55,
              ),
            ),
          ),
        const SizedBox(height: NexusSpacing.s3),
        OutlinedButton(
          onPressed: onOpenAll,
          child: const Text('HISTORIAL  ⌘H'),
        ),
      ],
    );
  }
}

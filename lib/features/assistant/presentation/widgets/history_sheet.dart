import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';

/// Lo que abre «HISTORIAL ⌘H»: todo lo pedido en esta sesión, y tocar una
/// entrada la vuelve a pedir.
///
/// Es de esta sesión y no de siempre, y conviene que se note: la memoria entre
/// conversaciones es 3.4 y todavía no existe. Prometer aquí un historial
/// completo sería prometer algo que se pierde al cerrar la app.
class HistorySheet extends StatelessWidget {
  const HistorySheet({super.key, required this.entries, required this.onPick});

  final List<String> entries;
  final ValueChanged<String> onPick;

  static Future<void> open(
    BuildContext context, {
    required List<String> entries,
    required ValueChanged<String> onPick,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => HistorySheet(entries: entries, onPick: onPick),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.rise,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.rule2),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'HISTORIAL',
                style: NexusTypography.label.copyWith(color: colors.cyan),
              ),
              const SizedBox(height: NexusSpacing.s2),
              Text(
                'De esta sesión. Al cerrar Nexus se pierde — la memoria entre '
                'conversaciones todavía no existe.',
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
              const SizedBox(height: NexusSpacing.s5),
              Flexible(
                child: entries.isEmpty
                    ? Text(
                        'Todavía no le has pedido nada.',
                        style: NexusTypography.mono.copyWith(
                          color: colors.faint,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            Divider(color: colors.rule, height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              onPick(entry);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: NexusSpacing.s3,
                              ),
                              child: Text(
                                entry,
                                style: NexusTypography.data.copyWith(
                                  color: colors.ink,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

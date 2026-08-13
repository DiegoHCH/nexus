import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';

/// Lo que abre `⌘H`: las conversaciones guardadas de esta carpeta.
///
/// Antes enseñaba las últimas peticiones sueltas —el texto de lo que pediste,
/// sin la respuesta— porque no había nada más que enseñar. Ahora hay
/// conversaciones enteras, y tocar una la vuelve a abrir: se lee entera y lo
/// que sigas diciendo se añade a ella.
///
/// Es de **esta carpeta**, como todo lo demás: la memoria, el contexto y el
/// archivo van por carpeta, y mezclar aquí las de otro proyecto sería la única
/// pantalla que rompe esa regla.
class ConversationHistorySheet extends ConsumerWidget {
  const ConversationHistorySheet({
    super.key,
    required this.folderPath,
    required this.onPick,
    required this.onForget,
  });

  final String folderPath;
  final ValueChanged<ConversationRecord> onPick;
  final VoidCallback onForget;

  static Future<void> open(
    BuildContext context, {
    required String folderPath,
    required ValueChanged<ConversationRecord> onPick,
    required VoidCallback onForget,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ConversationHistorySheet(
        folderPath: folderPath,
        onPick: onPick,
        onForget: onForget,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final saved = ref.watch(savedConversationsProvider(folderPath));

    return Dialog(
      backgroundColor: colors.rise,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.rule2),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.history,
                style: NexusTypography.label.copyWith(color: colors.cyan),
              ),
              const SizedBox(height: NexusSpacing.s2),
              Text(
                strings.historyExplainer,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
              const SizedBox(height: NexusSpacing.s5),
              Flexible(
                child: saved.when(
                  loading: () => const SizedBox.shrink(),
                  // Que falle leer el historial no es «no hay historial»: se
                  // dice, porque son cosas muy distintas para quien busca algo
                  // que sabe que estaba ahí.
                  error: (error, _) => Text(
                    '$error',
                    style: NexusTypography.mono.copyWith(color: colors.err),
                  ),
                  data: (records) => records.isEmpty
                      ? Text(
                          strings.nothingAskedYet,
                          style: NexusTypography.mono.copyWith(
                            color: colors.faint,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: records.length,
                          itemBuilder: (context, index) => _Row(
                            record: records[index],
                            onTap: () {
                              Navigator.of(context).pop();
                              onPick(records[index]);
                            },
                          ),
                        ),
                ),
              ),
              const SizedBox(height: NexusSpacing.s5),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onForget();
                },
                child: Text(strings.startFromScratch),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.record, required this.onTap});

  final ConversationRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final when = record.startedAt;
    String two(int value) => value.toString().padLeft(2, '0');

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La fecha delante y en monoespaciada: así las columnas cuadran y
            // la lista se puede recorrer con la vista en vertical.
            Text(
              '${when.year}-${two(when.month)}-${two(when.day)} ${two(when.hour)}:${two(when.minute)}',
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
            const SizedBox(width: NexusSpacing.s4),
            Expanded(
              child: Text(
                record.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.body.copyWith(color: colors.ink),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            Text(
              '${record.messages.length}',
              style: NexusTypography.data.copyWith(color: colors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

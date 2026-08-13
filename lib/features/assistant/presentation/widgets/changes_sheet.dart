import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// El `git diff` de **la tarea que acaba de terminar**.
///
/// La otra mitad de «sin git no hay red de seguridad»: saber que se puede
/// deshacer no sirve de nada si no se ve qué se hizo. Y es de esa tarea, no de
/// la conversación: acumular haría que el quinto encargo enseñara también los
/// cuatro anteriores, y revisar «qué acaba de hacer» sería buscar una aguja
/// entre lo que ya diste por bueno.
class ChangesSheet extends StatelessWidget {
  const ChangesSheet({super.key, required this.changes});

  final GitChanges changes;

  static Future<void> open(BuildContext context, GitChanges changes) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangesSheet(changes: changes),
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
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.strings.changesTitle,
                style: NexusTypography.label.copyWith(color: colors.cyan),
              ),
              const SizedBox(height: NexusSpacing.s4),
              for (final file in changes.newFiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${context.strings.newFile}  $file',
                    style: NexusTypography.mono.copyWith(color: colors.ok),
                  ),
                ),
              if (changes.newFiles.isNotEmpty)
                const SizedBox(height: NexusSpacing.s4),
              Flexible(
                child: SingleChildScrollView(
                  // Horizontal además de vertical: una línea de código larga no
                  // se parte, y partirla aquí haría ilegible justo lo que se
                  // viene a leer.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText.rich(
                      TextSpan(children: _spans(colors)),
                      style: NexusTypography.mono.copyWith(height: 1.45),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Verde lo que entra, rojo lo que sale, y en gris lo que solo sitúa. Es la
  /// convención de cualquier diff: reinventarla aquí obligaría a leerla.
  List<TextSpan> _spans(NexusColors colors) {
    return [
      for (final line in changes.diff.split('\n'))
        TextSpan(
          text: '$line\n',
          style: TextStyle(color: _colorFor(line, colors)),
        ),
    ];
  }

  Color _colorFor(String line, NexusColors colors) {
    if (line.startsWith('+++') || line.startsWith('---')) return colors.faint;
    if (line.startsWith('+')) return colors.ok;
    if (line.startsWith('-')) return colors.err;
    if (line.startsWith('@@')) return colors.cyan;
    if (line.startsWith('diff --git')) return colors.ink;
    return colors.mute;
  }
}

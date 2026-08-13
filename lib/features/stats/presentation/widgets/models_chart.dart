import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/stats/domain/entities/usage_stats.dart';
import 'package:nexus/features/stats/domain/usecases/model_label.dart';

/// En qué modelo se va el trabajo.
///
/// La barra por modelo y no una tarta: lo que se compara son magnitudes muy
/// distintas —el primero se lleva dos tercios y el último un 0,1 %—, y en una
/// tarta esos últimos son astillas sin nombre. En barras, el pequeño sigue
/// siendo legible aunque mida tres píxeles.
class ModelsChart extends StatelessWidget {
  const ModelsChart({super.key, required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    if (stats.models.isEmpty) {
      return Text(
        strings.statsNothingYet,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    final top = stats.models.first.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final usage in stats.models) ...[
          Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  modelLabel(usage.model),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      // Un mínimo de dos píxeles: sin él, el modelo que se usó
                      // una vez desaparece y su fila queda con una etiqueta y
                      // nada al lado, que se lee como un fallo de dibujo.
                      width: (constraints.maxWidth * usage.tokens / top).clamp(
                        2.0,
                        constraints.maxWidth,
                      ),
                      height: 16,
                      decoration: BoxDecoration(
                        color: colors.cyan.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: NexusSpacing.s3),
              SizedBox(
                width: 46,
                child: Text(
                  '${(usage.share * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: NexusTypography.data.copyWith(color: colors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 90, bottom: NexusSpacing.s4),
            child: Text(
              // Entrada y salida por separado porque no cuestan lo mismo ni se
              // parecen: aquí la salida es el 98 % de todo, y un total único lo
              // escondería.
              strings.statsInOut(_compact(usage.input), _compact(usage.output)),
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),
        ],
      ],
    );
  }
}

String _compact(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

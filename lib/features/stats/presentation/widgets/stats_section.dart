import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/stats/domain/entities/usage_stats.dart';
import 'package:nexus/features/stats/domain/usecases/compute_stats.dart';
import 'package:nexus/features/stats/domain/usecases/model_label.dart';
import 'package:nexus/features/stats/presentation/providers/stats_providers.dart';
import 'package:nexus/features/stats/presentation/widgets/activity_heatmap.dart';
import 'package:nexus/features/stats/presentation/widgets/models_chart.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Qué se ha hecho con Claude, por cuenta.
///
/// Sale de los transcritos que el propio CLI deja en el disco, que es la única
/// fuente que hay: el endpoint de cuota dice cuánto te queda de la suscripción
/// —eso ya está en la barra—, no qué has hecho con ella.
class StatsSection extends ConsumerStatefulWidget {
  const StatsSection({super.key});

  @override
  ConsumerState<StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends ConsumerState<StatsSection> {
  String? _profile;
  var _range = StatsRange.all;
  var _models = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final profiles = ref.watch(claudeProfilesProvider).value ?? const [];
    if (profiles.isEmpty) return _Empty(message: strings.statsNoAccounts);

    // Como en el historial: las pestañas separan cuentas, así que **solo
    // existen si hay más de una** en el Mac. Con una sola, dividir en pestañas
    // inventa una frontera donde no la hay.
    final current = profiles.any((profile) => profile.path == _profile)
        ? _profile!
        : profiles.first.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profiles.length > 1)
          Row(
            children: [
              for (final profile in profiles)
                Expanded(
                  child: _Tab(
                    label: profile.name,
                    active: profile.path == current,
                    onTap: () => setState(() => _profile = profile.path),
                  ),
                ),
            ],
          ),
        const SizedBox(height: NexusSpacing.s5),
        Row(
          children: [
            _Toggle(
              label: strings.statsOverview,
              active: !_models,
              onTap: () => setState(() => _models = false),
            ),
            const SizedBox(width: NexusSpacing.s2),
            _Toggle(
              label: strings.statsModels,
              active: _models,
              onTap: () => setState(() => _models = true),
            ),
            const Spacer(),
            for (final range in StatsRange.values) ...[
              const SizedBox(width: NexusSpacing.s2),
              _Toggle(
                label: switch (range) {
                  StatsRange.all => strings.statsRangeAll,
                  StatsRange.days30 => strings.statsRange30,
                  StatsRange.days7 => strings.statsRange7,
                },
                active: _range == range,
                onTap: () => setState(() => _range = range),
              ),
            ],
          ],
        ),
        const SizedBox(height: NexusSpacing.s5),
        Expanded(
          child: ref
              .watch(transcriptTurnsProvider(current))
              .when(
                // Leer 186 MB lleva un par de segundos y se hace en otro
                // isolate: la ventana sigue viva, así que aquí basta con decir
                // que se está leyendo.
                loading: () => _Empty(message: strings.statsReading),
                error: (_, _) => _Empty(message: strings.statsUnreadable),
                data: (turns) {
                  final stats = ComputeStats.from(
                    turns,
                    _range,
                    now: DateTime.now(),
                  );
                  if (stats.isEmpty) {
                    return _Empty(message: strings.statsNothingYet);
                  }
                  return SingleChildScrollView(
                    child: _models
                        ? ModelsChart(stats: stats)
                        : _Overview(stats: stats),
                  );
                },
              ),
        ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.colors;
    final favorite = stats.favoriteModel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: NexusSpacing.s3,
          runSpacing: NexusSpacing.s3,
          children: [
            _Card(label: strings.statsSessions, value: '${stats.sessions}'),
            _Card(
              label: strings.statsMessages,
              value: _thousands(stats.messages),
            ),
            _Card(
              label: strings.statsTotalTokens,
              value: _compact(stats.tokens),
            ),
            _Card(label: strings.statsActiveDays, value: '${stats.activeDays}'),
            _Card(
              label: strings.statsCurrentStreak,
              value: '${stats.currentStreak}d',
            ),
            _Card(
              label: strings.statsLongestStreak,
              value: '${stats.longestStreak}d',
            ),
            _Card(
              label: strings.statsPeakHour,
              value: stats.peakHour == null ? '—' : '${stats.peakHour}:00',
            ),
            _Card(
              label: strings.statsFavoriteModel,
              value: favorite == null ? '—' : modelLabel(favorite),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s5),
        ActivityHeatmap(days: stats.days),
        const SizedBox(height: NexusSpacing.s4),
        // Los tokens en caché van aquí abajo y no como ficha: son de verdad y
        // son enormes —dos órdenes de magnitud por encima de todo lo demás—,
        // así que sumarlos al total convertiría cualquier gráfico en una barra
        // sola, y esconderlos sería contar la mitad.
        Text(
          strings.statsCachedFootnote(_compact(stats.cached)),
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

String _thousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _compact(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

class _Card extends StatelessWidget {
  const _Card({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 137,
      padding: const EdgeInsets.all(NexusSpacing.s3),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NexusTypography.data.copyWith(
              color: colors.ink,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NexusRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s3,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: active ? colors.rise : Colors.transparent,
          border: Border.all(color: active ? colors.rule : Colors.transparent),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Text(
          label,
          style: NexusTypography.label.copyWith(
            color: active ? colors.ink : colors.faint,
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? colors.cyan : colors.rule,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: NexusTypography.label.copyWith(
            color: active ? colors.cyan : colors.faint,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Text(
      message,
      style: NexusTypography.mono.copyWith(color: context.colors.faint),
    ),
  );
}

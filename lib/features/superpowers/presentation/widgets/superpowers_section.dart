import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/superpowers/presentation/widgets/mcp_panel.dart';
import 'package:nexus/features/superpowers/presentation/widgets/plugins_panel.dart';
import 'package:nexus/features/superpowers/presentation/widgets/skills_panel.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Lo que Claude sabe hacer de más, por cuenta.
///
/// Va todo junto porque es la misma idea —cosas que se instalan en el
/// `CLAUDE_CONFIG_DIR` de una cuenta y que las sesiones headless usan solas, sin
/// que nadie se las pida— y porque se gestionan igual: se leen del disco y se
/// cambian por el CLI, para no reimplementar su semántica.
class SuperpowersSection extends ConsumerStatefulWidget {
  const SuperpowersSection({super.key});

  @override
  ConsumerState<SuperpowersSection> createState() => _SuperpowersSectionState();
}

/// Las dos mitades: manos fuera del disco y procedimientos aprendidos.
enum _Kind { mcp, skills, plugins }

class _SuperpowersSectionState extends ConsumerState<SuperpowersSection> {
  String? _profile;
  var _kind = _Kind.mcp;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.colors;
    final profiles = ref.watch(claudeProfilesProvider).value ?? const [];
    if (profiles.isEmpty) {
      return Text(
        strings.statsNoAccounts,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    // Misma regla que el historial y las estadísticas: las pestañas separan
    // cuentas y solo existen si hay más de una en el Mac.
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
            for (final kind in _Kind.values) ...[
              _Toggle(
                label: switch (kind) {
                  _Kind.mcp => strings.superpowersMcp,
                  _Kind.skills => strings.superpowersSkills,
                  _Kind.plugins => strings.superpowersPlugins,
                },
                active: _kind == kind,
                onTap: () => setState(() => _kind = kind),
              ),
              const SizedBox(width: NexusSpacing.s2),
            ],
          ],
        ),
        const SizedBox(height: NexusSpacing.s5),
        // La clave fuerza a rehacer el panel al cambiar de cuenta: sin ella, lo
        // escrito a medias en el formulario de una cuenta se quedaría delante
        // de la lista de la otra.
        Expanded(
          child: switch (_kind) {
            _Kind.mcp => McpPanel(
              key: ValueKey('mcp-$current'),
              configDir: current,
            ),
            _Kind.skills => SkillsPanel(
              key: ValueKey('skills-$current'),
              configDir: current,
            ),
            _Kind.plugins => PluginsPanel(
              key: ValueKey('plugins-$current'),
              configDir: current,
            ),
          },
        ),
      ],
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

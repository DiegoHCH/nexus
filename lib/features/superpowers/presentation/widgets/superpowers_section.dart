import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/superpowers/presentation/widgets/hooks_panel.dart';
import 'package:nexus/features/superpowers/presentation/widgets/mcp_panel.dart';
import 'package:nexus/features/superpowers/presentation/widgets/plugins_panel.dart';
import 'package:nexus/features/superpowers/presentation/widgets/skills_panel.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';

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

/// Manos fuera del disco, procedimientos aprendidos, paquetes de los dos — y los ganchos.
///
/// Los ganchos van los últimos y no los primeros aunque sean los que más mandan: son dos,
/// se ponen una vez y no se vuelven a tocar, mientras que los MCP y las skills se miran
/// cada semana.
enum _Kind { mcp, skills, plugins, hooks }

class _SuperpowersSectionState extends ConsumerState<SuperpowersSection> {
  String? _profile;
  var _kind = _Kind.mcp;

  /// Si lo que se instale va a todas las cuentas o solo a la elegida.
  ///
  /// **Nace apagado**: instalar en cuentas que no se están mirando es un efecto que
  /// hay que pedir, no heredar. Y no se recuerda entre visitas por lo mismo — una
  /// casilla marcada la semana pasada tocaría cuentas sin que nadie lo decida hoy.
  var _enTodas = false;

  /// Las demás cuentas, si se pidió instalar en todas.
  List<String> _otras(List<ClaudeProfile> profiles, String current) => _enTodas
      ? [for (final p in profiles) p.path].where((p) => p != current).toList()
      : const [];

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
        if (profiles.length > 1) ...[
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
          const SizedBox(height: NexusSpacing.s3),
          // **El aviso va aquí y no en cada panel**: no es de los MCP ni de las
          // skills, es de las pestañas de arriba. Y va siempre, no solo al fallar:
          // enterarse por el síntoma —«en esta carpeta funciona y en esta no»— cuesta
          // mucho más que leerlo antes.
          _AvisoDeCuenta(
            enTodas: _enTodas,
            cuantas: profiles.length,
            alCambiar: (valor) => setState(() => _enTodas = valor),
          ),
        ],
        const SizedBox(height: NexusSpacing.s5),
        Row(
          children: [
            for (final kind in _Kind.values) ...[
              _Toggle(
                label: switch (kind) {
                  _Kind.mcp => strings.superpowersMcp,
                  _Kind.skills => strings.superpowersSkills,
                  _Kind.plugins => strings.superpowersPlugins,
                  _Kind.hooks => strings.superpowersHooks,
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
              key: ValueKey('mcp-$current-$_enTodas'),
              tambienEn: _otras(profiles, current),
              configDir: current,
            ),
            _Kind.skills => SkillsPanel(
              key: ValueKey('skills-$current-$_enTodas'),
              tambienEn: _otras(profiles, current),
              configDir: current,
            ),
            _Kind.plugins => PluginsPanel(
              key: ValueKey('plugins-$current'),
              configDir: current,
            ),
            _Kind.hooks => HooksPanel(
              key: ValueKey('hooks-$current-$_enTodas'),
              tambienEn: _otras(profiles, current),
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
              color: active ? colors.accent : colors.rule,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: NexusTypography.label.copyWith(
            color: active ? colors.accent : colors.faint,
          ),
        ),
      ),
    );
  }
}

/// La casilla de «en todas las cuentas», con su aviso debajo.
///
/// Un párrafo y no un icono con globo: lo que hay que decir no cabe en un adorno, y es
/// justo la clase de cosa que se descubre tarde y se diagnostica mal — el síntoma es
/// «en esta carpeta funciona y en esta no», que no menciona cuentas en ninguna parte.
class _AvisoDeCuenta extends StatelessWidget {
  const _AvisoDeCuenta({
    required this.enTodas,
    required this.cuantas,
    required this.alCambiar,
  });

  final bool enTodas;
  final int cuantas;
  final ValueChanged<bool> alCambiar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => alCambiar(!enTodas),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s2),
            child: Row(
              children: [
                // Un cuadro con hairline y un punto dentro, como el resto del sistema:
                // una casilla de Material aquí se ve de otra app.
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: enTodas ? colors.accent : colors.rule2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: enTodas
                      ? Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: NexusSpacing.s3),
                Text(
                  '${strings.superpowersEverywhere}  ($cuantas)',
                  style: NexusTypography.label.copyWith(
                    color: enTodas ? colors.accent : colors.mute,
                  ),
                ),
              ],
            ),
          ),
        ),
        // El aviso solo cuando **no** se instala en todas: con la casilla marcada deja
        // de ser verdad, y un aviso que miente es peor que ninguno.
        if (!enTodas)
          Text(
            strings.superpowersOnlyHere,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
      ],
    );
  }
}

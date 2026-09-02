import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/superpowers/domain/entities/claude_plugin.dart';
import 'package:nexus/features/superpowers/domain/usecases/plugin_command.dart';
import 'package:nexus/features/superpowers/presentation/providers/superpowers_providers.dart';

/// Los plugins de una cuenta: los puestos, los marketplaces de donde salen, y
/// el catálogo con buscador.
class PluginsPanel extends ConsumerStatefulWidget {
  const PluginsPanel({super.key, required this.configDir});

  final String configDir;

  @override
  ConsumerState<PluginsPanel> createState() => _PluginsPanelState();
}

class _PluginsPanelState extends ConsumerState<PluginsPanel> {
  final _search = TextEditingController();
  final _market = TextEditingController();
  var _query = '';
  var _busy = false;
  String? _error;

  /// Cuántos del catálogo se pintan.
  ///
  /// El marketplace oficial trae 287 y casi ninguno se va a instalar. Se
  /// enseñan los veinte más usados y el buscador saca el resto: dibujar los 287
  /// es una lista por la que nadie baja.
  static const _shown = 20;

  @override
  void dispose() {
    _search.dispose();
    _market.dispose();
    super.dispose();
  }

  Future<void> _act(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    ref
      ..invalidate(pluginsProvider(widget.configDir))
      ..invalidate(marketplacesProvider(widget.configDir));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _showDetails(String name) async {
    final text = await ref
        .read(pluginsDataSourceProvider)
        .details(widget.configDir, name);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.deep,
        title: Text(
          name,
          style: NexusTypography.data.copyWith(color: context.colors.ink),
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: SelectableText(
              text ?? context.strings.pluginsNoDetails,
              style: NexusTypography.mono.copyWith(color: context.colors.mute),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.strings.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final plugins = ref.watch(pluginsProvider(widget.configDir));
    final markets =
        ref.watch(marketplacesProvider(widget.configDir)).value ?? const [];

    final all = plugins.value ?? const <ClaudePlugin>[];
    final installed = all.where((plugin) => plugin.installed).toList();
    final rest = PluginCommand.search(
      all.where((plugin) => !plugin.installed).toList(),
      _query,
    );

    return ListView(
      children: [
        Text(
          strings.pluginsExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),

        _Heading(strings.pluginsInstalled),
        if (plugins.isLoading)
          Text(
            strings.pluginsLoading,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else if (installed.isEmpty)
          Text(
            strings.pluginsNone,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        for (final plugin in installed)
          _PluginRow(
            plugin: plugin,
            busy: _busy,
            actions: [
              // Apagar sin desinstalar: un plugin ocupa contexto en cada
              // sesión, y a veces lo que quieres es dejar de pagarlo sin perder
              // la configuración.
              _Action(
                icon: plugin.enabled ? Icons.toggle_on : Icons.toggle_off,
                tooltip: plugin.enabled
                    ? strings.pluginsDisable
                    : strings.pluginsEnable,
                onTap: () => _act(
                  () => ref
                      .read(pluginsDataSourceProvider)
                      .setEnabled(
                        widget.configDir,
                        plugin.id,
                        enabled: !plugin.enabled,
                      ),
                ),
              ),
              _Action(
                icon: Icons.info_outline,
                tooltip: strings.pluginsDetails,
                onTap: () => _showDetails(plugin.name),
              ),
              _Action(
                icon: Icons.refresh,
                tooltip: strings.pluginsUpdate,
                onTap: () => _act(
                  () => ref
                      .read(pluginsDataSourceProvider)
                      .update(widget.configDir, plugin.id),
                ),
              ),
              _Action(
                icon: Icons.close,
                tooltip: strings.pluginsUninstall,
                onTap: () => _act(
                  () => ref
                      .read(pluginsDataSourceProvider)
                      .uninstall(widget.configDir, plugin.id),
                ),
              ),
            ],
          ),

        const SizedBox(height: NexusSpacing.s6),
        _Heading(strings.pluginsMarketplaces),
        for (final market in markets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 190,
                  child: Text(
                    market.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.data.copyWith(color: colors.ink),
                  ),
                ),
                Expanded(
                  child: Text(
                    market.repo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                ),
                _Action(
                  icon: Icons.close,
                  tooltip: strings.pluginsRemoveMarketplace,
                  busy: _busy,
                  onTap: () => _act(
                    () => ref
                        .read(pluginsDataSourceProvider)
                        .removeMarketplace(widget.configDir, market.name),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _market,
                hint: strings.pluginsMarketplaceHint,
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await _act(
                        () => ref
                            .read(pluginsDataSourceProvider)
                            .addMarketplace(widget.configDir, _market.text),
                      );
                      if (_error == null) _market.clear();
                    },
              child: Text(strings.pluginsAddMarketplace),
            ),
          ],
        ),

        const SizedBox(height: NexusSpacing.s6),
        _Heading(strings.pluginsCatalog(all.length)),
        _Field(
          controller: _search,
          hint: strings.pluginsSearchHint,
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: NexusSpacing.s3),
        for (final plugin in rest.take(_shown))
          _PluginRow(
            plugin: plugin,
            busy: _busy,
            actions: [
              _Action(
                icon: Icons.add,
                tooltip: strings.pluginsInstall,
                onTap: () => _act(
                  () => ref
                      .read(pluginsDataSourceProvider)
                      .install(widget.configDir, plugin.id),
                ),
              ),
            ],
          ),
        // Decir cuántos se dejan fuera, en vez de cortar en silencio: sin esto,
        // veinte de doscientos ochenta y siete se leen como «esto es todo».
        if (rest.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s2),
            child: Text(
              strings.pluginsMore(rest.length - _shown),
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),

        if (_error case final message?) ...[
          const SizedBox(height: NexusSpacing.s3),
          Text(
            message,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }
}

class _PluginRow extends StatelessWidget {
  const _PluginRow({
    required this.plugin,
    required this.actions,
    required this.busy,
  });

  final ClaudePlugin plugin;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      plugin.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NexusTypography.data.copyWith(
                        color: plugin.installed && !plugin.enabled
                            ? colors.faint
                            : colors.ink,
                      ),
                    ),
                  ),
                  // La versión de lo que está puesto. Va aquí y no en la
                  // descripción porque es lo primero que se pregunta de un
                  // plugin propio —«¿tengo la última?»— y porque un instalado
                  // llega sin `installCount`, así que este hueco está libre.
                  if (plugin.version != null) ...[
                    const SizedBox(width: NexusSpacing.s2),
                    Text(
                      'v${plugin.version}',
                      style: NexusTypography.label.copyWith(
                        color: colors.faint,
                      ),
                    ),
                  ],
                  if (plugin.installs > 0) ...[
                    const SizedBox(width: NexusSpacing.s2),
                    Text(
                      _installs(plugin.installs),
                      style: NexusTypography.label.copyWith(
                        color: colors.faint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                plugin.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
            ),
          ),
          for (final action in actions) action,
        ],
      ),
    );
  }

  static String _installs(int count) =>
      count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}k' : '$count';
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: busy ? null : onTap,
    icon: Icon(icon, size: 15, color: context.colors.faint),
    splashRadius: 14,
    tooltip: tooltip,
    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    padding: EdgeInsets.zero,
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: NexusSpacing.s2),
    child: Text(
      text,
      style: NexusTypography.label.copyWith(color: context.colors.accent),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: NexusTypography.mono.copyWith(color: colors.ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: NexusTypography.mono.copyWith(color: colors.rule2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s3,
          vertical: NexusSpacing.s3,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.rule),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.accent),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
      ),
    );
  }
}

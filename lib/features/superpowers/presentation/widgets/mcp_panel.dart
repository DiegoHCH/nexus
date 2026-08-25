import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_catalog.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';
import 'package:nexus/features/superpowers/presentation/providers/superpowers_providers.dart';
import 'package:nexus/features/superpowers/domain/usecases/fallos_por_cuenta.dart';

/// Los servidores MCP de una cuenta: los que hay, los que se pueden poner de un
/// clic, y uno a mano.
class McpPanel extends ConsumerStatefulWidget {
  const McpPanel({
    super.key,
    required this.configDir,
    this.tambienEn = const [],
  });

  final String configDir;

  /// Las demás cuentas donde replicar lo que se instale aquí.
  ///
  /// Vacío es lo normal: solo la de arriba. Va como lista y no como un booleano «en
  /// todas» porque este panel no sabe cuántas cuentas hay ni cómo se llaman — eso lo
  /// decide la sección, que es quien tiene las pestañas.
  final List<String> tambienEn;

  @override
  ConsumerState<McpPanel> createState() => _McpPanelState();
}

class _McpPanelState extends ConsumerState<McpPanel> {
  final _name = TextEditingController();
  final _spec = TextEditingController();
  var _busy = false;
  var _checking = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _spec.dispose();
    super.dispose();
  }

  Future<void> _install(
    String name, {
    String? url,
    List<String> command = const [],
    String? comoSeInstala,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    // **El binario, antes de registrar nada.** `claude mcp add` acepta cualquier
    // comando sin comprobar que exista: se instalaría con un tic verde y fallaría
    // la primera vez que un encargo lo use, en headless, diciendo algo que no se
    // parece a esto. Aquí el aviso llega donde se pulsó el botón.
    final binario = command.isEmpty ? null : command.first;
    if (binario != null &&
        !ref.read(mcpDataSourceProvider).hayBinario(binario)) {
      setState(() {
        _busy = false;
        // Sin traducir y con la ruta del comando dentro, como los errores del
        // CLI que este panel ya muestra literales: lo accionable es el comando,
        // y un «no se pudo instalar» obliga a abrir la terminal para averiguar
        // qué faltaba.
        _error = comoSeInstala == null
            ? 'No se encuentra «$binario». Instálalo y vuelve a intentarlo.'
            : 'No se encuentra «$binario». Instálalo con: $comoSeInstala';
      });
      return;
    }
    final error = await ref
        .read(mcpDataSourceProvider)
        // A la cuenta de arriba **y a las demás si se pidió**. Aquí el síntoma de
        // tenerlo en una sola es el peor de leer: «no puedo consultar tu calendario»
        // no se parece a un problema de cuentas.
        .addEn(
          [widget.configDir, ...widget.tambienEn],
          name: name,
          url: url,
          command: command,
        )
        .then(FallosPorCuenta.primero);
    ref.invalidate(mcpServersProvider(widget.configDir));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _remove(String name) async {
    setState(() => _busy = true);
    final error = await ref
        .read(mcpDataSourceProvider)
        .remove(widget.configDir, name);
    ref.invalidate(mcpServersProvider(widget.configDir));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  /// Lo escrito a mano puede ser una URL o un comando, y se distingue solo: lo
  /// que empieza por `http` es lo primero. Pedir que el usuario elija el tipo
  /// en un desplegable sería preguntarle algo que ya dijo al escribirlo.
  Future<void> _addManual() async {
    final name = _name.text.trim();
    final spec = _spec.text.trim();
    if (name.isEmpty || spec.isEmpty) return;
    final isUrl = spec.startsWith('http://') || spec.startsWith('https://');
    await _install(
      name,
      url: isUrl ? spec : null,
      command: isUrl ? const [] : spec.split(RegExp(r'\s+')),
    );
    if (_error == null && mounted) {
      _name.clear();
      _spec.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final installed =
        ref.watch(mcpServersProvider(widget.configDir)).value ?? const [];
    final names = installed.map((server) => server.name).toSet();
    final health = _checking
        ? ref.watch(mcpHealthProvider(widget.configDir))
        : null;

    return ListView(
      children: [
        Text(
          strings.mcpExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),

        _Heading(strings.mcpInstalled),
        if (installed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
            child: Text(
              strings.mcpNone,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),
        for (final server in installed)
          _ServerRow(
            server: server,
            enabled: !_busy,
            onRemove: () => _remove(server.name),
          ),

        const SizedBox(height: NexusSpacing.s4),
        Row(
          children: [
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      ref.invalidate(mcpHealthProvider(widget.configDir));
                      setState(() => _checking = true);
                    },
              child: Text(strings.mcpCheck),
            ),
            const SizedBox(width: NexusSpacing.s3),
            Expanded(
              child: Text(
                strings.mcpCheckNote,
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
            ),
          ],
        ),
        if (health != null) ...[
          const SizedBox(height: NexusSpacing.s3),
          switch (health) {
            AsyncData(:final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final server in value)
                  _ServerRow(server: server, enabled: false),
              ],
            ),
            AsyncData() => Text(
              strings.mcpCheckFailed,
              style: NexusTypography.mono.copyWith(color: colors.warn),
            ),
            AsyncError() => Text(
              strings.mcpCheckFailed,
              style: NexusTypography.mono.copyWith(color: colors.warn),
            ),
            _ => Text(
              strings.mcpChecking,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          },
        ],

        const SizedBox(height: NexusSpacing.s6),
        _Heading(strings.mcpCatalog),
        for (final entry in McpCatalog.entries)
          _CatalogRow(
            entry: entry,
            already: names.contains(entry.name),
            enabled: !_busy,
            onAdd: () => _install(
              entry.name,
              url: entry.url,
              command: entry.command,
              comoSeInstala: entry.comoSeInstala,
            ),
          ),

        const SizedBox(height: NexusSpacing.s6),
        _Heading(strings.mcpManual),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: _Field(controller: _name, hint: strings.mcpNameHint),
            ),
            const SizedBox(width: NexusSpacing.s3),
            Expanded(
              child: _Field(controller: _spec, hint: strings.mcpSpecHint),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: _busy ? null : _addManual,
              child: Text(strings.mcpAdd),
            ),
          ],
        ),
        if (_error case final message?) ...[
          const SizedBox(height: NexusSpacing.s3),
          // Lo que dijo el CLI, literal: «ya existe uno con ese nombre» o «no
          // se pudo resolver el comando» es accionable, y taparlo con un «no se
          // pudo» obliga a abrir la terminal para saber qué pasó.
          Text(
            message,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.server, this.enabled = true, this.onRemove});

  final McpServer server;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (server.status != McpStatus.unknown) ...[
            Icon(
              switch (server.status) {
                McpStatus.connected => Icons.check_circle_outline,
                McpStatus.needsAuth => Icons.lock_outline,
                _ => Icons.error_outline,
              },
              size: 13,
              color: switch (server.status) {
                McpStatus.connected => colors.ok,
                McpStatus.needsAuth => colors.warn,
                _ => colors.err,
              },
            ),
            const SizedBox(width: NexusSpacing.s2),
          ],
          SizedBox(
            width: 150,
            child: Text(
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.data.copyWith(color: colors.ink),
            ),
          ),
          Expanded(
            child: Text(
              server.spec,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),
          // Los conectores de claude.ai llegan con la sesión y se gestionan
          // allí: un botón de quitar que no puede quitar es peor que ninguno.
          if (onRemove != null && !server.fromAccount)
            IconButton(
              onPressed: enabled ? onRemove : null,
              icon: Icon(Icons.close, size: 14, color: colors.faint),
              splashRadius: 14,
              tooltip: context.strings.mcpRemove,
            ),
        ],
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.entry,
    required this.already,
    required this.enabled,
    required this.onAdd,
  });

  final McpCatalogEntry entry;
  final bool already;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              entry.name,
              style: NexusTypography.data.copyWith(
                color: already ? colors.faint : colors.ink,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.what,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),
          const SizedBox(width: NexusSpacing.s3),
          if (already)
            Icon(Icons.check, size: 14, color: colors.ok)
          else
            IconButton(
              onPressed: enabled ? onAdd : null,
              icon: Icon(Icons.add, size: 15, color: colors.accent),
              splashRadius: 14,
              tooltip: context.strings.mcpAdd,
            ),
        ],
      ),
    );
  }
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
  const _Field({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TextField(
      controller: controller,
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

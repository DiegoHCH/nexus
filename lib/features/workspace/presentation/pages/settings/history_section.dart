import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/history/presentation/providers/slack_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Historial: dónde se archivan las conversaciones cuando terminan.

/// Dónde acaban las conversaciones.
///
/// Los tres destinos son del usuario, no del programa, y por eso el estado de
/// partida es «en ningún sitio»: sacar lo que hablas de esta máquina es una
/// decisión suya, no algo que pase por omisión.
class HistorySection extends ConsumerWidget {
  const HistorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final settings = ref.watch(archiveControllerProvider);
    final controller = ref.read(archiveControllerProvider.notifier);

    String label(ArchiveDestination option) => switch (option) {
      ArchiveDestination.none => strings.archiveNone,
      ArchiveDestination.folder => strings.archiveFolder,
      ArchiveDestination.obsidian => strings.archiveObsidian,
      ArchiveDestination.notion => strings.archiveNotion,
    };
    String hint(ArchiveDestination option) => switch (option) {
      ArchiveDestination.none => strings.archiveNoneHint,
      ArchiveDestination.folder => strings.archiveFolderHint,
      ArchiveDestination.obsidian => strings.archiveObsidianHint,
      ArchiveDestination.notion => strings.archiveNotionHint,
    };

    // Con su propio scroll, como Ayuda y Voz y por lo mismo: el cuerpo de una
    // sección no lo trae, y esta pasó de «a dónde archivo» a llevar además el
    // parte del día con su token y su destino. Lo último se salía por abajo —
    // lo dijeron las pruebas que abren todas las secciones.
    return ListView(
      children: [
        Text(
          strings.archiveTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.archiveExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        for (final option in ArchiveDestination.values)
          InkWell(
            onTap: () => controller.selectDestination(option),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    option == settings.destination
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 15,
                    color: option == settings.destination
                        ? colors.accent
                        : colors.faint,
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label(option),
                          style: NexusTypography.data.copyWith(
                            color: option == settings.destination
                                ? colors.ink
                                : colors.mute,
                          ),
                        ),
                        Text(
                          hint(option),
                          style: NexusTypography.mono.copyWith(
                            color: colors.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (settings.destination == ArchiveDestination.notion) ...[
          const SizedBox(height: NexusSpacing.s5),
          _NotionFields(settings: settings, controller: controller),
        ],
        // El parte del día, junto al destino de archivo: es la misma pregunta
        // —a dónde mando mi trabajo— y no merece una sección propia.
        const SizedBox(height: NexusSpacing.s7),
        Divider(color: colors.rule, height: 1),
        const SizedBox(height: NexusSpacing.s6),
        const _ParteAlSlack(),
        if (settings.destination.needsFolder) ...[
          const SizedBox(height: NexusSpacing.s5),
          Row(
            children: [
              OutlinedButton(
                onPressed: () async {
                  final chosen = await getDirectoryPath();
                  if (chosen != null) await controller.selectFolder(chosen);
                },
                child: Text(strings.archiveChooseFolder),
              ),
              const SizedBox(width: NexusSpacing.s4),
              Expanded(
                child: Text(
                  settings.folderPath ?? '',
                  style: NexusTypography.mono.copyWith(color: colors.mute),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.s3),
          Text(
            settings.isReady
                ? strings.archiveLayout(settings.folderPath!)
                : strings.archiveNoFolderYet,
            style: NexusTypography.mono.copyWith(
              color: settings.isReady ? colors.faint : colors.warn,
            ),
          ),
        ],
      ],
    );
  }
}

/// El token y la página de Notion.
///
/// Se pide aquí y no en la configuración inicial porque no es un requisito para
/// usar Nexus: es una decisión de dónde quieres tus conversaciones. El token
/// viaja al llavero, como la llave de Gemini — no a las preferencias en claro.
/// A dónde va el parte del día, y con qué permiso.
///
/// **El token se escribe y no se vuelve a ver**: al guardarlo el campo se
/// vacía, y lo único que queda en pantalla es si hay uno. Enseñar un secreto
/// recortado no sirve para compararlo y sí para que aparezca en la captura de
/// pantalla de alguien enseñando la app.
class _ParteAlSlack extends ConsumerStatefulWidget {
  const _ParteAlSlack();

  @override
  ConsumerState<_ParteAlSlack> createState() => _ParteAlSlackState();
}

class _ParteAlSlackState extends ConsumerState<_ParteAlSlack> {
  final _token = TextEditingController();
  late final _destino = TextEditingController(
    text: ref.read(slackControllerProvider).destino ?? '',
  );
  String? _resultado;
  bool _probando = false;

  @override
  void dispose() {
    _token.dispose();
    _destino.dispose();
    super.dispose();
  }

  Future<void> _probar() async {
    setState(() {
      _probando = true;
      _resultado = null;
    });
    final fallo = await ref
        .read(slackControllerProvider.notifier)
        .mandar(context.strings.slackPrueba);
    if (!mounted) return;
    setState(() {
      _probando = false;
      _resultado = fallo ?? context.strings.slackLlego;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final slack = ref.watch(slackControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.slackTitle,
          style: NexusTypography.label.copyWith(color: colors.accent),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.slackExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),
        Text(
          slack.hayToken ? strings.slackConToken : strings.slackSinToken,
          style: NexusTypography.mono.copyWith(
            color: slack.hayToken ? colors.ok : colors.warn,
          ),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _token,
                obscureText: true,
                style: NexusTypography.mono.copyWith(color: colors.ink),
                decoration: InputDecoration(hintText: strings.slackTokenHint),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: () async {
                await ref
                    .read(slackControllerProvider.notifier)
                    .guardarToken(_token.text);
                _token.clear();
              },
              child: Text(strings.geminiKeySave),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s4),
        Text(
          strings.slackDestino,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        TextField(
          controller: _destino,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(hintText: strings.slackDestinoHint),
          onChanged: (valor) =>
              ref.read(slackControllerProvider.notifier).guardarDestino(valor),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.slackDestinoExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),
        // De qué proyecto se cuenta el trabajo. **Sin esto el parte mezclaría**
        // lo personal con lo del trabajo en el canal de un equipo, y eso no se
        // arregla acordándose cada mañana.
        Text(
          strings.slackProyecto,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Wrap(
          spacing: NexusSpacing.s2,
          runSpacing: NexusSpacing.s2,
          children: [
            for (final carpeta in [
              null,
              ...ref
                  .watch(workspaceControllerProvider)
                  .folders
                  .map((f) => f.path),
            ])
              OutlinedButton(
                onPressed: () => ref
                    .read(slackControllerProvider.notifier)
                    .guardarProyecto(carpeta),
                child: Text(
                  carpeta == null
                      ? strings.slackTodos
                      : carpeta.split('/').last,
                  style: NexusTypography.mono.copyWith(
                    color: carpeta == slack.proyecto
                        ? colors.accent
                        : colors.mute,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s4),
        Row(
          children: [
            OutlinedButton(
              onPressed: slack.listo && !_probando ? _probar : null,
              child: Text(
                _probando ? strings.slackProbando : strings.slackProbar,
              ),
            ),
            if (_resultado case final dicho?) ...[
              const SizedBox(width: NexusSpacing.s3),
              Expanded(
                child: Text(
                  dicho,
                  style: NexusTypography.mono.copyWith(
                    color: dicho == strings.slackLlego ? colors.ok : colors.err,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _NotionFields extends StatefulWidget {
  const _NotionFields({required this.settings, required this.controller});

  final ArchiveSettings settings;
  final ArchiveController controller;

  @override
  State<_NotionFields> createState() => _NotionFieldsState();
}

class _NotionFieldsState extends State<_NotionFields> {
  late final _page = TextEditingController(
    text: widget.settings.notionPage ?? '',
  );
  final _token = TextEditingController();

  @override
  void dispose() {
    _page.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final settings = widget.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.notionToken,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        TextField(
          controller: _token,
          obscureText: true,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(hintText: strings.notionTokenHint),
          onChanged: widget.controller.saveNotionToken,
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.notionTokenExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Text(
          strings.notionPage,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        TextField(
          controller: _page,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(hintText: strings.notionPageHint),
          onChanged: widget.controller.saveNotionPage,
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.notionPageExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),
        Text(
          settings.isReady ? strings.notionReady : strings.notionMissing,
          style: NexusTypography.mono.copyWith(
            color: settings.isReady ? colors.ok : colors.warn,
          ),
        ),
      ],
    );
  }
}

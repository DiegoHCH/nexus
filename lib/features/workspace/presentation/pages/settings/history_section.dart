import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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

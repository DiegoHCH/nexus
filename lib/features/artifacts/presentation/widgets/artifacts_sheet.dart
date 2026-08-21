import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/core/platform/system_files.dart';
import 'package:nexus/core/platform/system_thumbnails.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'dart:io';

/// Los documentos que han salido de las conversaciones, en una lista.
///
/// Existe porque hasta ahora un mockup terminado desaparecía: Claude lo escribe
/// en el disco, dice dónde, y a los diez minutos esa ruta está veinte mensajes
/// más arriba. Aquí están todos, y se abren sin salir de la app.
class ArtifactsSheet extends ConsumerWidget {
  const ArtifactsSheet({super.key});

  static Future<void> open(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const ArtifactsSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final folder = ref.watch(artifactsFolderProvider);
    // **Todo lo que es un documento**, no solo lo que el `WKWebView` pinta.
    //
    // Estuvo filtrado a lo que abría ese visor, y el resultado era que los noventa
    // `.md` de la carpeta no existían para esta pantalla: la lista decía «no hay nada»
    // teniendo ciento dieciocho. El visor sigue siendo el mismo; lo que cambia es que
    // un markdown se abre **aquí dentro**, con el mismo pintor que usa el chat, en vez
    // de mandarse a un navegador que lo enseñaría en crudo.
    final artifacts = ref.watch(artifactsProvider).value ?? const <Artifact>[];

    return Dialog(
      backgroundColor: colors.rise,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.rule2),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.artifacts,
                style: NexusTypography.label.copyWith(color: colors.accent),
              ),
              const SizedBox(height: NexusSpacing.s2),
              Text(
                folder ?? strings.artifactsExplainer,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
              const SizedBox(height: NexusSpacing.s5),
              Flexible(
                child: folder == null
                    ? Text(
                        strings.artifactsNoFolder,
                        style: NexusTypography.mono.copyWith(
                          color: colors.faint,
                        ),
                      )
                    : artifacts.isEmpty
                    ? Text(
                        strings.artifactsEmpty,
                        style: NexusTypography.mono.copyWith(
                          color: colors.faint,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: artifacts.length,
                        itemBuilder: (context, index) =>
                            _Row(artifact: artifacts[index]),
                      ),
              ),
              const SizedBox(height: NexusSpacing.s5),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final chosen = await getDirectoryPath();
                      if (chosen == null) return;
                      await ref
                          .read(artifactsFolderProvider.notifier)
                          .choose(chosen);
                    },
                    child: Text(
                      folder == null
                          ? strings.artifactsChoose
                          : strings.artifactsChange,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.close),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.artifact});

  final Artifact artifact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return InkWell(
      // La fila entera abre: es lo que se quiere hacer el noventa por ciento de
      // las veces, y obligar a apuntar a un icono de dieciséis píxeles para
      // hacerlo sería cobrar puntería por lo normal.
      // Cada uno donde se lee mejor: lo que el visor del sistema pinta va a su
      // ventana —ahí se puede hacer zoom, imprimir, arrastrar—; un markdown se pinta
      // aquí, porque mandarlo a un `WKWebView` enseñaría las almohadillas.
      onTap: () => Artifact.isViewable(artifact.path)
          ? ref.read(artifactsDataSourceProvider).open(artifact.path)
          : _MarkdownSheet.open(context, artifact),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: Row(
          children: [
            _Preview(path: artifact.path),
            const SizedBox(width: NexusSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artifact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.data.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _when(artifact.at),
                    style: NexusTypography.label.copyWith(color: colors.faint),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () =>
                  ref.read(artifactsDataSourceProvider).reveal(artifact.path),
              icon: Icon(Icons.folder_open, size: 15, color: colors.faint),
              splashRadius: 14,
              tooltip: strings.artifactsReveal,
            ),
            IconButton(
              // A la papelera y no borrado a secas: es un archivo del usuario,
              // y desde el Finder se recupera si fue un error.
              onPressed: () async {
                await SystemFiles.moveToTrash(artifact.path);
                ref.invalidate(artifactsProvider);
              },
              icon: Icon(Icons.delete_outline, size: 15, color: colors.faint),
              splashRadius: 14,
              tooltip: strings.artifactsTrash,
            ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}/'
      '${at.month.toString().padLeft(2, '0')}/${at.year} · '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

/// La miniatura del documento, la misma del Finder.
///
/// Aquí es donde más se nota: cinco mockups seguidos se llaman todos
/// `mockup-algo.html` y lo que los distingue es cómo se ven.
class _Preview extends StatefulWidget {
  const _Preview({required this.path});

  final String path;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  Uint8List? _bytes;

  static const _side = 40.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await SystemThumbnails.of(widget.path, size: _side);
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bytes = _bytes;

    return ClipRRect(
      borderRadius: BorderRadius.circular(NexusRadius.sm - 2),
      child: SizedBox(
        width: _side,
        height: _side,
        child: bytes == null
            ? ColoredBox(color: colors.rule2.withValues(alpha: 0.35))
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }
}

/// Un documento de texto, pintado dentro de la app.
///
/// Con el mismo pintor que el chat y no con el visor del sistema: `WKWebView` no
/// interpreta markdown, así que enseñaría las almohadillas y los guiones. Y con el
/// texto seleccionable, que es la mitad de para qué se abre un informe.
class _MarkdownSheet extends StatelessWidget {
  const _MarkdownSheet({required this.artifact});

  final Artifact artifact;

  static Future<void> open(BuildContext context, Artifact artifact) =>
      showDialog<void>(
        context: context,
        builder: (_) => _MarkdownSheet(artifact: artifact),
      );

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
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                artifact.name,
                style: NexusTypography.label.copyWith(color: colors.accent),
              ),
              const SizedBox(height: NexusSpacing.s4),
              Expanded(
                child: FutureBuilder<String>(
                  future: File(artifact.path).readAsString(),
                  builder: (context, estado) {
                    if (estado.hasError) {
                      return Text(
                        'No se pudo leer.',
                        style: NexusTypography.data.copyWith(
                          color: colors.mute,
                        ),
                      );
                    }
                    if (!estado.hasData) return const SizedBox.shrink();
                    return Markdown(
                      data: estado.data!,
                      selectable: true,
                      padding: EdgeInsets.zero,
                      styleSheet: MarkdownStyleSheet(
                        p: NexusTypography.body.copyWith(color: colors.ink),
                        code: NexusTypography.mono.copyWith(
                          color: colors.accent,
                        ),
                        h1: NexusTypography.title.copyWith(color: colors.ink),
                        h2: NexusTypography.lead.copyWith(color: colors.ink),
                        h3: NexusTypography.body.copyWith(color: colors.mute),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

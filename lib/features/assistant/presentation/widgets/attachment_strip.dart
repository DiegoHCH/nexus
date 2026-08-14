import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/platform/system_thumbnails.dart';
import 'package:nexus/features/assistant/domain/usecases/attached_files.dart';

/// Lo que va a acompañar a lo que estás escribiendo, con su miniatura.
///
/// La miniatura no es adorno: al soltar tres capturas de pantalla seguidas, sus
/// nombres son `Captura 2026-08-13 a las 10.24.31`, `…10.24.48` y `…10.25.02`,
/// y ahí la única forma de saber cuál es cuál es verla. Por eso se pide la del
/// sistema —la misma del Finder— en vez de dibujar un icono por extensión, que
/// dejaría las tres idénticas.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.paths, this.onRemove});

  final List<String> paths;

  /// `null` para **solo mirar**: es como la usa la conversación, donde el
  /// adjunto ya se mandó y quitarlo no significaría nada. En la caja de
  /// escribir sí se puede quitar, porque el mensaje aún no ha salido.
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
      child: Wrap(
        spacing: NexusSpacing.s3,
        runSpacing: NexusSpacing.s3,
        children: [
          for (final path in paths)
            _Attachment(
              key: ValueKey(path),
              path: path,
              onRemove: onRemove == null ? null : () => onRemove!(path),
            ),
        ],
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({super.key, required this.path, this.onRemove});

  final String path;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      // La ruta completa a la vista, pero solo si se pregunta: dos archivos con
      // el mismo nombre en carpetas distintas se distinguen aquí.
      message: path,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, NexusSpacing.s3, 4),
        decoration: BoxDecoration(
          color: colors.deep,
          border: Border.all(color: colors.rule),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Thumbnail(path: path),
            const SizedBox(width: NexusSpacing.s3),
            ConstrainedBox(
              // Un límite, porque los hay larguísimos: se recorta por el final
              // y la ruta entera sigue estando en el tooltip.
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                AttachedFiles.name(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.data.copyWith(color: colors.ink),
              ),
            ),
            if (onRemove case final quitar?) ...[
              const SizedBox(width: NexusSpacing.s2),
              InkWell(
                onTap: quitar,
                borderRadius: BorderRadius.circular(NexusRadius.sm),
                child: Icon(Icons.close, size: 13, color: colors.faint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Se pide una vez por archivo y se guarda mientras el chip viva.
///
/// Es un `StatefulWidget` y no un provider porque la miniatura no es estado de
/// la app: nace y muere con el chip, y guardarla en un provider global la
/// dejaría en memoria mucho después de haber enviado el mensaje.
class _Thumbnail extends StatefulWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  Uint8List? _bytes;

  static const _side = 34.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await SystemThumbnails.of(widget.path, size: _side);
    // Puede volver con el chip ya quitado: se soltó un archivo y se descartó
    // antes de que QuickLook contestara.
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(NexusRadius.sm - 2),
      child: SizedBox(
        width: _side,
        height: _side,
        child: _bytes == null
            // Mientras llega, el hueco en gris y no un giro de carga: la
            // miniatura tarda decenas de milisegundos y un indicador que
            // aparece y desaparece se lee como un error.
            ? ColoredBox(color: colors.rule2.withValues(alpha: 0.35))
            : Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }
}

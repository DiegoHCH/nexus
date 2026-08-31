import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';

/// Dónde se pone la llave con la que se generarán las imágenes.
///
/// Vive aquí y no con la de voz porque **son dos llaves de proyectos
/// distintos**: la de voz se sostiene con la capa gratuita y ésta no puede —el
/// modelo de imágenes no está en el nivel gratuito—, así que su proyecto
/// necesita facturación. Juntarlas haría que encender las imágenes empezara a
/// cobrar las conversaciones, que hoy salen gratis.
///
/// 🔴 **La sección se adelanta a lo que hace la app**, y por eso lo dice: hoy
/// nada consume esta llave. Guardarla no genera ni cobra nada. Es preferible
/// eso a un campo que aparezca de la nada el día que entre la generación —y
/// mucho preferible a callarlo y que alguien la pegue esperando que pase algo.
class ImagenesSection extends ConsumerStatefulWidget {
  const ImagenesSection({super.key});

  @override
  ConsumerState<ImagenesSection> createState() => _ImagenesSectionState();
}

class _ImagenesSectionState extends ConsumerState<ImagenesSection> {
  final _controller = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final llave = _controller.text.trim();
    if (llave.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    await ref.read(geminiImageKeyStoreProvider).save(llave);
    if (!mounted) return;
    _controller.clear();
    setState(() => _guardando = false);
    // Para que la sección de Llaves la vea sin reiniciar: lee del llavero por
    // su cuenta.
    ref.invalidate(geminiImageKeyStoreProvider);
    ref.invalidate(hayLlaveDeImagenesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final hay = ref.watch(hayLlaveDeImagenesProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.imagesExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Text(
          strings.imageKeyLabel,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          hay ? strings.geminiKeySaved : strings.geminiKeyMissing,
          style: NexusTypography.mono.copyWith(
            color: hay ? colors.ok : colors.warn,
          ),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: true,
                onSubmitted: (_) => _guardar(),
                style: NexusTypography.mono.copyWith(color: colors.ink),
                decoration: InputDecoration(hintText: strings.geminiKeyHint),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: _guardando ? null : _guardar,
              child: Text(strings.geminiKeySave),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s5),
        Text(
          strings.imagesNotWiredYet,
          style: NexusTypography.mono.copyWith(color: colors.warn),
        ),
      ],
    );
  }
}

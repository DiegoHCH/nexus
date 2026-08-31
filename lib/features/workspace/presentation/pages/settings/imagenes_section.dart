import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/artifacts/domain/entities/modelo_de_imagen.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/settings_chooser.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/las_llaves_guardadas.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Dónde se ponen las llaves con las que se generan las imágenes.
///
/// **Una por cuenta de Claude, no una para todo.** Cada carpeta emparejada dice
/// con qué cuenta trabaja, y el gasto de las imágenes sale de un bolsillo
/// concreto: con una sola llave global, trabajar en una carpeta del trabajo
/// gastaría del saldo personal sin que se viera. Poner la llave solo en una
/// cuenta es la forma de decir «desde las demás no se generan imágenes», y
/// hasta ahora no había forma de decirlo.
///
/// Y aparte de la de voz porque el proyecto de imágenes necesita facturación
/// —su modelo no está en el nivel gratuito— mientras que el de voz no.
class ImagenesSection extends ConsumerWidget {
  const ImagenesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final cuentas = cuentasParaLlaves(
      ref.watch(claudeProfilesProvider).value ?? const [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.imagesExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        // Cuál dibuja, antes que las llaves: es lo que decide cuánto cuesta
        // cada imagen, y con el doble de diferencia entre el más caro y el más
        // barato conviene verlo al elegir y no en la factura.
        Text(
          strings.whichImageModel,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        SettingsChooser<ModeloDeImagen>(
          value: ref.watch(modeloDeImagenProvider),
          options: ModeloDeImagen.values,
          label: (modelo) => modelo.nombre,
          detail: (modelo) => strings.perImage(modelo.precio),
          onSelected: ref.read(modeloDeImagenProvider.notifier).elegir,
        ),
        const SizedBox(height: NexusSpacing.s6),
        for (final cuenta in cuentas) _LaDeUnaCuenta(perfil: cuenta),
        const SizedBox(height: NexusSpacing.s3),
        Text(
          strings.imagesNotWiredYet,
          style: NexusTypography.mono.copyWith(color: colors.warn),
        ),
      ],
    );
  }
}

class _LaDeUnaCuenta extends ConsumerStatefulWidget {
  const _LaDeUnaCuenta({required this.perfil});

  /// `null` es la cuenta de siempre, la que no tiene nombre.
  final String? perfil;

  @override
  ConsumerState<_LaDeUnaCuenta> createState() => _LaDeUnaCuentaState();
}

class _LaDeUnaCuentaState extends ConsumerState<_LaDeUnaCuenta> {
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
    await ref.read(geminiImageKeyStoreProvider).save(widget.perfil, llave);
    if (!mounted) return;
    _controller.clear();
    setState(() => _guardando = false);
    _refrescar();
  }

  Future<void> _olvidar() async {
    await ref.read(geminiImageKeyStoreProvider).clear(widget.perfil);
    if (!mounted) return;
    _refrescar();
  }

  /// Las dos pantallas que preguntan por esta llave leen del llavero por su
  /// cuenta, así que hay que decírselo a las dos.
  void _refrescar() {
    ref.invalidate(hayLlaveDeImagenesProvider(widget.perfil));
    ref.invalidate(lasLlavesGuardadasProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final hay =
        ref.watch(hayLlaveDeImagenesProvider(widget.perfil)).value ?? false;
    final cuenta = widget.perfil ?? strings.defaultAccount;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cuenta.toUpperCase(),
                  style: NexusTypography.label.copyWith(color: colors.faint),
                ),
              ),
              Text(
                hay ? strings.keyIsSaved : strings.keyIsMissing,
                style: NexusTypography.data.copyWith(
                  color: hay ? colors.ok : colors.faint,
                ),
              ),
              // Olvidar solo lo que está puesto. Uno que a veces no hace nada
              // enseña a no pulsarlo, y entonces tampoco se pulsa el día que sí.
              if (hay)
                Padding(
                  padding: const EdgeInsets.only(left: NexusSpacing.s3),
                  child: TextButton(
                    onPressed: _olvidar,
                    style: TextButton.styleFrom(foregroundColor: colors.err),
                    child: Text(
                      strings.keyForget,
                      style: NexusTypography.label.copyWith(color: colors.err),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexusSpacing.s2),
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
        ],
      ),
    );
  }
}

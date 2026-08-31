import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/presentation/providers/las_llaves_guardadas.dart';

/// Qué secretos tiene Nexus guardados, y cómo quitarlos.
///
/// Antes no existía: para saber qué había guardado tocaba abrir Acceso a
/// Llaveros y buscar por el nombre interno de la clave, y **quitar una era
/// borrarla desde ahí a mano** — pedirle a alguien que hurgue en el llavero de
/// su Mac para deshacer algo que hizo desde una pantalla de Ajustes.
///
/// 🔴 **No se enseña ninguna, ni recortada.** Lo único que dice cada fila es si
/// está puesta. Una cola de cuatro caracteres ayudaría a distinguir cuál es,
/// pero pone un trozo de secreto en pantalla —y en cualquier captura, y en
/// cualquier pantalla compartida— a cambio de poco: para comprobar si es la que
/// crees, la quitas y pones la buena.
class LlavesSection extends ConsumerWidget {
  const LlavesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final guardadas = ref.watch(lasLlavesGuardadasProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.keysExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        for (final llave in LlaveDeNexus.values)
          _Fila(
            llave: llave,
            // Mientras se lee el llavero no se dice «sin poner»: sería una
            // respuesta falsa a la única pregunta que contesta la pantalla.
            hay: guardadas?[llave],
          ),
      ],
    );
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.llave, required this.hay});

  final LlaveDeNexus llave;
  final bool? hay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final nombre = _nombre(llave, strings);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: NexusSpacing.s3),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hay ?? false ? colors.ok : colors.rule2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              nombre,
              style: NexusTypography.body.copyWith(color: colors.ink),
            ),
          ),
          Text(
            hay == null
                ? '…'
                : (hay! ? strings.keyIsSaved : strings.keyIsMissing),
            style: NexusTypography.data.copyWith(color: colors.faint),
          ),
          // El botón solo si hay algo que quitar. Uno que a veces no hace nada
          // enseña a no pulsarlo, y entonces tampoco se pulsa el día que sí.
          if (hay ?? false)
            Padding(
              padding: const EdgeInsets.only(left: NexusSpacing.s4),
              child: TextButton(
                onPressed: () => _confirmar(context, ref, nombre),
                style: TextButton.styleFrom(foregroundColor: colors.err),
                child: Text(
                  strings.keyForget,
                  style: NexusTypography.label.copyWith(color: colors.err),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Se pregunta antes, y no por ceremonia: **borrar un secreto no se deshace**
  /// y el que se va puede ser el que sostiene el canal con un teléfono que no
  /// está delante.
  Future<void> _confirmar(
    BuildContext context,
    WidgetRef ref,
    String nombre,
  ) async {
    final strings = context.strings;
    final colors = context.colors;

    final seguro = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: colors.rise,
        title: Text(
          strings.keyForgetAsk(nombre),
          style: NexusTypography.body.copyWith(color: colors.ink),
        ),
        content: Text(
          strings.keyForgetWarning,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            style: TextButton.styleFrom(foregroundColor: colors.err),
            child: Text(strings.keyForget),
          ),
        ],
      ),
    );

    if (seguro != true) return;
    await ref.read(olvidarUnaLlaveProvider)(llave);
  }

  static String _nombre(LlaveDeNexus llave, NexusStrings strings) =>
      switch (llave) {
        LlaveDeNexus.voz => strings.keyVoice,
        LlaveDeNexus.imagenes => strings.keyImages,
        LlaveDeNexus.tokenDelCanal => strings.keyChannelToken,
        LlaveDeNexus.fraseDeEscritura => strings.keyWritePhrase,
        LlaveDeNexus.emparejamiento => strings.keyPairing,
      };
}

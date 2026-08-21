import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';

/// Un turno de la conversación: quién habló y qué dijo.
///
/// **No es una burbuja, y esa es la diferencia de fondo con lo que había.** La
/// primera versión de esta pantalla usaba `Container` redondeados alineados a un lado
/// y a otro, que es la convención de una app de mensajería — y esta no lo es. Lo
/// dibujado es una pila de bloques separados por **hairlines**, cada uno con una
/// etiqueta pequeña arriba y el texto debajo en peso ligero.
///
/// La diferencia no es estética: una burbuja dice «dos personas charlando» y un bloque
/// con hairline dice «un registro de lo que pasó». Lo segundo es lo que esto es — el
/// teléfono no ejecuta nada, refleja.
///
/// La etiqueta de Nexus va **en acento** y la tuya no, así que quién habla se lee sin
/// leer: es lo único que cambia de color en toda la pila.
class TurnBlock extends StatelessWidget {
  const TurnBlock({
    super.key,
    required this.mine,
    required this.text,
    this.chip,
  });

  final bool mine;
  final String text;

  /// Un estado del turno: «Interrumpido» cuando la respuesta se cortó, «Esperando»
  /// cuando el encargo todavía no salió del teléfono.
  final String? chip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s4),
      decoration: BoxDecoration(
        // La hairline arriba y no abajo: así el primer bloque de la pila abre con una
        // línea y el último no cierra con una suelta.
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mine ? 'TÚ' : 'NEXUS',
            style: NexusTypography.label.copyWith(
              color: mine ? colors.faint : colors.accent,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text,
            style: NexusTypography.subtitleMobile.copyWith(
              // Lo tuyo en tinta y lo de Nexus más apagado: lo que pediste es el
              // ancla de la lectura y su respuesta es lo que se recorre.
              color: mine ? colors.ink : colors.mute,
            ),
          ),
          if (chip != null) ...[
            const SizedBox(height: NexusSpacing.s3),
            StateChip(texto: chip!),
          ],
        ],
      ),
    );
  }
}

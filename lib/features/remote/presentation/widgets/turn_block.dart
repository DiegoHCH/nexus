import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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
          // **Lo tuyo tal cual; lo de Nexus, interpretado.**
          //
          // Es la misma regla que el escritorio, y aquí faltaba: la respuesta llegaba
          // en markdown y se pintaba en crudo, así que se leían los `**`, las `##` y
          // una tabla salía como una parrilla de tuberías. Un asterisco que escribiste
          // tú sigue siendo un asterisco — interpretar lo tuyo cambiaría lo que
          // pediste.
          //
          // Con el mismo pintor que el chat del Mac, para que no haya dos ideas de qué
          // es una tabla.
          if (mine)
            SelectableText(
              text,
              // En tinta: lo que pediste es el ancla de la lectura.
              style: NexusTypography.subtitleMobile.copyWith(color: colors.ink),
            )
          else
            MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: NexusTypography.body.copyWith(color: colors.mute),
                h1: NexusTypography.subtitleMobile.copyWith(color: colors.ink),
                h2: NexusTypography.lead.copyWith(color: colors.ink),
                h3: NexusTypography.body.copyWith(color: colors.ink),
                strong: NexusTypography.body.copyWith(color: colors.ink),
                em: NexusTypography.body.copyWith(
                  color: colors.mute,
                  fontStyle: FontStyle.italic,
                ),
                code: NexusTypography.mono.copyWith(color: colors.accent),
                codeblockDecoration: BoxDecoration(
                  color: colors.rise,
                  border: Border.all(color: colors.rule),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colors.rule2, width: 2),
                  ),
                ),
                tableBorder: TableBorder.all(color: colors.rule),
                tableHead: NexusTypography.label.copyWith(color: colors.ink),
                tableBody: NexusTypography.mono.copyWith(color: colors.mute),
                listBullet: NexusTypography.body.copyWith(color: colors.faint),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.rule)),
                ),
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

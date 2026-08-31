import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';

/// El selector de opciones excluyentes de Ajustes.
///
/// Aparte porque lo comparten tres secciones —tema, idioma y voz— y era la única
/// pieza de `settings_page.dart` con más de un dueño.

/// El desplegable de Ajustes.
///
/// Lo comparten la voz y el idioma para que no acaben pareciéndose solo un
/// rato: son la misma pregunta —elige uno de esta lista— y separarlos en dos
/// widgets fue exactamente lo que hizo que uno tuviera 30 opciones en una
/// columna interminable y el otro tres.
class SettingsChooser<T> extends StatelessWidget {
  const SettingsChooser({
    super.key,
    required this.value,
    required this.options,
    required this.label,
    required this.onSelected,
    this.detail,
  });

  final T value;
  final List<T> options;

  /// Lo que se lee en la fila. Se pide como función y no como texto ya hecho
  /// porque las opciones vienen del dominio —una voz, un idioma— y traducirlas
  /// es cosa de la pantalla.
  final String Function(T option) label;

  /// La coletilla en gris: el carácter de una voz, por ejemplo. Opcional
  /// porque el idioma no tiene nada que añadir.
  final String Function(T option)? detail;

  final void Function(T option) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s4),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          // El desplegado hereda el fondo claro de Material si no se le dice
          // lo contrario, y en esta app eso es un fogonazo blanco.
          dropdownColor: colors.deep,
          // Sin esto, el botón se queda pintado de cian después de elegir: es
          // el resaltado de foco de Material, que en un control tan ancho se
          // lee como «esto sigue seleccionado» en vez de «esto tiene el foco».
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(NexusRadius.sm),
          icon: Icon(Icons.expand_more, size: 16, color: colors.faint),
          style: NexusTypography.data.copyWith(color: colors.ink),
          onChanged: (option) {
            if (option != null) onSelected(option);
          },
          items: [
            for (final option in options)
              DropdownMenuItem<T>(
                value: option,
                // 🔴 **Los dos textos ceñidos, y el nombre antes que la
                // coletilla.** Iban sueltos en la fila, así que cabían de
                // casualidad: con las opciones que había —una voz, un idioma—
                // nunca se pasaban, y con «Nano Banana 2 Lite» y su precio
                // detrás desbordó 192 px en la columna de Ajustes.
                //
                // Si hay que recortar algo se recorta la coletilla, que es el
                // dato de apoyo; el nombre es lo que se está eligiendo y sin
                // él la fila no dice nada.
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label(option),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NexusTypography.data.copyWith(color: colors.ink),
                      ),
                    ),
                    if (detail case final describe?) ...[
                      const SizedBox(width: NexusSpacing.s3),
                      Flexible(
                        child: Text(
                          describe(option),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NexusTypography.mono.copyWith(
                            color: colors.faint,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

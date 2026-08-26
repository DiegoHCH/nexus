import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';

/// Un desplegable para los paneles del compositor.
///
/// **Aparte de `SettingsChooser` y no una copia suya**: ese es de Ajustes, con su
/// alto y su tipografía de formulario. Aquí manda el sitio — un panel de 620 px
/// sobre la barra— y lo que se elige es un identificador, no una preferencia.
///
/// El relleno horizontal es `s2` y no `s3`, y eso no es estética: con el mayor,
/// un `DropdownButton` con `isExpanded` desborda su propia fila por 0,9 px al
/// abrir el menú —una rareza de la medida interna de Material— y pinta la franja
/// amarilla de aviso encima de la barra.
class SelectorCompacto extends StatelessWidget {
  const SelectorCompacto({
    super.key,
    required this.valor,
    required this.opciones,
    required this.pista,
    required this.onElegir,
  });

  final String? valor;
  final List<String> opciones;
  final String pista;
  final void Function(String) onElegir;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s2),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isExpanded: true,
          isDense: true,
          dropdownColor: colors.deep,
          focusColor: Colors.transparent,
          hint: Text(
            pista,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          icon: Icon(Icons.expand_more, size: 14, color: colors.faint),
          items: [
            for (final opcion in opciones)
              DropdownMenuItem(
                value: opcion,
                child: Text(
                  opcion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onElegir(v);
          },
        ),
      ),
    );
  }
}

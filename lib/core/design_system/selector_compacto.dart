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
    this.etiqueta,
    this.cargando = false,
  });

  final String? valor;
  final List<String> opciones;
  final String pista;
  final void Function(String) onElegir;

  /// Lo que se lee de cada opción, cuando no es la opción misma.
  ///
  /// **Hace falta porque lo que se elige no siempre se puede leer.** Un
  /// dispositivo se elige por su id —`emulator-5554`, `00008030-000C390C1AC0C02E`—
  /// y eso no dice cuál es cuál; el nombre sí. Se separan el valor y su etiqueta
  /// en vez de enseñar el id, que fue el primer intento y no servía para elegir.
  final String Function(String opcion)? etiqueta;

  /// Todavía no se sabe qué opciones hay.
  ///
  /// **No es lo mismo que no tener ninguna**, y esa diferencia era un fallo:
  /// un desplegable sin opciones se queda inerte —lo apaga Flutter solo— y al
  /// pulsarlo no pasa nada, que desde fuera se lee como una interfaz colgada.
  /// Cargando se dice: la rueda en vez del galón, y la pista lo cuenta.
  final bool cargando;

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
          // Lo mismo en el valor puesto: `DropdownButton` pinta el hijo del item
          // elegido, así que la etiqueta llega sola por el `items` de arriba.
          hint: Text(
            pista,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          icon: cargando
              ? SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: colors.faint,
                  ),
                )
              : Icon(Icons.expand_more, size: 14, color: colors.faint),
          items: [
            for (final opcion in opciones)
              DropdownMenuItem(
                value: opcion,
                child: Text(
                  etiqueta?.call(opcion) ?? opcion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
          ],
          // Apagado mientras busca, y a sabiendas: sin opciones el desplegable
          // se apaga igual, pero así lo dice la rueda en vez de no decir nada.
          onChanged: cargando
              ? null
              : (v) {
                  if (v != null) onElegir(v);
                },
        ),
      ),
    );
  }
}

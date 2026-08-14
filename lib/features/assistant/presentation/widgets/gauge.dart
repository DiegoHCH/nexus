import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';

/// Una barra con su nombre, su cifra y, si hace falta, una nota debajo.
///
/// Vive en su propio archivo y **no privada dentro del compositor** para poder
/// probarla dibujada, como `ActivityHeatmap` y `ModelsChart`: el fallo que se
/// coló aquí —el valor empujando la fila 192 px fuera del panel— no lo ve el
/// análisis ni una prueba de reglas, solo una que la pinte en el ancho de
/// verdad.
class Gauge extends StatelessWidget {
  const Gauge({
    super.key,
    required this.label,
    required this.percent,
    this.value,
    this.note,
    this.warnAt = 90,
  });

  final String label;
  final int percent;

  /// Lo que se escribe a la derecha. Sin él va el porcentaje solo, que es lo
  /// que basta para una cuota; el contexto necesita las tres cifras.
  final String? value;

  final String? note;
  final int warnAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // **Cada dato en su fila**: el nombre entero, la cifra debajo, y la
        // barra al final. Compartiendo línea no cabían: en un panel de 300 px
        // con tipografía mono, «Ventana de contexto» y «31,1k / 200,0k (16 %)»
        // se recortaban **los dos** —quedaba «Ventana de con… 31,1k / 200,0k
        // (…»—, y un medidor que no deja leer ni su nombre ni su número no mide
        // nada. Apilarlos cuesta una línea de alto y los enseña completos.
        //
        // Cuándo se renueva sigue debajo del todo, por lo mismo de siempre: es
        // secundario, y apretado arriba ya desbordó una vez cuando el plazo
        // pasó de horas a días («129 h 27 m»).
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.mono.copyWith(color: colors.mute),
        ),
        const SizedBox(height: 2),
        Text(
          value ?? '$percent %',
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.data.copyWith(color: colors.faint),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 3,
            backgroundColor: colors.rule,
            color: percent >= warnAt ? colors.warn : colors.cyan,
          ),
        ),
        if (note case final texto?) ...[
          const SizedBox(height: 3),
          Text(
            texto,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ],
      ],
    );
  }
}

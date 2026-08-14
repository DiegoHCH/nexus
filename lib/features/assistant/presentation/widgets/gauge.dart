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
        // Encima de la barra solo el nombre y el número: son los dos datos que
        // se leen de un vistazo y caben siempre. Cuándo se renueva va **debajo**
        // — es un dato secundario y, apretado en la misma línea, desbordaba el
        // panel en cuanto el plazo pasaba de las horas a los días («129 h 27 m»).
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.mono.copyWith(color: colors.mute),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            // Flexible y con puntos suspensivos, como la etiqueta. Suelto, el
            // valor empujaba la fila fuera del panel —192 px con la frase de
            // «sin sesión» dentro— y un desbordamiento de Flutter tapa
            // justamente lo que venía a decir. Que se corte es feo; que se
            // pinte encima de la línea siguiente en rojo, peor.
            Flexible(
              child: Text(
                value ?? '$percent %',
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.data.copyWith(color: colors.faint),
              ),
            ),
          ],
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

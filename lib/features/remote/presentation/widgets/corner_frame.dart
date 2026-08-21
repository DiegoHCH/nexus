import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';

/// El marco de cuatro esquinas del visor.
///
/// **Solo las esquinas y no un cuadrado**, que es lo que dibuja el mockup y no es un
/// detalle: un borde cerrado se lee como un marco de imagen y tapa el código por los
/// lados; cuatro escuadras dicen «pon el código aquí dentro» sin cubrir nada. Es la
/// convención de todos los escáneres, y funciona porque el ojo completa el rectángulo.
class CornerFrame extends StatelessWidget {
  const CornerFrame({
    super.key,
    this.lado = 220,
    this.largo = 26,
    this.grosor = 2,
  });

  /// El lado del hueco. 220 sobre una pantalla de 390 deja el código grande y con
  /// aire: más pequeño obliga a acercar el teléfono hasta que la cámara no enfoca.
  final double lado;

  /// Cuánto mide cada escuadra.
  final double largo;
  final double grosor;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.accent;

    return SizedBox(
      width: lado,
      height: lado,
      child: Stack(
        children: [
          for (final (arriba, izquierda) in const [
            (true, true),
            (true, false),
            (false, true),
            (false, false),
          ])
            Align(
              alignment: Alignment(izquierda ? -1 : 1, arriba ? -1 : 1),
              child: CustomPaint(
                size: Size(largo, largo),
                painter: _Escuadra(
                  color: color,
                  arriba: arriba,
                  izquierda: izquierda,
                  grosor: grosor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Escuadra extends CustomPainter {
  const _Escuadra({
    required this.color,
    required this.arriba,
    required this.izquierda,
    required this.grosor,
  });

  final Color color;
  final bool arriba;
  final bool izquierda;
  final double grosor;

  @override
  void paint(Canvas lienzo, Size medida) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = grosor
      // Cuadrado y no redondeado: el sistema de esta app es de esquinas casi rectas,
      // y una punta redonda aquí se ve prestada de otra parte.
      ..strokeCap = StrokeCap.square;

    final x = izquierda ? 0.0 : medida.width;
    final y = arriba ? 0.0 : medida.height;
    final hastaX = izquierda ? medida.width : 0.0;
    final hastaY = arriba ? medida.height : 0.0;

    lienzo
      ..drawLine(Offset(x, y), Offset(hastaX, y), pincel)
      ..drawLine(Offset(x, y), Offset(x, hastaY), pincel);
  }

  @override
  bool shouldRepaint(_Escuadra otra) =>
      otra.color != color || otra.grosor != grosor;
}

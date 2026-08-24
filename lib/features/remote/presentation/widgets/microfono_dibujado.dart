import 'package:flutter/widgets.dart';

/// El micrófono, dibujado.
///
/// **No es un icono de Material y no es un glifo.** Los iconos de Material traen su
/// propio idioma —lo dice la guarda de la pieza 6— y de glifo no hay ninguno que sea un
/// micrófono: `●` había que aprenderlo, y un emoji habría metido en la fila la
/// tipografía de otro. Así que se traza con el mismo vocabulario que el resto del HUD,
/// que es el que ya usa el orbe: hairline, sin relleno salvo cuando algo está pasando,
/// y las proporciones fijadas en una rejilla de 24 para que no dependan del tamaño.
///
/// Los tres estados de la voz se leen **por la forma**, no por el color: contorno
/// —quieto—, relleno —hablando— y tachado —no va a abrir—. El color separa después las
/// dos causas de que no vaya a abrir, pero un usuario que no distinga esos dos tonos
/// sigue viendo que está tachado.
class MicrofonoDibujado extends StatelessWidget {
  const MicrofonoDibujado({
    super.key,
    required this.color,
    required this.size,
    this.relleno = false,
    this.tachado = false,
  });

  final Color color;
  final double size;

  /// La cápsula va rellena mientras entra voz: es lo que dice «ahora mismo».
  final bool relleno;

  /// Tachado cuando no se va a poder abrir, por permiso o porque no hay Mac.
  final bool tachado;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _Trazo(color: color, relleno: relleno, tachado: tachado),
    ),
  );
}

class _Trazo extends CustomPainter {
  const _Trazo({
    required this.color,
    required this.relleno,
    required this.tachado,
  });

  final Color color;
  final bool relleno;
  final bool tachado;

  @override
  void paint(Canvas canvas, Size size) {
    // Rejilla de 24: las medidas se escriben una vez y valen a cualquier tamaño.
    final k = size.width / 24;
    final trazo = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // El grosor escala con el icono, pero con un suelo: por debajo de medio píxel el
      // trazo se difumina hasta desaparecer, y un micrófono medio borrado se lee como
      // un fallo de pintado.
      ..strokeWidth = (1.4 * k).clamp(0.8, 2.0)
      ..strokeCap = StrokeCap.round;

    // La cápsula.
    final capsula = RRect.fromRectAndRadius(
      Rect.fromLTRB(9.5 * k, 3 * k, 14.5 * k, 13.5 * k),
      Radius.circular(2.5 * k),
    );
    canvas.drawRRect(capsula, relleno ? (Paint()..color = color) : trazo);

    // La horquilla: media circunferencia por debajo de la cápsula. Va desde el lado
    // izquierdo hasta el derecho pasando por abajo, que es lo que hace que se lea como
    // un soporte y no como un aro.
    canvas.drawArc(
      Rect.fromLTRB(6.5 * k, 8 * k, 17.5 * k, 18 * k),
      0,
      3.14159,
      false,
      trazo,
    );

    // El pie: un tallo corto y la base.
    canvas.drawLine(Offset(12 * k, 18 * k), Offset(12 * k, 21 * k), trazo);
    canvas.drawLine(Offset(8.5 * k, 21 * k), Offset(15.5 * k, 21 * k), trazo);

    if (!tachado) return;
    // La barra va de esquina a esquina y **por encima de todo**, no interrumpida por la
    // silueta: una tachadura que respeta el dibujo se lee como parte del dibujo.
    canvas.drawLine(Offset(4 * k, 20.5 * k), Offset(20 * k, 3.5 * k), trazo);
  }

  @override
  bool shouldRepaint(_Trazo anterior) =>
      anterior.color != color ||
      anterior.relleno != relleno ||
      anterior.tachado != tachado;
}

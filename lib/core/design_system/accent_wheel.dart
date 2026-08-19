import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accent_preference.dart';
import 'nexus_radius.dart';
import 'nexus_spacing.dart';
import 'nexus_colors.dart';

/// La rueda de color: matiz por el ángulo, saturación por el radio, y el brillo
/// en una barra debajo.
///
/// Es lo que se pidió en vez de una lista cerrada, y tiene sentido: el acento es
/// identidad, y una identidad no se elige de un menú de seis.
///
/// **Lo que la rueda no decide es el brillo final.** Aquí se elige el color; el
/// tono con el que se pinta en cada tema lo ajusta [Accent.forBrightness] para que
/// cumpla contraste sobre los tres fondos. Sin eso, media rueda —todo lo oscuro—
/// dejaría la app ilegible en oscuro, y la otra media en claro. Se dice en la
/// propia pantalla, que es donde importa saberlo.
class AccentWheel extends StatelessWidget {
  const AccentWheel({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onSettled,
    this.size = 220,
  });

  /// El color elegido ahora mismo, tal cual se eligió.
  final Color value;

  /// Se llama en cada arrastre: el color se ve cambiar mientras se mueve el dedo,
  /// que es la mitad de por qué una rueda es mejor que una lista.
  final ValueChanged<Color> onChanged;

  /// Se llama **al soltar**, y es el que confirma.
  ///
  /// Existen los dos porque cada acento confirmado arma un `ThemeData` entero y lo
  /// guarda: confirmar en cada movimiento dejaría cientos de temas en memoria por
  /// un solo gesto. Así el arrastre se ve y solo el resultado se guarda.
  final ValueChanged<Color> onSettled;

  final double size;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Disco(size: size, hsv: hsv, onChanged: onChanged, onSettled: onSettled),
        const SizedBox(height: NexusSpacing.s5),
        SizedBox(
          width: size,
          child: _BarraDeBrillo(
            hsv: hsv,
            onChanged: onChanged,
            onSettled: onSettled,
          ),
        ),
      ],
    );
  }
}

class _Disco extends StatefulWidget {
  const _Disco({
    required this.size,
    required this.hsv,
    required this.onChanged,
    required this.onSettled,
  });

  final double size;
  final HSVColor hsv;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color> onSettled;

  @override
  State<_Disco> createState() => _DiscoState();
}

class _DiscoState extends State<_Disco> {
  /// El último color que produjo el gesto.
  ///
  /// Existe porque al soltar hay que confirmar **lo que dijo el gesto**, y no lo
  /// que tenga el padre en ese instante: el padre se enteró por `onChanged` y
  /// puede no haberse reconstruido todavía. Confiando en él, un arrastre rápido
  /// confirmaba el color **anterior** — lo encontró una prueba que arrastraba y
  /// veía el acento sin cambiar, y a ojo habría pasado por «a veces no coge bien».
  Color? _ultimo;

  /// Del punto tocado al color: el ángulo es el matiz, la distancia al centro la
  /// saturación.
  Color _colorEn(Offset local) {
    final radio = widget.size / 2;
    final v = local - Offset(radio, radio);
    // `atan2` da −π…π con el cero a la derecha; se pasa a 0…360 girando para que
    // el rojo caiga arriba, como en cualquier rueda de color.
    final angulo = (math.atan2(v.dy, v.dx) * 180 / math.pi + 450) % 360;
    // Recortado a 1 y no ignorado fuera del disco: al arrastrar, el dedo se sale
    // constantemente, y perder el gesto ahí hace que la rueda se sienta rota.
    final saturacion = (v.distance / radio).clamp(0.0, 1.0);
    return HSVColor.fromAHSV(1, angulo, saturacion, widget.hsv.value).toColor();
  }

  void _mover(Offset local) {
    final color = _colorEn(local);
    _ultimo = color;
    widget.onChanged(color);
  }

  void _soltar() {
    final color = _ultimo;
    _ultimo = null;
    if (color != null) widget.onSettled(color);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    // `opaque` y no el `deferToChild` por defecto: un `CustomPaint` **sin hijo no
    // absorbe pulsaciones** —su `hitTestSelf` es falso— así que delegando en él no
    // llegaba ni un toque y la rueda estaba muerta. Lo encontró una prueba que
    // arrastraba y no veía ningún cambio; a ojo habría parecido que la rueda se
    // pinta bien y «no hace nada».
    behavior: HitTestBehavior.opaque,
    onPanDown: (d) => _mover(d.localPosition),
    onPanUpdate: (d) => _mover(d.localPosition),
    onPanEnd: (_) => _soltar(),
    onPanCancel: _soltar,
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _DiscoPainter(hsv: widget.hsv),
    ),
  );
}

class _DiscoPainter extends CustomPainter {
  _DiscoPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final radio = size.width / 2;
    final rect = Rect.fromCircle(center: centro, radius: radio);

    // El matiz, dando la vuelta. Se listan los doce vértices y no seis para que
    // la rueda no muestre bandas donde el degradado interpola de lejos.
    canvas.drawCircle(
      centro,
      radio,
      Paint()
        ..shader = SweepGradient(
          // Girado un cuarto para que el rojo quede arriba.
          transform: const GradientRotation(-math.pi / 2),
          colors: [
            for (var i = 0; i <= 12; i++)
              HSVColor.fromAHSV(1, i * 30 % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );

    // La saturación: blanco en el centro que se abre hacia el borde.
    canvas.drawCircle(
      centro,
      radio,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // Y el brillo, como un velo negro encima. Así la rueda enseña la elección
    // completa y no solo dos de sus tres números — bajar el brillo y ver la rueda
    // igual de encendida es de las cosas que hacen dudar de si el control hizo
    // algo.
    if (hsv.value < 1) {
      canvas.drawCircle(
        centro,
        radio,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }

    // Donde está lo elegido: un aro, no un punto relleno. Un punto tapa el color
    // que hay que juzgar, que es justo el que está debajo.
    final angulo = (hsv.hue - 90) * math.pi / 180;
    final punto =
        centro + Offset(math.cos(angulo), math.sin(angulo)) * radio * hsv.saturation;
    canvas.drawCircle(
      punto,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        // Blanco o negro según lo que haya debajo: un aro blanco sobre un amarillo
        // claro no se ve, y ahí se pierde el único indicio de dónde estás.
        ..color = Accent.luminance(hsv.toColor()) > 0.45
            ? Colors.black
            : Colors.white,
    );
  }

  @override
  bool shouldRepaint(_DiscoPainter old) => old.hsv != hsv;
}

/// El brillo, de negro al color puro.
class _BarraDeBrillo extends StatelessWidget {
  const _BarraDeBrillo({
    required this.hsv,
    required this.onChanged,
    required this.onSettled,
  });

  final HSVColor hsv;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color> onSettled;

  @override
  Widget build(BuildContext context) {
    final puro = HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor();
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 10,
        // Sin marcas ni valor flotando: el valor de esta barra **es el color que
        // se ve**, y un «0,62» encima solo añade un número que nadie usa.
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        overlayShape: SliderComponentShape.noOverlay,
        // El riel lo pinta el degradado de abajo; el del propio Slider se apaga
        // para que no se vea una banda encima.
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
        thumbColor: hsv.toColor(),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NexusRadius.sm),
              gradient: LinearGradient(colors: [Colors.black, puro]),
            ),
          ),
          Slider(
            value: hsv.value,
            onChanged: (v) =>
                onChanged(HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, v).toColor()),
            onChangeEnd: (v) =>
                onSettled(HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, v).toColor()),
          ),
        ],
      ),
    );
  }
}

/// Cómo se verá el color en los dos temas, uno al lado del otro.
///
/// Existe porque el ajuste de brillo es invisible y podría parecer que la app
/// ignora la elección: aquí se ve que en claro el tono baja y en oscuro sube, y
/// que los dos son el mismo color. Sin esto, elegir un violeta muy oscuro y verlo
/// aparecer claro en el orbe se leería como un fallo.
class AccentPreview extends StatelessWidget {
  const AccentPreview({super.key, required this.accent});

  final Accent accent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final brillo in [Brightness.dark, Brightness.light])
        Padding(
          padding: const EdgeInsets.only(right: NexusSpacing.s3),
          child: _Muestra(
            // El vacío de cada tema, que es el fondo real de la app.
            fondo: (brillo == Brightness.dark
                    ? NexusColors.dark
                    : NexusColors.light)
                .void_,
            color: accent.forBrightness(brillo),
          ),
        ),
    ],
  );
}

class _Muestra extends StatelessWidget {
  const _Muestra({required this.fondo, required this.color});

  final Color fondo;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 30,
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(NexusRadius.sm),
    ),
    alignment: Alignment.center,
    // Un aro y un punto: lo mismo que dibuja el orbe, en pequeño.
    child: Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    ),
  );
}

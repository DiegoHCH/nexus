import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nexus/features/assistant/presentation/orb/orb_geometry.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

class _StateConfig {
  const _StateConfig({
    required this.spin,
    required this.edge,
    required this.dot,
    required this.size,
    required this.halo,
    required this.breathe,
    required this.envelopeSpeed,
  });

  /// Vueltas por segundo (se multiplica por 2π más adelante).
  final double spin;

  /// Opacidad base de las aristas; 0 significa "sin malla".
  final double edge;

  /// Opacidad base de los puntos.
  final double dot;

  /// Multiplicador de tamaño de los puntos.
  final double size;

  /// Intensidad del halo detrás del orbe.
  final double halo;

  /// Amplitud de la respiración (pulso lento de tamaño).
  final double breathe;

  /// A qué velocidad se recorre la envolvente de voz simulada.
  final double envelopeSpeed;
}

const _configs = {
  NexusOrbState.sleep: _StateConfig(
    spin: 0.055,
    edge: 0.00,
    dot: 0.34,
    size: 1.15,
    halo: 0.055,
    breathe: 0.030,
    envelopeSpeed: 0.62,
  ),
  NexusOrbState.listen: _StateConfig(
    spin: 0.170,
    edge: 0.20,
    dot: 0.92,
    size: 1.45,
    halo: 0.150,
    breathe: 0.010,
    envelopeSpeed: 1.60,
  ),
  NexusOrbState.think: _StateConfig(
    spin: 0.520,
    edge: 0.30,
    dot: 0.85,
    size: 1.30,
    halo: 0.110,
    breathe: 0.006,
    envelopeSpeed: 2.40,
  ),
  NexusOrbState.speak: _StateConfig(
    spin: 0.120,
    edge: 0.26,
    dot: 0.98,
    size: 1.55,
    halo: 0.190,
    breathe: 0.008,
    envelopeSpeed: 1.20,
  ),
};

const double _tilt = -0.36;
const double _focal = 3.4;
const int _edgeBuckets = 5;
const int _dotBuckets = 5;

/// Envolvente de voz simulada: determinista (sin aleatoriedad), tres senos
/// batiendo entre sí para que no se note el patrón. Sostiene "listen" y
/// "speak" hasta que en la Fase 2 haya audio real que la reemplace.
double _envelope(double t) {
  final v =
      0.5 +
      0.30 * math.sin(t * 5.1) +
      0.16 * math.sin(t * 11.3 + 1.1) +
      0.10 * math.sin(t * 19.7 + 2.4);
  return v.clamp(0.06, 1.0);
}

/// Pinta el orbe y el horizonte. Portado línea por línea desde el `orb.js`
/// de referencia (esfera de Fibonacci + aristas por radio) combinado con el
/// horizonte del segundo pase de mockups — es la combinación que decidió
/// el tracker: base del sistema con esos dos injertos.
///
/// Las aristas y los puntos se agrupan en [_edgeBuckets]/[_dotBuckets] cubos
/// de opacidad, cada uno con un solo `Path`/`drawRawPoints`: pintar ~250
/// aristas y 140 puntos con una llamada por elemento es la trampa de
/// rendimiento documentada en el tracker.
class NexusOrbPainter extends CustomPainter {
  const NexusOrbPainter({
    required this.state,
    required this.t,
    required this.accent,
    this.showHorizon = true,
  });

  final NexusOrbState state;

  /// Tiempo en segundos, monotónico, con un offset de fase por instancia.
  final double t;

  final Color accent;
  final bool showHorizon;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;

    final cfg = _configs[state]!;
    final cx = w / 2;
    final cy = h * 0.46;
    final r0 = math.min(w, h) * 0.30;
    final env = _envelope(t * cfg.envelopeSpeed);

    final breathePhase = state == NexusOrbState.sleep ? 0.68 : 1.6;
    final breathe = 1 + cfg.breathe * math.sin(t * breathePhase);
    final beat = state == NexusOrbState.speak ? 1 + 0.075 * env : 1.0;
    final r = r0 * breathe * beat;

    _paintHalo(canvas, cx, cy, r, cfg, env);
    if (state == NexusOrbState.speak) _paintConcentricWaves(canvas, cx, cy, r, env);

    final projected = _project(cx, cy, r, cfg, env, state);
    if (cfg.edge > 0) _paintEdges(canvas, projected, cfg.edge);
    _paintDots(canvas, projected, r, cfg);

    if (state == NexusOrbState.think) _paintSweepRings(canvas, cx, cy, r);
    if (state == NexusOrbState.listen) _paintVoiceRing(canvas, cx, cy, r, env);
    if (showHorizon) _paintHorizon(canvas, w, h, cx, cy, env);
  }

  void _paintHalo(Canvas canvas, double cx, double cy, double r, _StateConfig cfg, double env) {
    if (cfg.halo <= 0) return;
    final hr = r * (state == NexusOrbState.speak ? 3.1 : 2.5);
    final haloAlpha = cfg.halo * (state == NexusOrbState.speak ? (0.75 + 0.4 * env) : 1.0);
    final center = Offset(cx, cy);
    // El original (`ctx.createRadialGradient(cx, cy, R*0.35, cx, cy, hr)`) es
    // un gradiente de dos círculos concéntricos: empieza a brillar recién en
    // R*0.35, no en el centro. `Gradient.radial` de Flutter solo dibuja un
    // círculo salvo que se le dé `focal`/`focalRadius` — sin eso el brillo
    // arranca en el centro y se ve más apagado hacia afuera que en el mockup.
    final shader = ui.Gradient.radial(
      center,
      hr,
      [
        accent.withValues(alpha: haloAlpha.clamp(0.0, 1.0)),
        accent.withValues(alpha: (haloAlpha * 0.28).clamp(0.0, 1.0)),
        accent.withValues(alpha: 0),
      ],
      const [0.0, 0.55, 1.0],
      TileMode.clamp,
      null,
      center,
      r * 0.35,
    );
    canvas.drawRect(Rect.fromCircle(center: center, radius: hr), Paint()..shader = shader);
  }

  void _paintConcentricWaves(Canvas canvas, double cx, double cy, double r, double env) {
    for (var q = 0; q < 3; q++) {
      final p = ((t * 0.42) + q / 3) % 1.0;
      final alpha = (0.26 * (1 - p) * (0.5 + env * 0.5)).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(cx, cy),
        r * (1.15 + p * 1.5),
        Paint()
          ..color = accent.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  ({Float64List x, Float64List y, Float64List depth, List<bool> lit}) _project(
    double cx,
    double cy,
    double r,
    _StateConfig cfg,
    double env,
    NexusOrbState state,
  ) {
    final rot = t * cfg.spin * 2 * math.pi;
    final sr = math.sin(rot), cr = math.cos(rot);
    final st = math.sin(_tilt), ct = math.cos(_tilt);
    final squash = state == NexusOrbState.think ? 0.90 : 1.0;
    final sweepY = state == NexusOrbState.think ? math.sin(t * 1.9) : 2.0;

    final points = OrbGeometry.points;
    final n = points.length;
    final px = Float64List(n), py = Float64List(n), depth = Float64List(n);
    final lit = List<bool>.filled(n, false);

    for (var i = 0; i < n; i++) {
      final p = points[i];
      final x1 = p.x * cr + p.z * sr;
      final z1 = -p.x * sr + p.z * cr;
      final y2 = p.y * ct - z1 * st;
      final z2 = p.y * st + z1 * ct;

      var rad = 1.0;
      switch (state) {
        case NexusOrbState.listen:
          rad = 1 + 0.13 * env * math.sin(p.y * 5.5 + t * 6.0);
        case NexusOrbState.think:
          rad = 1 + 0.05 * math.sin(i * 2.1 + t * 7.0);
        case NexusOrbState.speak:
          rad = 1 + 0.09 * env * math.sin(p.y * 3.2 + t * 4.4);
        case NexusOrbState.sleep:
          rad = 1.0;
      }

      final persp = _focal / (_focal - z2);
      px[i] = cx + x1 * r * rad * persp;
      py[i] = cy + y2 * r * rad * squash * persp;
      depth[i] = (z2 + 1) / 2;
      lit[i] = state == NexusOrbState.think && (p.y - sweepY).abs() < 0.14;
    }

    return (x: px, y: py, depth: depth, lit: lit);
  }

  void _paintEdges(
    Canvas canvas,
    ({Float64List x, Float64List y, Float64List depth, List<bool> lit}) proj,
    double edgeAlpha,
  ) {
    final bucketPaths = List.generate(_edgeBuckets, (_) => Path());
    for (final (i, j) in OrbGeometry.edges) {
      final dd = (proj.depth[i] + proj.depth[j]) / 2;
      var alpha = edgeAlpha * (0.18 + dd * 0.95);
      if (proj.lit[i] || proj.lit[j]) alpha = math.min(0.85, alpha + 0.35);
      alpha = alpha.clamp(0.0, 1.0);
      final bucket = (alpha * (_edgeBuckets - 1)).round().clamp(0, _edgeBuckets - 1);
      bucketPaths[bucket]
        ..moveTo(proj.x[i], proj.y[i])
        ..lineTo(proj.x[j], proj.y[j]);
    }
    for (var b = 0; b < _edgeBuckets; b++) {
      final alpha = (b + 0.5) / _edgeBuckets;
      canvas.drawPath(
        bucketPaths[b],
        Paint()
          ..color = accent.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _paintDots(
    Canvas canvas,
    ({Float64List x, Float64List y, Float64List depth, List<bool> lit}) proj,
    double r,
    _StateConfig cfg,
  ) {
    final bucketOffsets = List.generate(_dotBuckets, (_) => <double>[]);
    final n = OrbGeometry.points.length;
    for (var i = 0; i < n; i++) {
      if (proj.lit[i]) continue;
      final bucket = (proj.depth[i] * (_dotBuckets - 1)).round().clamp(0, _dotBuckets - 1);
      bucketOffsets[bucket]
        ..add(proj.x[i])
        ..add(proj.y[i]);
    }
    for (var b = 0; b < _dotBuckets; b++) {
      final offsets = bucketOffsets[b];
      if (offsets.isEmpty) continue;
      final depthMid = (b + 0.5) / _dotBuckets;
      final alpha = (cfg.dot * (0.15 + depthMid * 0.95)).clamp(0.0, 1.0);
      final radius = cfg.size * (0.55 + depthMid * 0.85) * (r / 120 + 0.55);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(offsets),
        Paint()
          ..color = accent.withValues(alpha: alpha)
          ..strokeWidth = math.max(1.0, radius * 2)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Los puntos "iluminados" por el barrido de think son pocos a la vez:
    // se dibujan sueltos, más brillantes, encima de los cubos.
    for (var i = 0; i < n; i++) {
      if (!proj.lit[i]) continue;
      final alpha = math.min(1.0, cfg.dot * (0.15 + proj.depth[i] * 0.95) + 0.4);
      final radius = cfg.size * (0.55 + proj.depth[i] * 0.85) * (r / 120 + 0.55) * 1.5;
      canvas.drawCircle(
        Offset(proj.x[i], proj.y[i]),
        math.max(0.5, radius),
        Paint()..color = accent.withValues(alpha: alpha),
      );
    }
  }

  void _paintSweepRings(Canvas canvas, double cx, double cy, double r) {
    for (var ring = 0; ring < 2; ring++) {
      final ang = t * (ring == 0 ? 2.1 : -1.5) + ring * 1.2;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(ang * 0.5 + ring * 0.8);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: r * (1.22 + ring * 0.22) * 2,
        height: r * (0.30 + ring * 0.16) * 2,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..color = accent.withValues(alpha: 0.34 - ring * 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.restore();
    }
  }

  void _paintVoiceRing(Canvas canvas, double cx, double cy, double r, double env) {
    final path = Path();
    for (var s = 0; s <= 120; s++) {
      final a = (s / 120) * 2 * math.pi;
      final rr = r * (1.34 + 0.13 * env * math.sin(a * 6 + t * 4.2) + 0.05 * math.sin(a * 13 - t * 2.6));
      final x = cx + math.cos(a) * rr, y = cy + math.sin(a) * rr;
      if (s == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.20 + env * 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  /// El horizonte: cambia de *tipo* de línea según el estado, no de color.
  void _paintHorizon(Canvas canvas, double w, double h, double cx, double cy, double env) {
    final hy = cy;
    switch (state) {
      case NexusOrbState.sleep:
        final shader = ui.Gradient.linear(const Offset(0, 0), Offset(w, 0), [
          accent.withValues(alpha: 0),
          accent.withValues(alpha: 0.13),
          accent.withValues(alpha: 0),
        ], const [0.0, 0.5, 1.0]);
        canvas.drawLine(Offset(0, hy), Offset(w, hy), Paint()..shader = shader);

      case NexusOrbState.listen:
        final path = Path();
        for (var x = 0.0; x <= w; x += 3) {
          final fall = math.exp(-math.pow((x - cx) / (w * 0.30), 2));
          final amp = 22 * env * fall;
          final y = hy + math.sin(x * 0.026 + t * 6.2) * amp + math.sin(x * 0.061 - t * 3.4) * amp * 0.42;
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );

      case NexusOrbState.think:
        canvas.drawLine(Offset(0, hy), Offset(w, hy), Paint()..color = accent.withValues(alpha: 0.10));
        final travel = ((t * 0.30) % 1.0) * w;
        final x0 = math.max(0.0, travel - w * 0.16), x1 = math.min(w, travel + w * 0.06);
        final shader = ui.Gradient.linear(Offset(travel - w * 0.16, 0), Offset(travel + w * 0.06, 0), [
          accent.withValues(alpha: 0),
          accent.withValues(alpha: 0.55),
          accent.withValues(alpha: 0),
        ], const [0.0, 0.75, 1.0]);
        canvas.drawLine(Offset(x0, hy), Offset(x1, hy), Paint()..shader = shader..strokeWidth = 1.6);

      case NexusOrbState.speak:
        canvas.drawLine(Offset(0, hy), Offset(w, hy), Paint()..color = accent.withValues(alpha: 0.14));
        final barPaint = Paint()..color = accent.withValues(alpha: 0.34);
        for (var x = 0.0; x <= w; x += 9) {
          final fall = math.exp(-math.pow((x - cx) / (w * 0.34), 2));
          final height = 12 * env * fall * (0.45 + 0.55 * math.sin(x * 0.05 + t * 5.5).abs());
          if (height < 0.7) continue;
          canvas.drawLine(Offset(x, hy - height), Offset(x, hy + height), barPaint);
        }
    }
  }

  @override
  bool shouldRepaint(covariant NexusOrbPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.t != t ||
      oldDelegate.accent != accent ||
      oldDelegate.showHorizon != showHorizon;
}

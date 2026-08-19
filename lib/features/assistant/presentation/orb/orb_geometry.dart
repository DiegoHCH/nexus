import 'dart:math' as math;

/// Un punto en la esfera unitaria del orbe.
class OrbPoint {
  const OrbPoint(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

/// Geometría del orbe: 140 puntos en espiral de Fibonacci (ángulo áureo) y
/// las aristas entre vecinos por **radio**, no por k=3 vecinos más cercanos.
/// El criterio por k=3 (usado en el primer pase de mockups) tiene un bug de
/// deduplicación que deja la malla asimétrica; por radio es simétrico por
/// construcción y no hace falta deduplicar. Se calcula una sola vez: es
/// O(n²) y no cambia entre frames.
abstract final class OrbGeometry {
  static const int pointCount = 140;

  static final List<OrbPoint> points = _buildPoints();
  static final List<(int, int)> edges = _buildEdges();

  static List<OrbPoint> _buildPoints() {
    final goldenAngle = math.pi * (3 - math.sqrt(5));
    return List.generate(pointCount, (i) {
      final y = 1 - (i / (pointCount - 1)) * 2;
      final r = math.sqrt(math.max(0, 1 - y * y));
      final theta = goldenAngle * i;
      return OrbPoint(math.cos(theta) * r, y, math.sin(theta) * r);
    });
  }

  static List<(int, int)> _buildEdges() {
    final threshold = 2.2 * (4 * math.pi / pointCount);
    final result = <(int, int)>[];
    for (var i = 0; i < pointCount; i++) {
      final a = points[i];
      for (var j = i + 1; j < pointCount; j++) {
        final b = points[j];
        final dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
        if (dx * dx + dy * dy + dz * dz < threshold) {
          result.add((i, j));
        }
      }
    }
    return result;
  }
}

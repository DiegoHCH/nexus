import 'package:flutter/foundation.dart';

/// Qué se sabe de la versión publicada.
///
/// `null` en [latest] no es «estás al día»: es **no se pudo preguntar**. Y esas
/// dos cosas no se dicen igual, por lo mismo que en la comprobación de arranque
/// —«no está» y «no se pudo comprobar» piden cosas distintas de quien lee.
@immutable
class ReleaseCheck {
  const ReleaseCheck({required this.current, this.latest});

  /// La que está corriendo, leída del propio paquete.
  final String current;

  /// La última publicada, sin la `v` de la etiqueta. `null` si no se pudo saber.
  final String? latest;

  // Aquí había un `url`, y se fue con el enlace: mientras el aviso solo sabía
  // avisar, la acción era abrir la página de la release en el navegador. Ahora la
  // acción es instalarla, así que un enlace guardado no lo usaría nadie.

  bool get isNewer {
    final publicada = latest;
    if (publicada == null) return false;
    return compare(publicada, current) > 0;
  }

  /// Compara dos versiones por sus números, no como texto.
  ///
  /// Como texto, `0.0.10` es **menor** que `0.0.9` —el `1` va antes del `9`— y el
  /// aviso desaparecería justo al llegar a la décima versión. Se compara tramo a
  /// tramo, y lo que no sea número cuenta como cero: una etiqueta rara no debe
  /// hacer que esto reviente, solo que no destaque.
  static int compare(String a, String b) {
    final unos = _tramos(a);
    final otros = _tramos(b);
    for (var i = 0; i < 3; i++) {
      final diferencia = _en(unos, i) - _en(otros, i);
      if (diferencia != 0) return diferencia;
    }
    return 0;
  }

  static List<int> _tramos(String version) {
    // Se tira la `v` de la etiqueta y cualquier sufijo: `v0.2.0-beta.1` → 0,2,0.
    final limpio = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final numeros = limpio.split(RegExp(r'[-+]')).first;
    return numeros.split('.').map((tramo) => int.tryParse(tramo) ?? 0).toList();
  }

  static int _en(List<int> tramos, int i) => i < tramos.length ? tramos[i] : 0;
}

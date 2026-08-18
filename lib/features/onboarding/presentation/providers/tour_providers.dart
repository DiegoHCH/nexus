import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde está cada pieza del HUD, para poder señalarla.
///
/// Una `GlobalKey` por parada, creadas una vez: el tour necesita el rectángulo
/// **real** de cada widget, no una posición escrita a mano que se quedaría
/// desfasada en cuanto alguien mueva algo — y moverlo es lo normal.
///
/// Cada parada aparece como mucho una vez en pantalla, así que reutilizar la
/// misma clave entre la casa con conversación y la casa vacía es seguro: no
/// están montadas a la vez.
final tourAnchorsProvider = Provider<Map<TourStop, GlobalKey>>(
  (ref) => {for (final stop in TourStop.values) stop: GlobalKey()},
);

/// El rectángulo de una parada, o `null` si no está en pantalla.
///
/// Se pregunta al árbol en vez de guardarse: entre que arranca el tour y se
/// pinta un paso, la ventana puede haberse redimensionado.
Rect? tourRectOf(Map<TourStop, GlobalKey> anchors, TourStop stop) {
  final context = anchors[stop]?.currentContext;
  if (context == null) return null;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// El tour de la primera vez.
///
/// Solo una vez, y **solo lo que está en pantalla**: las paradas se filtran por
/// si su ancla existe, así que la lista se adapta a la casa que le toque —con
/// conversación abierta o vacía— en vez de prometer piezas que no están.
class TourController extends Notifier<TourState> {
  static const _key = 'tour_seen';

  /// Si ya se vio, resuelto desde disco. Arranca en `true` para **no** enseñar
  /// el tour mientras se lee la preferencia: equivocarse hacia «ya lo vio» se
  /// arregla solo en el siguiente arranque; equivocarse al revés te planta un
  /// tour encima cada vez que abres la app.
  var _seen = true;

  @override
  TourState build() {
    unawaited(_load());
    return const TourState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _seen = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Sin preferencias no se insiste: mejor no enseñarlo que enseñarlo cada
      // arranque sin poder recordar que ya se vio.
      _seen = true;
    }
  }

  /// Arranca si toca. Devuelve si arrancó, que es lo que la pantalla necesita
  /// saber para no volver a intentarlo en cada fotograma.
  bool startIfNeeded(List<TourStop> available) {
    if (_seen || state.running || available.isEmpty) return false;
    state = TourState(
      stop: available.first,
      pending: available.skip(1).toList(),
      total: available.length,
    );
    return true;
  }

  void next() {
    final pending = state.pending;
    if (pending.isEmpty) {
      finish();
      return;
    }
    state = TourState(
      stop: pending.first,
      pending: pending.skip(1).toList(),
      total: state.total,
    );
  }

  /// Saltar y terminar hacen lo mismo con la preferencia a propósito: quien lo
  /// salta no quiere verlo, y volver a plantarlo en el siguiente arranque es
  /// ignorar lo que acaba de decir.
  void skip() => finish();

  void finish() {
    state = const TourState();
    _seen = true;
    unawaited(_remember());
  }

  Future<void> _remember() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Se queda visto en esta sesión aunque no se pueda guardar.
    }
  }
}

final tourControllerProvider = NotifierProvider<TourController, TourState>(
  TourController.new,
);

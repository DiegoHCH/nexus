import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde quedó la botonera de la corrida la última vez que se movió.
///
/// **Se guarda porque el asa no sirve de nada si no se recuerda.** Arrastrarla
/// a la esquina que no estorba y encontrarla otra vez en medio al abrir la app
/// es peor que no poder moverla: enseña que moverla no cuenta.
///
/// `null` es «donde nace», no una posición: la de fábrica depende del tamaño de
/// la ventana —abajo a la derecha, encima del compositor— y guardarla resuelta
/// dejaría la botonera fuera de la pantalla en cuanto la ventana se hiciera más
/// pequeña. Ver [LaBotoneraDeCorridas.dondeNace].
class DondeFlotaLaBotonera extends Notifier<Offset?> {
  static const _claveX = 'run.botonera.x';
  static const _claveY = 'run.botonera.y';

  @override
  Offset? build() {
    _cargar();
    return null;
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    // Si la pantalla se fue mientras tanto, el proveedor ya no existe y esto
    // lanzaría en vez de no hacer nada.
    if (!ref.mounted) return;
    final x = prefs.getDouble(_claveX);
    final y = prefs.getDouble(_claveY);
    if (x == null || y == null) return;
    state = Offset(x, y);
  }

  Future<void> mover(Offset donde) async {
    state = donde;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_claveX, donde.dx);
    await prefs.setDouble(_claveY, donde.dy);
  }
}

final dondeFlotaLaBotoneraProvider =
    NotifierProvider<DondeFlotaLaBotonera, Offset?>(DondeFlotaLaBotonera.new);

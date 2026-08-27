import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La carpeta raíz donde viven **los archivos de prueba** de todos los proyectos.
///
/// Se llama «de los flows» y no «de pruebas» porque ya hay una raíz de pruebas y es otra
/// cosa: aquella es donde se guardan **las corridas** —lo que dejó ejecutarlas—. Dos
/// cosas con el mismo nombre en el mismo módulo es como alguien acaba borrando el sitio
/// que no era.
///
/// **Una sola, con una subcarpeta por proyecto.** `~/pruebas/nexus/`,
/// `~/pruebas/front-mobile-b2c/`. Es lo que permite tenerlas todas juntas sin que se
/// mezclen: la separación es la subcarpeta, y quien lista una no ve la otra.
///
/// Y fuera de los repos, que es medio motivo para tenerla: una prueba en un repo del
/// trabajo es un archivo que alguien acaba commiteando sin querer.
///
/// **Vacía de partida a propósito**, igual que la de documentos: escribir en el disco de
/// alguien en un sitio que no ha elegido es justo lo que no se hace aquí. Sin raíz, cada
/// proyecto sigue con la convención de Maestro —`.maestro/` dentro— y nada cambia.
class RaizDeLosFlows extends Notifier<String?> {
  static const _key = 'pruebas.raiz';

  /// Se completa cuando ya se leyó del disco. Mismo motivo que en la carpeta de
  /// documentos: `build()` devuelve `null` y carga después, así que quien pregunte antes
  /// de tiempo recibiría «no hay raíz» teniéndola.
  late final Future<void> cargada;

  @override
  String? build() {
    cargada = _cargar().catchError((Object _) {});
    return null;
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardada = prefs.getString(_key);
    if (guardada != null && guardada.isNotEmpty) state = guardada;
  }

  Future<void> elegir(String? ruta) async {
    final limpia = ruta?.trim();
    final prefs = await SharedPreferences.getInstance();
    if (limpia == null || limpia.isEmpty) {
      await prefs.remove(_key);
      state = null;
      return;
    }
    await prefs.setString(_key, limpia);
    state = limpia;
  }
}

final raizDeLosFlowsProvider = NotifierProvider<RaizDeLosFlows, String?>(
  RaizDeLosFlows.new,
);

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lo que las páginas abiertas en el visor le piden a la app.
///
/// El visor intercepta cualquier `nexus://…` que se pulse dentro de una página
/// y lo reenvía por el canal. Es lo que permite que una página **estática**
/// —sin una línea de JavaScript— tenga botones que hacen algo.
///
/// 🔴 **Existe porque `setMethodCallHandler` es exclusivo por canal.** Lo tenía
/// puesto el controlador de las pruebas e2e, así que la segunda ventana que
/// quisiera un botón se lo quitaba en silencio y rompía la primera. Un
/// despachador y muchos oyentes es la única forma de que las dos convivan.
///
/// El reparto es por **lo que se pide** —el host de la URL—, y la ruta viaja
/// aparte para quien necesite decir además sobre qué: `nexus://detener/<id>`.
abstract final class LoQuePideLaPagina {
  static const _canal = MethodChannel('com.katanalabs.nexus/artifacts');

  static final Map<String, void Function(String ruta)> _oyentes = {};
  static bool _puesto = false;

  /// Atiende [que] —`parar`, `detener`— hasta que alguien lo olvide.
  ///
  /// Uno por petición: dos oyentes de lo mismo serían dos respuestas a un solo
  /// clic, y cuál gana dependería del orden de arranque.
  static void escuchar(String que, void Function(String ruta) alPedirlo) {
    _poner();
    _oyentes[que] = alPedirlo;
  }

  static void olvidar(String que) => _oyentes.remove(que);

  static void _poner() {
    if (_puesto) return;
    _puesto = true;
    _canal.setMethodCallHandler((llamada) async {
      if (llamada.method != 'desdeLaPagina') return null;
      final args = llamada.arguments;
      if (args is! Map) return null;
      final que = args['que'];
      if (que is! String) return null;
      // Sin oyente no pasa nada: una página vieja abierta desde ayer puede
      // pedir algo que ya nadie atiende, y eso no puede lanzar.
      _oyentes[que]?.call(args['ruta'] as String? ?? '');
      return null;
    });
  }

  /// El canal, para que una prueba pueda mandar por él lo que mandaría el
  /// visor. No se expone un ayudante que lo haga porque eso arrastraría
  /// `flutter_test` dentro de `lib/`.
  @visibleForTesting
  static MethodChannel get canal => _canal;

  /// Para las pruebas: deja el despachador como estaba.
  @visibleForTesting
  static void olvidarTodo() {
    _oyentes.clear();
    _puesto = false;
    _canal.setMethodCallHandler(null);
  }
}

import 'dart:async';

/// Convierte un stream que **no se entera** de que lo cancelan en uno que sí.
///
/// 🔴 **Existe por una trampa de Dart, y está medida.** Cancelar la suscripción
/// de un `async*` **no ejecuta sus `finally`**. Se comprobó de las tres formas en
/// que un generador puede estar aparcado —en un `yield*`, en un `await for` y en
/// un `await` que vuelve después de cancelar—, y las tres veces el `finally` no
/// corrió. Solo corre cuando el generador termina **solo**.
///
/// Lo que costó: el `finally` que mata el `claude -p` está escrito desde
/// siempre y no se ejecutaba nunca, porque ese proceso tampoco termina solo —se
/// queda leyendo el stdin que le dejamos abierto para los permisos—. Resultado
/// medido en una máquina de un día normal: **49 procesos vivos y 3,92 GB**, uno
/// por encargo. Y de paso, el botón Detener no detenía nada y cerrar la
/// conversación tampoco.
///
/// El `onCancel` de un `StreamController` **sí** se llama, así que envolver la
/// fuente en uno es lo que hace que cancelar signifique algo.
abstract final class LaSalidaQueSeCancela {
  static Stream<T> de<T>(
    Stream<T> Function() fuente, {
    required Future<void> Function() alCancelar,
  }) {
    late final StreamController<T> salida;
    StreamSubscription<T>? origen;

    salida = StreamController<T>(
      // La fuente no se toca hasta que hay alguien escuchando: arrancarla en el
      // constructor lanzaría el proceso aunque nadie llegara a mirar.
      onListen: () {
        origen = fuente().listen(
          salida.add,
          onError: salida.addError,
          onDone: salida.close,
        );
      },
      // **La contrapresión se conserva**, y no es un detalle: sin esto un
      // consumidor lento dejaría de frenar a la fuente y las líneas del proceso
      // se acumularían en memoria, que es la otra forma de la misma fuga.
      onPause: () => origen?.pause(),
      onResume: () => origen?.resume(),
      onCancel: () async {
        // Primero el remate y después la fuente: cancelar la suscripción de
        // abajo es justamente lo que no despierta al generador, así que
        // esperarlo antes sería esperar a nada.
        await alCancelar();
        await origen?.cancel();
      },
    );

    return salida.stream;
  }
}

/// Mantener el Mac despierto mientras dura algo.
///
/// Se pide y se suelta, como el turno de la cola: [hold] devuelve la función
/// para soltarlo, que hay que llamar **siempre** —también si el encargo falla o
/// se cancela—, porque lo que se queda colgado aquí es la capacidad del Mac de
/// dormirse en toda la sesión.
abstract interface class StaysAwake {
  Future<void Function()> hold(String reason);
}

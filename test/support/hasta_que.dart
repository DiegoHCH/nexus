import 'package:flutter_test/flutter_test.dart';

/// Espera **a que pase algo**, no a que pase un rato — y si se rinde, dice qué
/// estaba viendo.
///
/// 🔴 **Vive aquí porque ya son dos, y las dos eran intermitentes.** Nació en
/// `el_registro_no_pierde_el_documento_test`, que se cae solo dentro de la suite
/// entera; el mismo día el CI tumbó `el_enlace_del_movil_test` —«desconectar
/// mientras reintenta no deja el guardia puesto»— y la causa era de la misma
/// familia: un `Future.delayed` de 30 ms esperando a que un reintento de 10 ms
/// hubiera corrido. En una máquina cargada eso no es tiempo, es una apuesta.
///
/// **Un reloj fijo solo vale en un sentido**, y conviene tenerlo escrito: para
/// comprobar que algo **no** vuelve a pasar sí sirve —una máquina lenta hace que
/// pasen *menos* cosas, no más, así que no puede convertir un verde en un falso
/// verde—. Para esperar a que algo ocurra, no: ahí el reloj solo dice cuánto
/// aguanta la prueba antes de rendirse.
///
/// Por eso el plazo de aquí es **un guardia contra el cuelgue, no una medida**:
/// generoso, y cuando se agota el mensaje lleva el tiempo real, las vueltas y
/// —lo que de verdad diagnostica— [loQueSeVe], que lo escribe quien llama
/// porque es quien sabe qué mirar.
Future<void> hastaQue(
  bool Function() pasa, {
  required String esperando,
  String Function()? loQueSeVe,
  Duration limite = const Duration(seconds: 15),
}) async {
  final desde = DateTime.now();
  final hasta = desde.add(limite);
  var vueltas = 0;
  while (!pasa()) {
    if (DateTime.now().isAfter(hasta)) {
      final tardo = DateTime.now().difference(desde).inMilliseconds;
      fail(
        'no llegó a pasar: $esperando\n'
        'se rindió tras $tardo ms y $vueltas vueltas de espera\n'
        'lo que veía al rendirse: ${loQueSeVe?.call() ?? 'nadie lo contó'}',
      );
    }
    vueltas++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

import 'package:nexus/core/platform/system_power.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';

/// Cuenta cuántos lo necesitan y se lo dice al sistema una sola vez.
///
/// El recuento vive aquí y no en el lado nativo porque es aquí donde se sabe
/// cuántos encargos hay en marcha: tres conversaciones sobre carpetas distintas
/// corren a la vez, y la primera en terminar no puede dejar que el Mac se
/// duerma con las otras dos trabajando. Sin recuento eso pasaría, y pasaría
/// **solo a veces** —cuando la corta acabara antes—, que es la peor forma de
/// que pase.
class StaysAwakeImpl implements StaysAwake {
  StaysAwakeImpl();

  int _holders = 0;

  @override
  Future<void Function()> hold(String reason) async {
    _holders++;
    if (_holders == 1) await SystemPower.keepAwake(reason);

    var released = false;
    return () {
      if (released) return;
      released = true;
      _holders--;
      if (_holders == 0) SystemPower.allowSleep();
    };
  }
}

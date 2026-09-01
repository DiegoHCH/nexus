/// Las dos preguntas que hay que hacerle al sistema para saber si Nexus puede
/// trabajar. Interfaz en el dominio para que la comprobación se pueda probar sin
/// depender de si esta máquina tiene Claude Code instalado — que es justo el
/// caso a cubrir en los dos sentidos.
abstract class ReadinessProbe {
  /// El binario de `claude` está y arranca.
  Future<bool> cliInstalled();

  /// Hay **alguna** cuenta con sesión, no solo la de por defecto.
  ///
  /// «Alguna» y no «la de por defecto» a propósito: quien usa solo perfiles con
  /// nombre —`work`, `private`— tiene el de fábrica sin sesión, y decirle que
  /// inicie sesión sería exactamente el falso negativo de b18.
  ///
  /// 🔴 **`null` es «no se pudo preguntar», y no es lo mismo que `false`.**
  /// Devolvía un `bool` y por eso un CLI que contestaba raro se leía como «no
  /// tienes sesión»: le pasó a la primera persona ajena que instaló la app, con
  /// sesión abierta y `auth status` diciendo `loggedIn: true` en su terminal.
  /// Un `null` llega a la pantalla como `CheckResult.unknown`, que **no bloquea**.
  Future<bool?> anySession();
}

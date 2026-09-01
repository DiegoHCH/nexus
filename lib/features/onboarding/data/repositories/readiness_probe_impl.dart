import 'package:nexus/core/platform/claude_cli.dart';
import 'package:nexus/features/onboarding/domain/repositories/readiness_probe.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';

/// Las dos preguntas, contestadas por donde ya se sabían contestar.
///
/// Se apoya en dos sitios distintos a propósito, porque **no cuestan lo mismo**:
/// el binario y la sesión de la cuenta por defecto se le preguntan al CLI —0,25 s
/// medidos, y de paso puede renovar el token—, mientras que «¿hay alguna otra
/// cuenta?» se resuelve leyendo el llavero, sin arrancar nada.
class ReadinessProbeImpl implements ReadinessProbe {
  ReadinessProbeImpl({ClaudeCli? cli, ClaudeProfilesDataSource? profiles})
    : _cli = cli ?? ClaudeCli(),
      _profiles = profiles ?? const ClaudeProfilesDataSource();

  final ClaudeCli _cli;
  final ClaudeProfilesDataSource _profiles;

  @override
  Future<bool> cliInstalled() => _cli.installed();

  @override
  Future<bool?> anySession() async {
    // Primero la de por defecto, que es la que usa quien no ha separado cuentas.
    final deSiempre = await _cli.sesion(null);
    if (deSiempre == EstadoDeSesion.hay) return true;

    // Y si esa no, cualquiera con nombre. Solo se llega aquí cuando la de
    // fábrica no tiene sesión, así que el coste de listar se paga una vez y en
    // el único camino donde importa.
    final profiles = await _profiles.list();
    if (profiles.any((profile) => profile.signedIn)) return true;

    // 🔴 **Y aquí la diferencia que costó una instalación bloqueada.** Si a la
    // cuenta de siempre no se le pudo preguntar, no se puede afirmar que no haya
    // sesión en ninguna parte: puede que sí y que el CLI contestara raro. `null`
    // significa «no se sabe» y la pantalla no bloquea con eso.
    //
    // Solo se dice «no hay» cuando el CLI **contestó** que no. Ese es el único
    // caso en que mandar a iniciar sesión es un consejo correcto.
    if (deSiempre == EstadoDeSesion.noSeSabe) return null;
    return false;
  }
}

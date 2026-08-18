import 'package:flutter/foundation.dart';

/// El resultado de una comprobación que **puede no tener respuesta**.
///
/// Tres estados y no un `bool` porque «no está» y «no se pudo preguntar» piden
/// cosas distintas de quien lee: la primera se arregla instalando algo, la
/// segunda no se arregla — se vuelve a intentar. Es la misma lección de b18,
/// donde deducir «no hay sesión» de un silencio mandaba a iniciar sesión a
/// gente que ya la tenía.
enum CheckResult { ok, failed, unknown }

/// Si Nexus puede hacer su trabajo, y qué le falta si no.
@immutable
class Readiness {
  const Readiness({
    required this.cli,
    required this.session,
    required this.geminiKey,
  });

  /// El binario de `claude` se resuelve y arranca.
  final CheckResult cli;

  /// Hay al menos una cuenta de Claude con sesión.
  final CheckResult session;

  /// La llave de Gemini está guardada. Es un `bool` porque se lee del llavero
  /// de la propia app: o está o no está, no hay tercer caso.
  final bool geminiKey;

  /// Si hay que interponerse antes de dejar entrar.
  ///
  /// **Solo cuando se sabe que falta algo.** Un `unknown` no bloquea: decirle a
  /// alguien que no tiene Claude Code cuando no hemos podido preguntárselo es
  /// peor que dejarle pasar y que falle el encargo — ahí al menos el error lo
  /// da el CLI, que sabe de qué habla.
  ///
  /// La llave de Gemini no entra: sin ella se puede trabajar por texto, y su
  /// ausencia ya tiene su propia pantalla desde 2.6.
  bool get blocksWork =>
      cli == CheckResult.failed || session == CheckResult.failed;
}

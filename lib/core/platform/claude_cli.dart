import 'dart:convert';
import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';

/// Lo que se le puede preguntar al CLI **sobre sí mismo**: si está y si esa
/// cuenta tiene sesión.
///
/// Vive en `core` y no dentro de una feature porque lo van a usar dos: el
/// arranque, para no dejar entrar a una app que no puede trabajar, y el lector
/// del cupo, que ya lo necesitaba. Ahí estaba enterrado como método privado, y
/// dos copias de esto se separan en cuanto una cambie.
///
/// El lanzador se inyecta para poder probarlo: con `Process.run` de verdad, la
/// prueba dependería de que la máquina tenga —o no tenga— Claude Code
/// instalado, que es justo el caso que hay que cubrir en los dos sentidos.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class ClaudeCli {
  ClaudeCli({ProcessRunner? run}) : _run = run ?? Process.run;

  final ProcessRunner _run;

  /// Si el binario se resuelve **y arranca**.
  ///
  /// Se le pide la versión en vez de buscarlo con `which`: lo que importa no es
  /// que el archivo exista, es que se pueda ejecutar. Y se lanza con el PATH
  /// inyectado porque una app de GUI no hereda el de una shell — es la trampa
  /// de `v3`, y sin eso esto diría «no está instalado» en un Mac donde sí lo
  /// está.
  Future<bool> installed() async {
    try {
      final result = await _run('claude', [
        '--version',
      ], environment: ClaudeEnvironment.forTools());
      return result.exitCode == 0;
    } on Exception {
      return false;
    }
  }

  /// Si esa cuenta tiene sesión, **según el CLI**.
  ///
  /// Se le pregunta a él y no se deduce del llavero porque el llavero solo dice
  /// cuándo vence el acceso, no si hay cuenta: con el acceso vencido y el
  /// refresco bueno —lo normal tras unas horas sin usarla— mirar la caducidad
  /// concluye «no hay sesión», que es falso.
  ///
  /// `auth status --json` contesta en **0,25 s medidos**. Y de paso puede hacer
  /// que el CLI renueve el token, que es justo lo que nos vendría bien.
  Future<bool> loggedIn(String? configDir) async {
    try {
      final result = await _run('claude', [
        'auth',
        'status',
        '--json',
      ], environment: ClaudeEnvironment.forProfile(configDir));
      if (result.exitCode != 0) return false;
      final decoded = jsonDecode((result.stdout as String).trim());
      return decoded is Map<String, dynamic> && decoded['loggedIn'] == true;
    } on Exception {
      // Sin CLI alcanzable no se puede afirmar que no haya sesión, pero tampoco
      // leer el cupo. Se trata como «no hay sesión» porque es el único caso en
      // que el usuario tiene algo que hacer —iniciarla—, y equivocarse aquí
      // solo cuesta una frase, no un dato falso.
      return false;
    }
  }
}
